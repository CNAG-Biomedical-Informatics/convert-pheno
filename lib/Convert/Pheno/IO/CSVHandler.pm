package Convert::Pheno::IO::CSVHandler;

use strict;
use warnings;
use autodie;
use feature qw(say);
use File::Basename;
use Text::CSV_XS           qw(csv);
use Sort::Naturally        qw(nsort);
use List::Util             qw(any);
use File::Spec::Functions  qw(catdir);
use IO::Compress::Gzip     qw($GzipError);
use IO::Uncompress::Gunzip qw($GunzipError);

use Data::Dumper;
use Devel::Size qw(total_size);
use Convert::Pheno;
use Convert::Pheno::IO::FileIO;
use Convert::Pheno::OMOP::Definitions;
use Convert::Pheno::OMOP;
use Convert::Pheno::Utils::Schema;
use Convert::Pheno::Utils::Mapping;
use Exporter 'import';
our @EXPORT =
  qw(read_csv read_csv_stream read_redcap_dict_file read_mapping_file read_sqldump read_sqldump_stream sqldump2csv transpose_omop_data_structure write_csv open_filehandle load_exposures get_headers convert_table_aoh_to_hoh);

use constant DEVEL_MODE => 0;

#########################
#########################
#  SUBROUTINES FOR CSV  #
#########################
#########################

sub read_redcap_dictionary {
    my $filepath = shift;

    # Define split record separator from file extension
    my ( $separator, $encoding ) = define_separator( $filepath, undef );

    # We'll create an HoH using as 1D-key the 'Variable / Field Name'
    my $key = 'Variable / Field Name';

    # We'll be adding the key <_labels>. See sub add_labels
    my $labels = 'Choices, Calculations, OR Slider Labels';

    # Loading data directly from Text::CSV_XS
    # NB1: We want HoH and sub read_csv returns AoH
    # NB2: By default the Text::CSV module treats all fields in a CSV file as strings, regardless of their actual data type.
    # NB3: csv function ~ x2  RAM. It's ok here.
    my $hoh = csv(
        in       => $filepath,
        sep_char => $separator,

        #binary    => 1, # default
        auto_diag => 1,
        encoding  => $encoding,
        key       => $key,
        on_in     => sub { $_{_labels} = add_labels( $_{$labels} ) }
    );

    return $hoh;
}

