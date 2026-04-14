package Convert::Pheno::BFF::DerivedEntities;

use strict;
use warnings;
use autodie;

use Exporter 'import';

our @EXPORT_OK = qw(execution_entities synthesize_bundle_entities);

sub execution_entities {
    my ($entities) = @_;
    my @requested = @{ $entities || [] };
    @requested = ('individuals') unless @requested;

    my %seen;
    my @execution = grep { !$seen{$_}++ } @requested;

    # Datasets and cohorts are synthesized from the normalized individuals
    # collection, so keep individuals in the internal bundle even if the user
    # only requested the derived entities for output.
    if ( grep { $_ eq 'datasets' || $_ eq 'cohorts' } @execution ) {
        unshift @execution, 'individuals'
          unless grep { $_ eq 'individuals' } @execution;
    }

    return \@execution;
}

sub synthesize_bundle_entities {
    my ( $self, $bundle, $context ) = @_;

    my %requested = map { $_ => 1 } @{ execution_entities( $context->entities ) };
    my $individuals = $bundle->entities('individuals');

    return $bundle unless @{$individuals};

    if ( $requested{datasets} && !@{ $bundle->entities('datasets') } ) {
        $bundle->add_entity(
            datasets => _synthesizeDataset( $self, $bundle, $individuals )
        );
    }

    if ( $requested{cohorts} && !@{ $bundle->entities('cohorts') } ) {
        $bundle->add_entity(
            cohorts => _synthesizeCohort( $self, $individuals )
        );
    }

    return $bundle;
}

sub _synthesizeDataset {
    my ( $self, $bundle, $individuals ) = @_;

    my $dataset = {
        id          => 'dataset-1',
        name        => 'Converted dataset',
        description => sprintf(
            'Dataset synthesized from %d individual%s by convert-pheno.',
            scalar @{$individuals},
            scalar( @{$individuals} ) == 1 ? q{} : 's'
        ),
        info => {
            sourceEntity    => 'individuals',
            individualCount => scalar @{$individuals},
        },
    };

    my $biosamples = $bundle->entities('biosamples');
    $dataset->{info}{biosampleCount} = scalar @{$biosamples}
      if @{$biosamples};

    _merge_hash_into( $dataset, _entity_overrides( $self, 'datasets' ) );

    unless ( $self->{test} ) {
        $dataset->{info}{convertPheno} = $self->{convertPheno}
          if defined $self->{convertPheno};
    }

    return $dataset;
}

sub _synthesizeCohort {
    my ( $self, $individuals ) = @_;

    my $cohort = {
        id         => 'cohort-1',
        name       => 'All individuals',
        cohortType => 'study-defined',
        cohortSize => scalar @{$individuals},
    };

    my @cohortDataTypes;

    if ( grep { _hasClinicalContent($_) } @{$individuals} ) {
        push @cohortDataTypes,
          {
            id    => 'OGMS:0000015',
            label => 'clinical history',
          };
    }

    if ( grep { _hasGenomicContent($_) } @{$individuals} ) {
        push @cohortDataTypes,
          {
            id    => 'OBI:0000070',
            label => 'genotyping assay',
          };
    }

    $cohort->{cohortDataTypes} = \@cohortDataTypes if @cohortDataTypes;
    _merge_hash_into( $cohort, _entity_overrides( $self, 'cohorts' ) );

    return $cohort;
}

sub _entity_overrides {
    my ( $self, $entity ) = @_;

    my $overrides = {};

    if ( exists $self->{mapping_file_derived_entity_overrides}
      && ref( $self->{mapping_file_derived_entity_overrides} ) eq 'HASH'
      && exists $self->{mapping_file_derived_entity_overrides}{$entity}
      && ref( $self->{mapping_file_derived_entity_overrides}{$entity} ) eq 'HASH' )
    {
        _merge_hash_into(
            $overrides,
            _clone_data( $self->{mapping_file_derived_entity_overrides}{$entity} )
        );
    }

    if ( exists $self->{derived_entity_overrides}
      && ref( $self->{derived_entity_overrides} ) eq 'HASH'
      && exists $self->{derived_entity_overrides}{$entity}
      && ref( $self->{derived_entity_overrides}{$entity} ) eq 'HASH' )
    {
        _merge_hash_into(
            $overrides,
            _clone_data( $self->{derived_entity_overrides}{$entity} )
        );
    }

    return $overrides;
}

sub _clone_data {
    my ($data) = @_;

    return $data unless ref($data);
    return { map { $_ => _clone_data( $data->{$_} ) } keys %{$data} }
      if ref($data) eq 'HASH';
    return [ map { _clone_data($_) } @{$data} ]
      if ref($data) eq 'ARRAY';

    return $data;
}

sub _merge_hash_into {
    my ( $target, $source ) = @_;
    return $target unless defined $source && ref($source) eq 'HASH';

    for my $key ( keys %{$source} ) {
        my $value = $source->{$key};

        if ( ref($value) eq 'HASH' ) {
            $target->{$key} ||= {};
            _merge_hash_into( $target->{$key}, $value );
            next;
        }

        if ( ref($value) eq 'ARRAY' ) {
            $target->{$key} = [ @{$value} ];
            next;
        }

        $target->{$key} = $value;
    }

    return $target;
}

sub _hasClinicalContent {
    my ($individual) = @_;
    return scalar grep {
        exists $individual->{$_}
          && ref( $individual->{$_} ) eq 'ARRAY'
          && @{ $individual->{$_} }
      } qw(diseases exposures phenotypicFeatures interventionsOrProcedures measures treatments);
}

sub _hasGenomicContent {
    my ($individual) = @_;

    return 0 unless exists $individual->{info} && ref( $individual->{info} ) eq 'HASH';
    return 0
      unless exists $individual->{info}{phenopacket}
      && ref( $individual->{info}{phenopacket} ) eq 'HASH';

    my $phenopacket = $individual->{info}{phenopacket};

    return scalar grep {
        exists $phenopacket->{$_}
          && ref( $phenopacket->{$_} ) eq 'ARRAY'
          && @{ $phenopacket->{$_} }
      } qw(genes interpretations variants files);
}

1;
