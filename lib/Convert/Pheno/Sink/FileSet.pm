package Convert::Pheno::Sink::FileSet;

use strict;
use warnings;

use Exporter 'import';
use File::Spec::Functions qw(catfile);

use Convert::Pheno::IO::Atomic qw(write_atomically);
use Convert::Pheno::IO::CSVHandler qw(get_headers write_csv);
use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);
use Convert::Pheno::OMOP::Definitions qw($omop_headers);
use Convert::Pheno::Operations qw(conversion_spec);

our @EXPORT_OK = qw(
  resolve_entity_output_file
  resolve_omop_table_output_file
);

sub new {
    my ( $class, $arg ) = @_;
    $arg ||= {};
    die "FileSet sink requires a conversion request hash\n"
      unless ref( $arg->{request} ) eq 'HASH';

    return bless {
        request          => $arg->{request},
        out_file         => $arg->{out_file},
        before_write     => $arg->{before_write} || sub { return 1 },
        on_write         => $arg->{on_write} || sub { return 1 },
    }, $class;
}

sub write_result {
    my ( $self, %arg ) = @_;
    my $request = $self->{request};

    if ( $arg{bundle} ) {
        for my $entity ( @{ $request->{entities} } ) {
            my $path = resolve_entity_output_file( $request, $entity );
            $self->{on_write}->($path);
            _write_structured( $path, $arg{bundle}->entities($entity) );
        }
        return 1;
    }

    my $data = $arg{data};
    return 1 unless $data;

    my $spec = conversion_spec( $request->{method} )
      or die "Unsupported conversion <$request->{method}> in output sink\n";

    if ( $spec->{target} eq 'csv' ) {
        my $path = $self->{out_file};
        $self->{on_write}->($path);
        write_atomically(
            $path,
            sub {
                my ($staged) = @_;
                write_csv(
                    {
                        sep      => $request->{sep} // ';',
                        filepath => $staged,
                        headers  => get_headers($data),
                        data     => $data,
                    }
                );
            }
        );
        return 1;
    }

    if ( $spec->{target} eq 'omop' ) {
        for my $table ( sort keys %{$data} ) {
            my $path = resolve_omop_table_output_file( $request, $table );
            $self->{before_write}->($path);
            $self->{on_write}->($path);
            my @headers = @{ $omop_headers->{$table} };
            write_atomically(
                $path,
                sub {
                    my ($staged) = @_;
                    write_csv(
                        {
                            sep      => ';',
                            filepath => $staged,
                            headers  => \@headers,
                            data     => $data->{$table},
                        }
                    );
                }
            );
        }
        return 1;
    }

    my $path = $self->{out_file};
    $self->{on_write}->($path);
    _write_structured( $path, $data );
    return 1;
}

sub resolve_entity_output_file {
    my ( $request, $entity ) = @_;
    return $request->{output_name_overrides}{$entity}
      if exists $request->{output_name_overrides}
      && exists $request->{output_name_overrides}{$entity};
    return catfile( $request->{out_dir}, $entity . '.json' );
}

sub resolve_omop_table_output_file {
    my ( $request, $table ) = @_;
    return $request->{output_name_overrides}{$table}
      if exists $request->{output_name_overrides}
      && exists $request->{output_name_overrides}{$table};
    return catfile( $request->{out_dir}, $table . '.csv' );
}

sub _write_structured {
    my ( $path, $data ) = @_;
    return write_atomically(
        $path,
        sub {
            my ($staged) = @_;
            io_yaml_or_json(
                {
                    filepath => $staged,
                    mode     => 'write',
                    data     => $data,
                }
            );
        }
    );
}

1;