sub add_labels {
    my $value = shift;

    # *** IMPORTANT ***
    # This sub can return undef, i.e., $_{labels} = undef
    # That's OK as we won't perform exists $_{_label}
    # Note that in $hoh (above) empty columns are  key = ''.

    # Premature return if empty ('' = 0)
    return undef unless $value;    # perlcritic Severity: 5

    # We'll skip values that don't provide even number of key-values
    my @tmp = map { s/^\s//; s/\s+$//; $_; } ( split /\||,/, $value );    # perlcritic Severity: 5

    # Return undef for non-valid entries
    return @tmp % 2 == 0 ? {@tmp} : undef;
}

sub read_redcap_dict_file {
    my $arg = shift;

    # Read and load REDCap CSV dictionary
    return read_redcap_dictionary( $arg->{redcap_dictionary} );
}

sub read_mapping_file {
    my $arg = shift;

    # Read and load mapping file
    my $data_mapping_file =
      io_yaml_or_json( { filepath => $arg->{mapping_file}, mode => 'read' } );

    # Validate mapping file against JSON schema
    my $jv = Convert::Pheno::Utils::Schema->new(
        {
            data        => $data_mapping_file,
            debug       => $arg->{self_validate_schema},
            schema_file => $arg->{schema_file}
        }
    );
    $jv->json_validate;

    # Remap for quick looukup
    remap_assignTermIdFromHeader($data_mapping_file);

    # Return if succesful
    return $data_mapping_file;
}

sub read_sqldump {
    my $arg      = shift;
    my $filepath = $arg->{in};
    my $self     = $arg->{self};

    # Before resorting to writting this subroutine I performed an exhaustive search on CPAN:
    # - Tested MySQL::Dump::Parser::XS but I could not make it work...
    # - App-MysqlUtils-0.022 has a CLI utility (mysql-sql-dump-extract-tables)
    # - Of course one can always use *nix tools (sed, grep, awk, etc) or other programming languages....
    # Anyway, I ended up writting the parser myself...

    # Define variables that modify what we load
    my $max_lines_sql = $self->{max_lines_sql};
    my @omop_tables   = @{ $self->{omop_tables} };

    #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, attribute_description, attribute_type_concept_id, attribute_syntax) FROM stdin;
    # ......
    # \.

    # Verbose
    say "Reading the SQL dump...\n" if $self->{verbose};

    # Start reading the SQL dump
    my $fh = open_filehandle( $filepath, 'r' );

    # Determine the print interval based on file size
    my $print_interval = get_print_interval($filepath);

    # We'll store the data in the hashref $data
    my $data = {};

    # Now we we start processing line by line
    my $switch      = 0;
    my $local_count = 0;
    my $total_count = 0;
    my @headers;
    my $headers_data_structure;
    my $table_name;

    while ( my $line = <$fh> ) {

        if ( $line =~ m/^COPY/ ) {

            chomp $line;

            # First line contains the headers
            #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, ..., attribute_syntax) FROM stdin;

            # Create an array to hold the column names for this table
            $line =~ s/[\(\),]//g;    # getting rid of (),
            @headers = split /\s+/, $line;

            $table_name = uc( ( split /\./, $headers[1] )[1] );    # ATTRIBUTE_DEFINITI

            # Discarding non @$omop_tables:
            # This step improves RAM consumption
            next unless any { $_ eq $table_name } @omop_tables;

            # Discarding headers which are not terms/variables
            @headers = @headers[ 2 .. $#headers - 2 ];

            # Turning on the switch for later
            $switch = 1;

            # Reset count
            $local_count = 0;

            # Initializing $data>key as empty arrayref
            $data->{$table_name} = [];

            # Loading headers
            $headers_data_structure->{$table_name} = [@headers];

            # Jump one line
            $line = <$fh>;

            # Say if verbose
            say "Loading <$table_name> in memory..."
              if $self->{verbose};

        }

        # Loading the data if $switch
        if ($switch) {

            chomp $line;

            # Order matters. We exit before loading
            if ( $local_count == $max_lines_sql || $line =~ /^\\\.$/ ) {
                $switch = 0;
                print "==============\nRows read(total): $local_count\n\n"
                  if $self->{verbose};
                next;
            }
            $local_count++;
            $total_count++;

            # Columns are separated by \t
            # NB: 'split' and 'Text::CSV' split to strings
            # We go with 'split'. Coercing a posteriori
            my @fields = split /\t/, $line;

            # Loading the fields like this:
            #
            #  $VAR1 = {
            #  'PERSON' => [  # NB: This is the table name
            #             {
            #              'person_id' => 123,
            #               'test' => 'abc'
            #             },
            #             {
            #               'person_id' => 456,
            #               'test' => 'def'
            #             }
            #           ]
            #         };

            # Using tmp hashref to load all fields at once with slice
            my $hash_slice;
            @{$hash_slice}{@headers} =
              map { dotify_and_coerce_number($_) } @fields;

            # Adding them as an array element (AoH)
            push @{ $data->{$table_name} }, $hash_slice;

            # Print
            say "Rows read: $local_count"
              if ( $self->{verbose} && $local_count % $print_interval == 0 );
        }
    }
    close $fh;

    # Print if verbose
    print
"==========================\nRows read (sqldump-total): $total_count\n==========================\n\n"
      if $self->{verbose};

    # RAM Usage
    say ram_usage_str( 'read_sqldump', $data )
      if ( DEVEL_MODE || $self->{verbose} );

    return ( $data, $headers_data_structure );
}

sub read_sqldump_stream {
    my $arg           = shift;
    my $filein        = $arg->{in};
    my $self          = $arg->{self};
    my $person        = $arg->{person};
    my $fileout       = $self->{out_file};
    my $table_name    = $self->{omop_tables}[0];
    my $table_name_lc = lc($table_name);

    # Define variables that modify what we load
    my $max_lines_sql = $self->{max_lines_sql};

    # Open filehandles
    my $fh_in  = open_filehandle( $filein,  'r' );
    my $fh_out = open_filehandle( $fileout, 'a' );

    # Determine the print interval based on file size
    my $print_interval = get_print_interval($filein);

    # Start printing the array
    #say $fh_out "[";

    # Now we we start processing line by line
    my $count  = 0;
    my $switch = 0;
    my @headers;

    while ( my $line = <$fh_in> ) {

        # Only parsing $table_name_lc and discarding others
        # Note that double quotes are optional
        # - COPY "OMOP_cdm_eunomia".person
        # . COPY omop_cdm_eunomia_2.person
        if ( $line =~ /^COPY \"?(\w+)\"?\.$table_name_lc / ) {
            chomp $line;

            # Create an array to hold the column names for this table
            $line =~ s/[\(\),]//g;    # getting rid of (),
            @headers = split /\s+/, $line;

            # Discarding headers which are not terms/variables
            @headers = @headers[ 2 .. $#headers - 2 ];

            # Turning on the switch for later
            $switch++;

            # Jump one line
            $line = <$fh_in>;

        }

        # Loading the data if $switch
        if ($switch) {

            # get rid of \n
            chomp $line;

            # Order matters. We exit before loading
            last if $line =~ /^\\\.$/;

            # Splitting by tab, it's ok
            my @fields = split /\t/, $line;

            # Using tmp hashref to load all fields at once with slice
            my $hash_slice;
            @{$hash_slice}{@headers} =
              map { dotify_and_coerce_number($_) } @fields;

            # Error related to -max-lines-sqlError related to -max-lines-sql
            die
"We could not find person_id:$hash_slice->{person_id}. Try increasing the #lines with --max-lines-sql\n"
              unless exists $person->{ $hash_slice->{person_id} };

            # Increase counter
            $count++;

            # Encode data
            my $encoded_data =
              encode_omop_stream( $table_name, $hash_slice, $person, $count,
                $self );

            # Only after encoding we are able to discard 'null'
            say $fh_out $encoded_data if $encoded_data ne 'null';

            # adhoc filter to speed-up development
            last if $count == $max_lines_sql;

            # Print if verbose
            say "Rows processed: $count"
              if ( $self->{verbose} && $count % $print_interval == 0 );
        }
    }
    say "==============\nRows processed(total): $count\n" if $self->{verbose};

    #say $fh_out "]"; # not needed

    # Closing filehandles
    close $fh_in;
    close $fh_out;
    return 1;
}

sub encode_omop_stream {
    my ( $table_name, $hash_slice, $person, $count, $self ) = @_;

    # *** IMPORTANT ***
    # Table PERSON only has 1 individual
    my $person_id = $hash_slice->{person_id};
    my $data      = {
        $table_name => [$hash_slice],
        PERSON      => $count == 1
        ? $person->{$person_id}
        : {
            map { $_ => $person->{$person_id}{$_} }
              qw(person_id gender_concept_id birth_datetime)
        }
    };

    # Obtain
    my $stream = Convert::Pheno::omop2bff_stream_processing( $self, $data );

    # Return JSON string
    #  - canonical has some overhead but needed for t/)
    #  - $fh is already utf-8, no need to encode again here
    return JSON::XS->new->canonical->encode($stream);
}

sub sqldump2csv {
    my ( $data, $dir, $sql_headers_data_structure ) = @_;

    # CSV separator (tab character)
    my $sep = "\t";

    # Natural sort flag: set to 0 (off) by default.
    my $sort = 0;

    # Iterate over each table in the data hash.
    for my $table ( keys %{$data} ) {

        # Build the file path for the CSV file.
        my $filepath = catdir( $dir, "$table.csv" );

        # Retrieve header fields for the current table.
        my $table_headers = $sql_headers_data_structure->{$table};
        die "No header data found for table '$table'"
          unless defined $table_headers && @$table_headers;

        # Determine header order: natural sort if enabled, or as stored.
        my $headers =
          $sort
          ? [ nsort( @{$table_headers} ) ]
          : $table_headers;

        # Write the CSV file using the specified separator, headers, and data.
        write_csv(
            {
                sep      => $sep,
                filepath => $filepath,
                headers  => $headers,
                data     => $data->{$table},
            }
        );
    }
    return 1;
}

sub transpose_omop_data_structure {
    my ( $self, $data ) = @_;

    # The situation is the following, $data comes in format:
    #
    #$VAR1 = {
    #          'MEASUREMENT' => [
    #                             {
    #                               'measurement_concept_id' => 1,
    #                               'person_id' => 666
    #                             },
    #                             {
    #                               'measurement_concept_id' => 2,
    #                               'person_id' => 666
    #                             }
    #                           ],
    #          'PERSON' => [
    #                        {
    #                          'person_id' => 666
    #                        },
    #                        {
    #                          'person_id' => 1
    #                        }
    #                      ]
    #        };

    # where all 'person_id' are together inside the TABLE_NAME.
    # But, BFF "ideally" works at the individual level so we are going to
    # transpose the data structure to end up into something like this
    # NB: MEASUREMENT and OBSERVATION (among others, i.e., CONDITION_OCCURRENCE, PROCEDURE_OCCURRENCE)
    #     can have multiple values for one 'person_id' so they will be loaded as arrays
    #
    #
    #$VAR1 = {
    #          '1' => {
    #                     'PERSON' => {
    #                                   'person_id' => 1
    #                                 }
    #                   },
    #          '666' => {
    #                     'MEASUREMENT' => [
    #                                        {
    #                                          'measurement_concept_id' => 1,
    #                                          'person_id' => 666
    #                                        },
    #                                        {
    #                                          'measurement_concept_id' => 2,
    #                                          'person_id' => 666
    #                                        }
    #                                      ],
    #                     'PERSON' => {
    #                                   'person_id' => 666
    #                                 }
    #                   }
    #        };

    # Debug messages
    say "> Transposing OMOP data..." if $self->{debug};
    my $omop_person_id = {};

    # Only performed for $omop_main_table
    for my $table ( @{ $omop_main_table->{$omop_version} } ) {    # global

        # We void the table when reading to avoid data duplication in RAM
        while ( my $item = shift @{ $data->{$table} } ) {         # We want to keep order (!pop)

            if ( exists $item->{person_id} && $item->{person_id} ) {
                my $person_id = $item->{person_id};

                # {person_id} can have multiple rows in @omop_array_tables
                if ( any { $_ eq $table } @omop_array_tables ) {
                    push @{ $omop_person_id->{$person_id}{$table} }, $item;    # array
                }

                # {person_id} only has one value in a given table
                else {
                    $omop_person_id->{$person_id}{$table} = $item;             # scalar
                }
            }
        }
    }

    # To get any unused memory back to Perl
    $data = undef;

    # Finally we get rid of the 'person_id' key and return values as an array
    #
    #$VAR1 = [
    #          {
    #            'PERSON' => {
    #                          'person_id' => 1
    #                        }
    #          },
    # ------------------------------------------------
    #          {
    #            'MEASUREMENT' => [
    #                               {
    #                                 'measurement_concept_id' => 1,
    #                                 'person_id' => 666
    #                               },
    #                               {
    #                                 'measurement_concept_id' => 2,
    #                                 'person_id' => 666
    #                               }
    #                             ],
    #            'PERSON' => {
    #                          'person_id' => 666
    #                        }
    #          }
    #        ];
    # NB: We nsort keys to always have the same result but it's not needed
    say "> Sorting OMOP data by <person_id>..." if $self->{debug};

    my $aoh;
    for my $key ( nsort keys %{$omop_person_id} ) {
        push @{$aoh}, $omop_person_id->{$key};
        delete $omop_person_id->{$key};    # To avoid data duplication
    }

    # RAM usage
    say ram_usage_str( 'transpose_omop_data_structure', $aoh )
      if ( DEVEL_MODE || $self->{verbose} );

    return $aoh;
}

sub read_csv {
    my $arg      = shift;
    my $filepath = $arg->{in};
    my $sep      = $arg->{sep};
    my $self     = exists $arg->{self} ? $arg->{self} : { verbose => 0 };

    # Define split record separator from file extension
    my ( $separator, $encoding ) = define_separator( $filepath, $sep );

    # *** IMPORTANT ***
    # Text::CSV_XS functional interface
    # duplicates RAM <= DEPRECATED
    #my $aoh = csv(
    #    in       => $filepath,
    #    sep_char => $separator,
    #    headers  => "auto",
    #    encoding  => $encoding,
    #    auto_diag => 1
    #);

    # Create a new Text::CSV_XS object
    my $csv = Text::CSV_XS->new(
        {
            sep_char  => $separator,
            binary    => 1,
            auto_diag => 1,
        }
    );

    # Open fh
    my $fh = open_filehandle( $filepath, 'r' );

    # Determine the print interval based on file size
    my $print_interval = get_print_interval($filepath);

    # Get headers
    my $headers = $csv->getline($fh);
    $csv->column_names(@$headers);

    # Check for too many occurrences of separators
    die
      "Are you sure you are using the right --sep <$separator> for your data?\n"
      if is_separator_incorrect($headers);

    # Load data
    my @aoh;
    my $count = 0;
    while ( my $row = $csv->getline_hr($fh) ) {
        push @aoh, $row;
        $count++;

        say "Rows read: $count"
          if ( $self->{verbose} && $count % $print_interval == 0 );

    }

    # Close fh
    close $fh;

    # Print if verbose
    print
"==========================\nRows read (total): $count\n==========================\n\n"
      if $self->{verbose};

    # Coercing the data before returning it
    for my $item (@aoh) {
        for my $key ( @{$headers} ) {
            $item->{$key} = dotify_and_coerce_number( $item->{$key} );
        }
    }

    # RAM usage
    say ram_usage_str( "read_csv($filepath)", \@aoh )
      if ( DEVEL_MODE || $self->{verbose} );

    # Return data
    return \@aoh;
}

sub is_separator_incorrect {
    my $keys           = shift;
    my $max_delimiters = 5;

    # Count the number of delimiters (comma, semicolon, or tab) in the first key
    my $sep_count = ( $keys->[0] =~ tr/,;\t// );

    # Return true (1) if the number of delimiters exceeds the maximum allowed, otherwise false (0)
    return $sep_count > $max_delimiters ? 1 : 0;
}

sub read_csv_stream {
    my $arg     = shift;
    my $filein  = $arg->{in};
    my $self    = $arg->{self};
    my $sep     = $arg->{sep};
    my $person  = $arg->{person};
    my $fileout = $self->{out_file};

    # Define split record separator
    my ( $separator, $encoding, $table_name ) =
      define_separator( $filein, $sep );
    my $table_name_lc = lc($table_name);

    # Create a new Text::CSV_XS object
    my $csv = Text::CSV_XS->new(
        {
            sep_char  => $separator,
            binary    => 1,
            auto_diag => 1,
        }
    );

    # Open filehandles
    my $fh_in  = open_filehandle( $filein,  'r' );
    my $fh_out = open_filehandle( $fileout, 'a' );

    # Get headers
    my $headers = $csv->getline($fh_in);

    # *** IMPORTANT ***
    # On Feb-19-2023 I tested Parallel::ForkManager and:
    # 1 - The performance was by far slower than w/o it
    # 2 - We hot SQLite errors for concurring fh
    # Thus, it was not implemented

    my $count = 0;

    while ( my $row = $csv->getline($fh_in) ) {

        # Load the values as a hash slice
        my %hash_slice;
        @hash_slice{@$headers} = map { dotify_and_coerce_number($_) } @$row;

        # Encode data
        my $encoded_data =
          encode_omop_stream( $table_name, \%hash_slice, $person, $count,
            $self );

        # Only after encoding we are able to discard 'null'
        say $fh_out $encoded_data if $encoded_data ne 'null';

        # Increment $count
        $count++;

        # Verbose logging every 10,000 rows
        if ( $self->{verbose} && $count % 10_000 == 0 ) {
            say "Rows processed: $count";
        }
    }
    say "==============\nRows total:     $count\n" if $self->{verbose};

    close $fh_in;
    close $fh_out;
    return 1;
}

sub write_csv {
    my $arg      = shift;
    my $sep      = $arg->{sep};
    my $data     = $arg->{data};
    my $filepath = $arg->{filepath};
    my $headers  = $arg->{headers};

    # Ensure $data is an array reference of hashes
    if ( ref $data eq 'HASH' ) {
        $data = [$data];    # Convert to an array reference containing one hash
    }

    my @exts = qw(.csv .tsv);
    my $msg =
      qq(Can't recognize <$filepath> extension. Extensions allowed are: )
      . ( join ',', @exts ) . "\n";
    my ( undef, undef, $ext ) = fileparse( $filepath, @exts );
    die $msg unless any { $_ eq $ext } @exts;

    # Use Text::CSV_XS to write to CSV, ensuring $data is always an AoH
    csv(
        in       => $data,       # This now can be an AoH or a single hash converted to AoH
        out      => $filepath,
        sep_char => $sep,
        eol      => "\n",
        encoding => 'UTF-8',
        headers  => $headers     # Ensure headers are defined or auto-detection is enabled
    );
    return 1;
}

sub open_filehandle {
    my ( $filepath, $mode ) = @_;
    my $handle = $mode eq 'a' ? '>>' : $mode eq 'w' ? '>' : '<';
    my $fh;
    if ( $filepath =~ /\.gz$/ ) {
        if ( $mode eq 'a' || $mode eq 'w' ) {
            $fh = IO::Compress::Gzip->new( $filepath,
                Append => ( $mode eq 'a' ? 1 : 0 ) );
        }
        else {
            $fh = IO::Uncompress::Gunzip->new( $filepath, MultiStream => 1 );
        }
        binmode( $fh, ":encoding(UTF-8)" );
    }
    else {
        open $fh, qq($handle:encoding(UTF-8)), $filepath;
    }
    return $fh;
}

sub define_separator {
    my ( $filepath, $sep ) = @_;

    # Define split record separator from file extension
    my @exts = map { $_, $_ . '.gz' } qw(.csv .tsv .sql .txt);
    my ( $table_name, undef, $ext ) = fileparse( $filepath, @exts );

    # Defining separator character
    my $separator =
        $sep
      ? $sep
      : $ext eq '.csv'    ? ';'     # Note we don't use comma but semicolon
      : $ext eq '.csv.gz' ? ';'     # idem
      : $ext eq '.tsv'    ? "\t"
      : $ext eq '.tsv.gz' ? "\t"
      :                     "\t";

    my $encoding =
      $ext =~ m/\.gz/ ? ':gzip:encoding(utf-8)' : 'encoding(utf-8)';

    # Return 3 but some get only 2
    return ( $separator, $encoding, $table_name );
}

sub to_gb {
    my $bytes = shift;

    # base 2 => 1,073,741,824
    my $gb = $bytes / 1_073_741_824;
    return sprintf( '%9.4f', $gb ) . ' GB';
}

sub ram_usage_str {
    my ( $func, $data ) = @_;
    return qq/***RAM Usage***($func):/ . to_gb( total_size($data) ) . "\n";
}

sub load_exposures {
    my $data = read_csv( { in => shift, sep => "\t" } );

    # We will only use the key 'concept_id' and discard the rest
    #$VAR1 = {
    #      '4138352' => 1
    #    };
    my %hash = map { $_->{concept_id} => 1 } @$data;

    # Returning hashref
    return \%hash;
}

sub get_headers {
    my $data = shift;

    # Ensure $data is an array reference, wrap it in an array if it's a hash reference.
    $data = [$data] unless ref $data eq 'ARRAY';

    # Step 1 & 2: Collect all unique keys from all hashes, ignoring hash references.
    my %all_keys;
    foreach my $row (@$data) {
        foreach my $key ( keys %$row ) {

            # Skip any key where the value is a reference (including hash references)
            # Why?
            # In pxf2csv I encountered HASH(foobarbaz) as header. This is actually
            # a deeper issue I have to investigate
            next if ref $row->{$key};
            $all_keys{$key} = ();
        }
    }

    # Step 3: Sort keys for consistency.
    my @headers = sort keys %all_keys;
    return \@headers;
}

sub remap_assignTermIdFromHeader {
    my $hash = shift;
    for my $key (%$hash) {
        if ( exists $hash->{$key}{assignTermIdFromHeader} ) {
            $hash->{$key}{assignTermIdFromHeader_hash} =
              array_ref_to_hash( $hash->{$key}{assignTermIdFromHeader} );
        }
    }
    return 1;
}

sub array_ref_to_hash {
    my $array_ref = shift;

    # Check if the input is an array reference
    die "Expected an array reference at <assignTermIdFromHeader>"
      unless ref($array_ref) eq 'ARRAY';

    my %hash;

    # Iterate over the elements of the array reference
    foreach my $element ( @{$array_ref} ) {
        $hash{$element} = 1;
    }
    return \%hash;
}

sub convert_table_aoh_to_hoh {
    my ( $data, $table, $self ) = @_;

    my %table_cursor =
      map { $_ => $data->{$_} } qw(CONCEPT PERSON VISIT_OCCURRENCE);
    my %table_id = (
        CONCEPT          => 'concept_id',
        PERSON           => 'person_id',
        VISIT_OCCURRENCE => 'visit_occurrence_id'
    );
    my $array_ref = $table_cursor{$table};
    my $id        = $table_id{$table};

    ###########
    # CONCEPT #
    ###########

    # $VAR1 = [
    #          {
    #            'concept_class_id' => '4-char billing code',
    #            'concept_code' => 'K92.2',
    #            'concept_id' => 35208414,
    #            'concept_name' => 'Gastrointestinal hemorrhage, unspecified',
    #            'domain_id' => 'Condition',
    #            'invalid_reason' => undef,
    #            'standard_concept' => undef,
    #            'valid_end_date' => '2099-12-31',
    #            'valid_start_date' => '2007-01-01',
    #            'vocabulary_id' => 'ICD10CM'
    #          },
    #
    # and we convert it to hash to allow for quick searches by 'concept_id'
    #
    # $VAR1 = {
    #          '1107830' => {
    #                         'concept_class_id' => 'Ingredient',
    #                         'concept_code' => 28889,
    #                         'concept_id' => 1107830,
    #                         'concept_name' => 'Loratadine',
    #                         'domain_id' => 'Drug',
    #                         'invalid_reason' => undef,
    #                         'standard_concept' => 'S',
    #                         'valid_end_date' => '2099-12-31',
    #                         'valid_start_date' => '1970-01-01',
    #                         'vocabulary_id' => 'RxNorm'
    #                         },
    #
    # NB: We store all columns yet we'll use 4:
    # 'concept_id', 'concept_code', 'concept_name', 'vocabulary_id'

    ####################
    # VISIT_OCCURRENCE #
    ####################

    # Going from
    #$VAR1 = [
    #        {
    #          'admitting_source_concept_id' => 0,
    #          'visit_occurrence_id' => 85,
    #          ...
    #        }
    #      ];

    # To
    #$VAR1 = {
    #        '85' => {
    #                  'admitting_source_concept_id' => 0,
    #                  'visit_occurrence_id' => 85,
    #                  ...
    #                }
    #      };

    # Initialize the new hash for transformed data
    my $hoh = {};

    # Iterate over the array and build the hash while clearing the array
    while ( my $item = pop @{$array_ref} ) {    #faster than shift (order irrelevant here)
        my $key = $item->{$id};                 # avoid stringfication
        $hoh->{$key} = $item;
    }

    # The original array @{ $self->{data}{$table} is now empty
    # RAM Usage
    say ram_usage_str( "convert_table_aoh_to_hoh($table)", $hoh )
      if ( $self->{verbose} || DEVEL_MODE );

    return $hoh;
}

sub get_print_interval {
    my $filepath = shift;

    # Determine file size
    my $file_size = -s $filepath;

    # Set print interval based on file size (threshold: 10 MB)
    my $print_interval = $file_size > 10 * 1024 * 1024 ? 10_000 : 1_000;

    return $print_interval;
}

1;
