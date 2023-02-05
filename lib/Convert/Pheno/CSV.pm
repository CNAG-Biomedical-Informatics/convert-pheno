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
use Convert::Pheno::OMOP;
use Convert::Pheno::IO;
use Convert::Pheno::Schema;
use Exporter 'import';
our @EXPORT =
  qw(read_csv read_redcap_dic_and_mapping_file remap_ohdsi_dictionary read_sqldump sqldump2csv transpose_omop_data_structure);

#########################
#########################
#  SUBROUTINES FOR CSV  #
#########################
#########################

sub read_redcap_dictionary {

    my $in_file = shift;

    # Define split record separator from file extension
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    # Defining separator
    my $separator =
        $ext eq '.csv' ? ';'
      : $ext eq '.tsv' ? "\t"
      :                  ' ';

    # We'll create an HoH using as 1Di-key the 'Variable / Field Name'
    my $key = 'Variable / Field Name';

    # We'll be adding the key <_labels>. See sub add_labels
    my $labels = 'Choices, Calculations, OR Slider Labels';
    my $hoh    = csv(
        in        => $in_file,
        sep_char  => $separator,
        binary    => 1,
        auto_diag => 1,
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

    return { map { $_->{$column} => $_ } @{$data} };
}

sub read_sqldump {

    my ( $file, $self ) = @_;

    # Before resorting to writting this subroutine I performed an exhaustive search on CPAN
    # I tested MySQL::Dump::Parser::XS  but I could not make it work and other modules did not seem to do what I wanted...
    # .. so I ended up writting the parser myself...
    # The parser is based in reading COPY paragraphs from PostgreSQL dump by using Perl's paragraph mode  $/ = "";
    # The sub can be seen as "ugly" but it does the job :-)

    my $max_lines_sql = $self->{max_lines_sql} // 500;    # Limit to speed up runtime
    local $/ = "";                                        # set record separator to paragraph

    #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, attribute_description, attribute_type_concept_id, attribute_syntax) FROM stdin;
    # ......
    # \.

    # Start reading the SQL dump
    open my $fh, '<:encoding(utf-8)', $file;

    # We'll store the data in the hashref $data
    my $data = {};

    # Process paragraphs
    while ( my $paragraph = <$fh> ) {

        # Discarding paragraphs not having  m/^COPY/
        next unless $paragraph =~ m/^COPY/;

        # Discarding empty /^COPY/ paragraphs
        my @lines = split /\n/, $paragraph;
        next unless scalar @lines > 2;
        pop @lines;    # last line eq '\.'

        # Ad hoc for testing
        my $count = 0;

        # First line contain the headers
        #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, ..., attribute_syntax) FROM stdin;
        $lines[0] =~ s/[\(\),]//g;    # getting rid of (),
        my @headers = split /\s+/, $lines[0];
        my $table_name =
          uc( ( split /\./, $headers[1] )[1] );    # ATTRIBUTE_DEFINITION
        shift @lines;                              # discarding first line

        # Discarding headers which are not terms/variables
        @headers = @headers[ 2 .. $#headers - 2 ];

        # Initializing $data>key as empty arrayref
        $data->{$table_name} = [];

        # Processing line by line
        for my $line (@lines) {
            $count++;

            # Columns are separated by \t
            # NB: Loading everything as 'string'. Coercing a posteriori
            my @values = split /\t/, $line;

            # Loading the values like this:
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

            # Using tmp hash to load all values at once
            my %tmp_hash;
            @tmp_hash{@headers} = @values;

            # Adding them as an array element (AoH)
            push @{ $data->{$table_name} }, {%tmp_hash};

            # adhoc filter to speed-up development
            last if $count == $max_lines_sql;
        }
    }
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

    # where all 'perosn_id' are together inside the TABLE_NAME.
    # But, BFF works at the individual level so we are going to
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
                if (
                    any { m/^$table$/ } (
                        'MEASUREMENT',          'OBSERVATION',
                        'CONDITION_OCCURRENCE', 'PROCEDURE_OCCURRENCE',
                        'DRUG_EXPOSURE'
                    )
                  )
                {
                    push @{ $omop_person_id->{$person_id}{$table} }, $item;    # array
                }

                # {person_id} only has one value in a given TABLE
                else {
                    $omop_person_id->{$person_id}{$table} = $item;             # scalar
                }
            }
        }
    }

    # Finally we get rid of the 'person_id' key and return values as an array
    #
    #$VAR1 = [
    #          {
    #            'PERSON' => {
    #                          'person_id' => '001'
    #                        }
    #          },
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

    my $arg     = shift;
    my $in_file = $arg->{in};
    my $sep     = $arg->{sep};

    # Define split record separator from file extension
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    # Defining separator character
    my $separator =
        $sep
      ? $sep
      : $ext eq '.csv' ? ';'     # Note we don't use comma but semicolon
      : $ext eq '.tsv' ? "\t"
      :                  "\t";

    # Transform $in_file into an AoH
    # Using Text::CSV_XS functional interface
    my $aoh = csv(
        in        => $in_file,
        sep_char  => $separator,
        headers   => "auto",
        auto_diag => 1,
        binary    => 1
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

sub print_csv {

    my $arg      = shift;
    my $sep      = $arg->{sep};
    my $aoh      = $arg->{data};
    my $filepath = $arg->{filepath};
    my $headers  = $arg->{headers};

    # Using Text::CSV_XS functional interface
    csv(
        in       => $aoh,
        out      => $filepath,
        sep_char => $sep,
        eol      => "\n",
        binary   => 1,
        headers  => $arg->{headers}
    );
    return 1;
}
1;
