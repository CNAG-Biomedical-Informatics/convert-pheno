package Convert::Pheno::CSV;

use strict;
use warnings;
use autodie;
use feature qw(say);
use File::Basename;
use Text::CSV_XS          qw(csv);
use Sort::Naturally       qw(nsort);
use List::Util            qw(any);
use File::Spec::Functions qw(catdir);

#use Parallel::ForkManager;
use Convert::Pheno;
use Convert::Pheno::OMOP;
use Convert::Pheno::IO;
use Convert::Pheno::Schema;
use Exporter 'import';
our @EXPORT =
  qw(read_csv read_csv_stream read_redcap_dic_and_mapping_file remap_ohdsi_dictionary read_sqldump_stream read_sqldump  sqldump2csv transpose_omop_data_structure);

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

    # NB: We want HoH and sub read_csv returns AoH
    # Loading data directly from Text::CSV_XS
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

    #############
    # IMPORTANT #
    #############
    # This sub can return undef, i.e., $_{labels} = undef
    # That's OK as we won't perform exists $_{_label}
    # Note that in $hoh (above) empty columns are  key = ''.

    # Premature return if empty ('' = 0)
    return undef unless $value;

    # We'll skip values that don't provide even number of key-values
    my @tmp = map { s/^\s//; s/\s+$//; $_; } ( split /\||,/, $value );

    # Return undef for non-valid entries
    return @tmp % 2 == 0 ? {@tmp} : undef;
}

sub read_redcap_dic_and_mapping_file {

    my $arg = shift;

    # Read and load REDCap CSV dictionary
    my $data_redcap_dic = read_redcap_dictionary( $arg->{redcap_dictionary} );

    # Read and load mapping file
    my $data_mapping_file =
      io_yaml_or_json( { filepath => $arg->{mapping_file}, mode => 'read' } );

    # Validate mapping file against JSON schema
    my $jv = Convert::Pheno::Schema->new(
        {
            data        => $data_mapping_file,
            debug       => $arg->{self_validate_schema},
            schema_file => $arg->{schema_file}
        }
    );
    $jv->json_validate;

    # Return if succesful
    return ( $data_redcap_dic, $data_mapping_file );
}

sub remap_ohdsi_dictionary {

    my $data   = shift;
    my $column = 'concept_id';

    # The idea is the following:
    # $data comes as an array (from SQL/CSV)
    #
    # $VAR1 = [
    #          {
    #            'concept_class_id' => '4-char billing code',
    #            'concept_code' => 'K92.2',
    #            'concept_id' => '35208414',
    #            'concept_name' => 'Gastrointestinal hemorrhage, unspecified',
    #            'domain_id' => 'Condition',
    #            'invalid_reason' => undef,
    #            'standard_concept' => '',
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
    #                         'concept_code' => '28889',
    #                         'concept_id' => '1107830',
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
    return { map { $_->{$column} => $_ } @{$data} };
}

