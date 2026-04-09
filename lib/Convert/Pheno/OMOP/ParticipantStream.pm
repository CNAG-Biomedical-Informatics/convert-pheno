package Convert::Pheno::OMOP::ParticipantStream;

use strict;
use warnings;
use autodie;
use feature qw(say);

use Exporter 'import';
use List::Util qw(any);

use Convert::Pheno::OMOP::Definitions;

our @EXPORT_OK = qw(
  omop_require_concept
  omop_init_caches_and_metadata
  omop_prepare_data_shape
  omop_stream_dispatcher
  process_csv_files_stream
  process_sqldump_stream
);

sub omop_require_concept {
    my ( $self, $data ) = @_;
    die "The table <CONCEPT> is missing from the input files\n"
      unless exists $data->{CONCEPT};
    return 1;
}

sub omop_init_caches_and_metadata {
    my ( $self, $data ) = @_;

    $self->{data_ohdsi_dict} =
      Convert::Pheno::convert_table_aoh_to_hoh( $data, 'CONCEPT', $self );

    if ( $self->{stream} ) {
        $self->{person} = Convert::Pheno::convert_table_aoh_to_hoh( $data, 'PERSON', $self );
    }

    if ( exists $data->{VISIT_OCCURRENCE} ) {
        $self->{visit_occurrence} =
          Convert::Pheno::convert_table_aoh_to_hoh( $data, 'VISIT_OCCURRENCE', $self );
        delete $data->{VISIT_OCCURRENCE};
    }

    $self->{exposures} = Convert::Pheno::load_exposures( $self->{exposures_file} );

    $self->{metaData}     = Convert::Pheno::get_metaData($self);
    $self->{convertPheno} = Convert::Pheno::get_info($self);

    return 1;
}

sub omop_prepare_data_shape {
    my ( $self, $data ) = @_;
    $self->{data} =
      $self->{stream} ? $data : Convert::Pheno::transpose_omop_data_structure( $self, $data );
    return 1;
}

sub omop_stream_dispatcher {
    my $arg         = shift;
    my $self        = $arg->{self};
    my $filepath    = $arg->{filepath};
    my $filepaths   = $arg->{filepaths};
    my $omop_tables = $self->{prev_omop_tables};

    Convert::Pheno::open_connections_SQLite($self) if $self->{method} ne 'bff2pxf';

    return @$filepaths
      ? process_csv_files_stream( $self, $filepaths )
      : process_sqldump_stream( $self, $filepath, $omop_tables );
}

sub process_csv_files_stream {
    my ( $self, $filepaths ) = @_;
    my $person = $self->{person};
    for my $file (@$filepaths) {
        say "Processing file ... <$file>" if $self->{verbose};
        Convert::Pheno::read_csv_stream(
            {
                in     => $file,
                sep    => $self->{sep},
                self   => $self,
                person => $person
            }
        );
    }
    return 1;
}

sub process_sqldump_stream {
    my ( $self, $filepath, $omop_tables ) = @_;
    my $person = $self->{person};

    for my $table (@$omop_tables) {
        next if any { $_ eq $table } @stream_ram_memory_tables;
        say "Processing table <$table> line-by-line..." if $self->{verbose};

        Convert::Pheno::_with_temp_self_field(
            $self,
            'omop_tables',
            [$table],
            sub {
                Convert::Pheno::read_sqldump_stream(
                    { in => $filepath, self => $self, person => $person }
                );
                return 1;
            }
        );
    }
    return 1;
}

1;
