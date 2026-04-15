package Convert::Pheno::OMOP::Source;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use File::Basename qw(fileparse);
use List::Util qw(any);

use Convert::Pheno::IO::CSVHandler qw(read_csv read_sqldump sqldump2csv);
use Convert::Pheno::OMOP::Definitions;

our @EXPORT_OK = qw(collect_omop_input);

sub collect_omop_input {
    my ($self) = @_;

    # MEMORY input
    if ( exists $self->{data} ) {
        $self->{omop_cli} = 0;
        return {
            kind          => 'memory',
            data          => $self->{data},
            filepath_sql  => undef,
            filepaths_csv => [],
        };
    }

    # CLI / files input
    $self->{omop_cli} = 1;

    my $data = {};
    my $filepath_sql;
    my @filepaths_csv_stream;

    my @exts = map { $_, $_ . '.gz' } qw(.csv .tsv .sql);

    for my $file ( @{ $self->{in_files} } ) {
        my ( $table_name, undef, $ext ) = fileparse( $file, @exts );

        # SQL dump
        if ( $ext =~ m/\.sql/i ) {
            print "> Param: --max-lines-sql = $self->{max_lines_sql}\n"
              if $self->{verbose};

            if ( !$self->{stream} ) {
                print "> Mode : --no-stream\n\n" if $self->{verbose};
                my $sql_headers;
                ( $data, $sql_headers ) =
                  read_sqldump( { in => $file, self => $self } );
                sqldump2csv( $data, $self->{out_dir}, $sql_headers )
                  if $self->{sql2csv};
            }
            else {
                print "> Mode : --stream\n\n" if $self->{verbose};

                _with_temp_self_field(
                    $self,
                    'omop_tables',
                    [@stream_ram_memory_tables],
                    sub {
                        ( $data, undef ) =
                          read_sqldump( { in => $file, self => $self } );
                        return 1;
                    }
                );
            }

            print "> Parameter --max-lines-sql set to: $self->{max_lines_sql}\n\n"
              if $self->{verbose};

            $filepath_sql = $file;
            last;
        }

        # CSV/TSV
        warn "<$table_name> is not a valid table in OMOP-CDM\n" and next
          unless any { $_ eq $table_name } @omop_supported_tables;

        my $msg = "Reading <$table_name> and storing it in RAM memory...";

        if ( !$self->{stream} ) {
            print "$msg\n" if ( $self->{verbose} || $self->{debug} );
            $data->{$table_name} =
              read_csv( { in => $file, sep => $self->{sep}, self => $self } );
        }
        else {
            if ( any { $_ eq $table_name } @stream_ram_memory_tables ) {
                print "$msg\n" if ( $self->{verbose} || $self->{debug} );
                $data->{$table_name} =
                  read_csv( { in => $file, sep => $self->{sep}, self => $self } );
            }
            else {
                push @filepaths_csv_stream, $file;
            }
        }
    }

    return {
        kind          => ( $filepath_sql ? 'sql' : 'csv' ),
        data          => $data,
        filepath_sql  => $filepath_sql,
        filepaths_csv => \@filepaths_csv_stream,
    };
}

sub _with_temp_self_field {
    my ( $self, $field, $value, $code ) = @_;

    my $had = exists $self->{$field} ? 1 : 0;
    my $old = $had ? $self->{$field} : undef;

    $self->{$field} = $value;
    my $ret = $code->();

    if ($had) { $self->{$field} = $old }
    else      { delete $self->{$field} }

    return $ret;
}

1;
