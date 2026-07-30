package Convert::Pheno::ConversionRequest;

use strict;
use warnings;

use Hash::Util qw(lock_hashref);
use Storable qw(dclone);

use Convert::Pheno::Operations qw(conversion_spec);

my @ARGUMENT_KEYS = qw(
  data
  debug
  default_vital_status
  derived_entity_overrides
  entities
  exposures_file
  id
  in_file
  in_files
  in_textfile
  levenshtein_weight
  log
  mapping_file
  max_lines_sql
  min_text_similarity_score
  ohdsi_db
  omop_tables
  out_dir
  out_file
  output_name_overrides
  path_to_ohdsi_db
  print_hidden_labels
  redcap_dictionary
  schema_file
  search
  search_audit_file
  self_validate_schema
  sep
  source_info
  sql2csv
  stream
  test
  text_similarity_method
  username
  verbose
);

sub from_converter {
    my ( $class, $converter ) = @_;
    my $method = $converter->{method};
    my $spec = conversion_spec($method)
      or die "Unsupported conversion <$method>\n";

    my %arguments;
    for my $key (@ARGUMENT_KEYS) {
        next unless exists $converter->{$key};
        $arguments{$key} = _copy_value( $converter->{$key}, $key eq 'data' );
    }

    lock_hashref(\%arguments);
    my $self = {
        method    => $method,
        spec      => $spec,
        arguments => \%arguments,
        has_data  => exists $converter->{data} ? 1 : 0,
    };
    bless $self, $class;
    lock_hashref($self);
    return $self;
}

sub method   { return $_[0]->{method} }
sub has_data { return $_[0]->{has_data} }

sub spec {
    my ($self) = @_;
    return dclone( $self->{spec} );
}

sub pipeline {
    my ($self) = @_;
    return [ @{ $self->{spec}{pipeline} } ];
}

sub stage_arguments {
    my ( $self, $stage, %arg ) = @_;
    my %arguments = map {
        $_ => _copy_value( $self->{arguments}{$_}, $_ eq 'data' )
    } keys %{ $self->{arguments} };

    $arguments{method} = $stage;
    if ( exists $arg{data} ) {
        $arguments{data}        = $arg{data};
        $arguments{in_textfile} = 0;
    }

    return \%arguments;
}

sub _copy_value {
    my ( $value, $preserve_reference ) = @_;
    return $value if $preserve_reference || !ref($value);
    return dclone($value);
}

1;
