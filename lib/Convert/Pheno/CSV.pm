package Convert::Pheno::CSV;

use strict;
use warnings;
use autodie;
use feature qw(say);
use File::Basename;
use Text::CSV_XS;
use Sort::Naturally qw(nsort);
use List::Util      qw(any);
use Convert::Pheno::OMOP;
use Exporter 'import';
our @EXPORT =
  qw(read_csv_export read_redcap_dictionary remap_ohdsi_dictionary read_sqldump sqldump2csv transpose_omop_data_structure);

#########################
#########################
#  SUBROUTINES FOR CSV  #
#########################
#########################

sub read_csv_export {

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

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    # Defining variables
    my $data = [];                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Open filehandle
    open my $fh, '<:encoding(utf8)', $in_file;

    # Loading header fields
    my $header = $csv->getline($fh);

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh) ) {

        # We store the data as an AoH $data
        my $tmp_hash;
        for my $i ( 0 .. $#{$header} ) {
            $tmp_hash->{ $header->[$i] } = $row->[$i];
        }
        push @$data, $tmp_hash;
    }

    close $fh;

    #########################################
    #     END READING CSV|TSV|TXT FILE      #
    #########################################

    return $data;
}

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

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    # Defining variables
    my $data = {};                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Open filehandle
    open my $fh, '<:encoding(utf8)', $in_file;

    # Loading header fields
    my $header = $csv->getline($fh);

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh) ) {

        # We store the data as an AoH $data
        my $tmp_hash;

        for my $i ( 0 .. $#{$header} ) {

            # We keep key>/value as they are
            $tmp_hash->{ $header->[$i] } = $row->[$i];

# For the key having labels, we create a new ad hoc key '_labels'
# 'Choices, Calculations, OR Slider Labels' => '1, Female|2, Male|3, Other|4, not available',
            if ( $header->[$i] eq 'Choices, Calculations, OR Slider Labels' ) {
                my @tmp =
                  map { s/^\s//; s/\s+$//; $_; } ( split /\||,/, $row->[$i] );
                $tmp_hash->{_labels} = {@tmp} if @tmp % 2 == 0;
            }
        }

        # Now we create the 1D of the hash with 'Variable / Field Name'
        my $key = $tmp_hash->{'Variable / Field Name'};

        # And we nest the hash inside
        $data->{$key} = $tmp_hash;
    }

    close $fh;

    #######################################
    #     END READING CSV|TSV|TXT FILE    #
    #######################################

    return $data;
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

    my ($file, $self) = @_;

# Before resorting to writting this subroutine I performed an exhaustive search on CPAN
# I tested MySQL::Dump::Parser::XS  but I could not make it work and other modules did not seem to do what I wanted...
# .. so I ended up writting the parser myself...
# The parser is based in reading COPY paragraphs from PostgreSQL dump by using Perl's paragraph mode  $/ = "";
# The sub can be seen as "ugly" but it does the job :-)

    my $max_lines_sql = $self->{max_lines_sql} // 500;    # Limit to speed up runtime
    local $/ = "";      # set record separator to paragraph

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

            push @{ $data->{$table_name} },
              { map { $headers[$_] => $values[$_] } ( 0 .. $#headers ) };
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

        # Name for CSV file
        my $filename = catdir( $dir, "$table.csv" );

        # Start printing
        open my $fh, ">:encoding(utf8)", $filename;
        my $csv =
          Text::CSV_XS->new( { sep_char => $sep, eol => "\n", binary => 1 } );

        ##########################
        # Transforming it to CSV #
        ##########################

        # Print headers (we get them from row[0])
        my @headers = nsort keys %{ $data->{$table}[0] };
        say $fh join $sep, @headers;

        # Print rows
        foreach my $row ( 0 .. $#{ $data->{$table} } ) {

            # Transposing it to typical CSV format
            $csv->print( $fh, [ map { $data->{$table}[$row]{$_} } @headers ] );
        }
        close $fh;
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
                    push @{ $omop_person_id->{$person_id}{$table} },
                      $item;    # array
                }

                # {person_id} only has one value in a given TABLE
                else {
                    $omop_person_id->{$person_id}{$table} = $item;    # scalar
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
1;