sub read_sqldump_stream {

    my $arg     = shift;
    my $filein  = $arg->{in};
    my $self    = $arg->{self};
    my $fileout = $self->{out_file};
    my $switch  = 0;
    my @headers;
    my $table_name    = $self->{omop_tables}[0];
    my $table_name_lc = lc($table_name);

    # First we do a transformation from AoH to HoH to speed up the calculation
    my $person = { map { $_->{person_id} => $_ } @{ $self->{data}{PERSON} } };

    # Open filehandles
    my $fh_in  = open_file( $filein,  'r' );
    my $fh_out = open_file( $fileout, 'w' );

    # Start printing the array
    #say $fh_out "[";

    # Now we we start processing line by line
    my $count = 0;
    while ( my $line = <$fh_in> ) {
        chomp $line;

        # Only parsing $table_name_lc and discarding others
        # Note that double quotes are optional
        # - COPY "OMOP_cdm_eunomia".person
        # . COPY omop_cdm_eunomia_2.person
        if ( $line =~ /^COPY \"?(\w+)\"?\.$table_name_lc / ) {

            # Create an array to hold the column names for this table
            $line =~ s/[\(\),]//g;    # getting rid of (),
            @headers = split /\s+/, $line;

            # Discarding headers which are not terms/variables
            @headers = @headers[ 2 .. $#headers - 2 ];

            # Turning on the switch for later
            $switch++;

            # Jump one line and get rid of \n
            chomp( $line = <$fh_in> );

        }

        # Loading the data if $switch
        if ($switch) {

            # Order matters. We exit before loading
            last if $line =~ /^\\\.$/;

            # Solitting by tab, it's ok
            my @fields = split /\t/, $line;

            # Using tmp hashref to load all fields at once with slice
            my $tmp_hash;
            @{$tmp_hash}{@headers} = @fields;

            # Initialize $data each time
            # Adding them as an array element (AoH)
            die
"We could not find person_id:$tmp_hash->{person_id}. Try increasing the #lines with --max-lines-sql\n"
              unless exists $person->{ $tmp_hash->{person_id} };

            # Increase counter
            $count++;

            # Encode data
            my $encoded_data =
              encode_omop_stream( $table_name, $tmp_hash, $person,
                $count, $self );
            say $fh_out $encoded_data if $encoded_data ne 'null';

            # Print if verbose
            say "Rows processed: $count"
              if ( $self->{verbose} && $count % 10_000 == 0 );
        }
    }
    say "==============\nRows total:     $count\n" if $self->{verbose};

    #say $fh_out "]"; # not needed

    # Closing filehandles
    close $fh_in;
    close $fh_out;
    return 1;
}

sub encode_omop_stream {
    my ( $table_name, $tmp_hash, $person, $count, $self ) = @_;

    # IMPORTANT === We only print person_id ONCE!!!
    my $data = {
        $table_name => [$tmp_hash],
        PERSON      => $count == 1
        ? $person->{ $tmp_hash->{person_id} }
        : {
            map { $_ => $person->{ $tmp_hash->{person_id} }{$_} }
              qw(person_id gender_concept_id birth_datetime)
        }
    };

    # Print line by line
    return JSON::XS->new->utf8->canonical->encode(
        Convert::Pheno::omop2bff_stream_processing( $self, $data ) );

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
    # The parser is based in reading COPY paragraphs from PostgreSQL dump by using Perl's paragraph mode  $/ = "";
    # NB: Each paragraph (TABLE) is loaded into memory. Not great for large files.

    # Define variables that modify what we load
    my $max_lines_sql = $self->{max_lines_sql};
    my @omop_tables   = @{ $self->{omop_tables} };

    # Set record separator to paragraph
    local $/ = "";

    #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, attribute_description, attribute_type_concept_id, attribute_syntax) FROM stdin;
    # ......
    # \.

    # Start reading the SQL dump
    my $fh = open_file( $filepath, 'r' );

    # We'll store the data in the hashref $data
    my $data = {};

    # Process paragraphs
    while ( my $paragraph = <$fh> ) {

        # Discarding paragraphs not having  m/^COPY/
        next unless $paragraph =~ m/^COPY/;

        # Load all lines into an array
        my @lines = split /\n/, $paragraph;
        next unless scalar @lines > 2;
        pop @lines;    # last line eq '\.'

        # First line contains the headers
        #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, ..., attribute_syntax) FROM stdin;
        $lines[0] =~ s/[\(\),]//g;    # getting rid of (),
        my @headers = split /\s+/, $lines[0];
        my $table_name =
          uc( ( split /\./, $headers[1] )[1] );    # ATTRIBUTE_DEFINITION

        # Discarding non @$omop_tables:
        # This step improves RAM consumption
        next unless any { m/^$table_name$/ } @omop_tables;

        # Say if verbose
        say "Processing table ... <$table_name>" if $self->{verbose};

        # Discarding first line
        shift @lines;

        # Discarding headers which are not terms/variables
        @headers = @headers[ 2 .. $#headers - 2 ];

        # Initializing $data>key as empty arrayref
        $data->{$table_name} = [];

        # Ad hoc counter for dev
        my $count = 0;

        # Processing line by line
        for my $line (@lines) {
            $count++;

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
            my $tmp_hash;
            @{$tmp_hash}{@headers} = @fields;

            # Adding them as an array element (AoH)
            push @{ $data->{$table_name} }, $tmp_hash;

            # adhoc filter to speed-up development
            last if $count == $max_lines_sql;
            say "Rows processed: $count"
              if ( $self->{verbose} && $count % 1_000 == 0 );

        }

        # Print if verbose
        say "==============\nRows total:     $count\n" if $self->{verbose};
    }
    close $fh;
    return $data;
}

sub sqldump2csv {

    my ( $data, $dir ) = @_;

    # CSV sep character
    my $sep = "\t";

    # The idea is to save a CSV table for each $data->key
    for my $table ( keys %{$data} ) {

        # File path for CSV file
        my $filepath = catdir( $dir, "$table.csv" );

        # We get header fields from row[0] and nsort them
        # NB: The order will not be the same as that in <.sql>
        my @headers = nsort keys %{ $data->{$table}[0] };

        # Print data as CSV
        print_csv(
            {
                sep      => $sep,
                filepath => $filepath,
                headers  => \@headers,
                data     => $data->{$table}
            }
        );
    }
    return 1;
}

sub transpose_omop_data_structure {

    my $data = shift;

    # The situation is the following, $data comes in format:
    #
    #$VAR1 = {
    #          'MEASUREMENT' => [
    #                             {
    #                               'measurement_concept_id' => '001',
    #                               'person_id' => '666'
    #                             },
    #                             {
    #                               'measurement_concept_id' => '002',
    #                               'person_id' => '666'
    #                             }
    #                           ],
    #          'PERSON' => [
    #                        {
    #                          'person_id' => '666'
    #                        },
    #                        {
    #                          'person_id' => '001'
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
    #          '001' => {
    #                     'PERSON' => {
    #                                   'person_id' => '001'
    #                                 }
    #                   },
    #          '666' => {
    #                     'MEASUREMENT' => [
    #                                        {
    #                                          'measurement_concept_id' => '001',
    #                                          'person_id' => '666'
    #                                        },
    #                                        {
    #                                          'measurement_concept_id' => '002',
    #                                          'person_id' => '666'
    #                                        }
    #                                      ],
    #                     'PERSON' => {
    #                                   'person_id' => '666'
    #                                 }
    #                   }
    #        };

    my $omop_person_id = {};

    # Only performed for $omop_main_table
    for my $table ( @{ $omop_main_table->{$omop_version} } ) {    # global
        for my $item ( @{ $data->{$table} } ) {

            if ( exists $item->{person_id} && $item->{person_id} ne '' ) {
                my $person_id = $item->{person_id};

                # {person_id} can have multiple rows in a given table
                if ( any { m/^$table$/ } @omop_array_tables ) {
                    push @{ $omop_person_id->{$person_id}{$table} }, $item;    # array
                }

                # {person_id} only has one value in a given TABLE
                else {
                    $omop_person_id->{$person_id}{$table} = $item;             # scalar
                }
            }
        }
        delete $data->{$table};    # To get back unused memory for later...
    }

    # Finally we get rid of the 'person_id' key and return values as an array
    #
    #$VAR1 = [
    #          {
    #            'PERSON' => {
    #                          'person_id' => '001'
    #                        }
    #          },
    # ------------------------------------------------
    #          {
    #            'MEASUREMENT' => [
    #                               {
    #                                 'measurement_concept_id' => '001',
    #                                 'person_id' => '666'
    #                               },
    #                               {
    #                                 'measurement_concept_id' => '002',
    #                                 'person_id' => '666'
    #                               }
    #                             ],
    #            'PERSON' => {
    #                          'person_id' => '666'
    #                        }
    #          }
    #        ];
    # NB: We nsort keys to always have the same result but it's not needed
    return [ map { $omop_person_id->{$_} } nsort keys %{$omop_person_id} ];
}

sub read_csv {

    my $arg      = shift;
    my $filepath = $arg->{in};
    my $sep      = $arg->{sep};

    # Define split record separator from file extension
    my ( $separator, $encoding ) = define_separator( $filepath, $sep );

    # Transform $filepath into an AoH
    # Using Text::CSV_XS functional interface
    my $aoh = csv(
        in       => $filepath,
        sep_char => $separator,
        headers  => "auto",
        eol      => "\n",

        # binary    => 1, # default
        encoding  => $encoding,
        auto_diag => 1
    );

    # $aoh = [
    #       {
    #         'abdominal_mass' => '0',
    #         'age_first_diagnosis' => '0',
    #         'alcohol' => '4',
    #        }, {},,,
    #      ]

    return $aoh;
}

sub read_csv_stream {

    my $arg     = shift;
    my $filein  = $arg->{in};
    my $self    = $arg->{self};
    my $sep     = $arg->{sep};
    my $fileout = $self->{out_file};

    # Define split record separator from file extension
    my ( $separator, $encoding, $table_name ) =
      define_separator( $filein, $sep );
    my $table_name_lc = lc($table_name);

    # First we do a transformation from AoH to HoH to speed up the calculation
    my $person = { map { $_->{person_id} => $_ } @{ $self->{data}{PERSON} } };

    # Using Text::CSV_XS OO interface
    my $csv = Text::CSV_XS->new(
        { binary => 1, auto_diag => 1, sep_char => $separator, eol => "\n" } );

    # Open filehandles
    my $fh_in  = open_file( $filein,  'r' );
    my $fh_out = open_file( $fileout, 'w' );

    # Get rid of \n on first line
    chomp( my $line = <$fh_in> );
    my @headers = split /$separator/, $line;

    my $tmp_hash;
    my $count = 0;

    #############
    # IMPORTANT #
    #############
    # On Feb-19-2023 I tested Parallel::ForkManager and:
    # 1 - The performance was by far slower than w/o it
    # 2 - We hot SQLite errors for concurring fh
    # Thus, it was not implemented

    while ( my $row = $csv->getline($fh_in) ) {

        # Load the values a a hash slice;
        my $tmp_hash;
        @{$tmp_hash}{@headers} = @$row;

        # Encode data
        my $encoded_data =
          encode_omop_stream( $table_name, $tmp_hash, $person, $count, $self );
        say $fh_out $encoded_data if $encoded_data ne 'null';

        # Increment $count
        $count++;
        say "Rows processed: $count"
          if ( $self->{verbose} && $count % 10_000 == 0 );
    }
    say "==============\nRows total:     $count\n" if $self->{verbose};

    close $fh_in;
    close $fh_out;
    return 1;
}

sub print_csv {

    my $arg      = shift;
    my $sep      = $arg->{sep};
    my $aoh      = $arg->{data};
    my $filepath = $arg->{filepath};
    my $headers  = $arg->{headers};

    # Using Text::CSV_XS functional interface
    # NB: About speed:
    #     https://metacpan.org/pod/Text::CSV#csv1
    csv(
        in       => $aoh,
        out      => $filepath,
        sep_char => $sep,
        eol      => "\n",

        #binary   => 1,   # default
        encoding => 'UTF-8',
        headers  => $arg->{headers}
    );
    return 1;
}

sub open_file {

    my ( $filepath, $mode ) = @_;
    my $diamond = $mode eq 'w' ? '>' : '<';
    my $fh;

    # To avoid issues with ZIP layers we use gzip to rw gz files
    # See: https://perldoc.perl.org/IO::Compress::FAQ
    #      https://www.biostars.org/p/94240/
    #open my $fh_in, '-|', 'zcat', $filein;

    if ( $filepath =~ /\.gz$/ ) {
        open $fh, qq($diamond:gzip:encoding(utf-8)), $filepath;
    }
    else {
        open $fh, qq($diamond:encoding(utf-8)), $filepath;
    }
    return $fh;
}

sub define_separator {

    my ( $filepath, $sep ) = @_;

    # Define split record separator from file extension
    my @exts = map { $_, $_ . '.gz' } qw(.csv .tsv .sql .txt);
    my ( undef, $table_name, $ext ) = fileparse( $filepath, @exts );

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
1;
