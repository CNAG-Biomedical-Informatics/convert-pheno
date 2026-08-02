package Convert::Pheno::CBioPortal::ToBFF;

use strict;
use warnings;

use Exporter 'import';
use Storable qw(dclone);

use Convert::Pheno::BFF::Biosample qw(biosample_to_phenopacket);
use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Tabular::ToBFF qw(
  map_tabular_biosamples
  map_tabular_individual
);
use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(run_cbioportal_to_bundle);

my $DEFAULT = get_defaults();

sub run_cbioportal_to_bundle {
    my ( $self, $record, $context ) = @_;

    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => 'cbioportal',
            target_format => 'beacon',
            entities      => $self->{entities} || ['individuals'],
        }
    );

    die "Normalized cBioPortal input must contain a patient-scoped object\n"
      unless ref($record) eq 'HASH'
      && ref( $record->{patient} ) eq 'HASH'
      && ref( $record->{study} ) eq 'HASH';

    my $bundle = Convert::Pheno::Model::Bundle->new(
        {
            context  => $context,
            entities => $context->entities,
        }
    );

    my $individual = _map_individual($self, $record);
    my @biosamples = map {
        _map_biosample( $self, $_, $individual->{id} )
    } @{ $record->{samples} || [] };

    # PXF pipelines carry only the primary individual between stages. Keep a
    # Phenopackets representation here so linked samples are not discarded.
    if (@biosamples) {
        $individual->{info}{phenopacket}{biosamples} = [
            map { biosample_to_phenopacket($_) } @biosamples
        ];
    }

    $bundle->add_entity( individuals => $individual );
    if ( _context_requests_entity( $context, 'biosamples' ) ) {
        $bundle->add_entity( biosamples => $_ ) for @biosamples;
    }

    if ( $record->{isFirst}
        && _context_requests_entity( $context, 'datasets' ) )
    {
        $bundle->add_entity(
            datasets => _map_dataset( $self, $record->{study} )
        );
    }

    if ( $record->{isFirst}
        && _context_requests_entity( $context, 'cohorts' ) )
    {
        $bundle->add_entity( cohorts => $_ )
          for @{ _map_cohorts( $self, $record->{study} ) };
    }

    return $bundle;
}

sub _map_individual {
    my ( $self, $record ) = @_;
    my $patient = $record->{patient};
    my $id = _required_scalar( $patient->{PATIENT_ID}, 'PATIENT_ID' );

    my $individual = {
        id  => $id,
        sex => _map_sex($patient),
    };

    my $vital_status = _map_vital_status($patient);
    $individual->{info}{phenopacket}{vitalStatus} = $vital_status
      if $vital_status;

    my ( %seen_disease, @diseases );
    for my $sample ( @{ $record->{samples} || [] } ) {
        my $term = _oncotree_term($sample);
        next unless $term && !$seen_disease{ $term->{id} }++;
        push @diseases, { diseaseCode => $term };
    }
    $individual->{diseases} = \@diseases if @diseases;

    if ( $self->{source_info} // 1 ) {
        $individual->{info}{cbioportal}{patient} = dclone($patient);
    }

    if ( ref( $self->{data_mapping_file} ) eq 'HASH' ) {
        my $mapped = map_tabular_individual( $self, $patient );
        die "The cBioPortal mapping did not produce individual <$id>; ensure its sex source is populated\n"
          unless ref($mapped) eq 'HASH';
        die "A cBioPortal mapping cannot rewrite PATIENT_ID <$id> as <$mapped->{id}>\n"
          unless defined $mapped->{id} && "$mapped->{id}" eq $id;

        # cBioPortal identifiers are structural: sample links and case lists
        # refer to them. Mapping rules augment semantics but cannot change the
        # identity graph without breaking those source relationships.
        _merge_hash_into( $individual, $mapped );
        $individual->{id} = $id;
    }

    $individual->{info}{convertPheno} = $self->{convertPheno}
      if !$self->{test} && defined $self->{convertPheno};

    return $individual;
}

sub _map_biosample {
    my ( $self, $sample, $individual_id ) = @_;
    my $id = _required_scalar( $sample->{SAMPLE_ID}, 'SAMPLE_ID' );
    my $source_patient_id = _required_scalar(
        $sample->{PATIENT_ID},
        'PATIENT_ID',
    );
    die "cBioPortal sample <$id> cannot be linked to rewritten individual <$individual_id>\n"
      unless $source_patient_id eq $individual_id;

    my $biosample = {
        id               => $id,
        individualId     => $individual_id,
        biosampleStatus  => dclone( $DEFAULT->{ontology_term} ),
        # cBioPortal SAMPLE_TYPE is a source category, not necessarily an
        # ontology concept. Preserve it in info and avoid inventing a CURIE.
        sampleOriginType => dclone( $DEFAULT->{ontology_term} ),
    };
    my $diagnosis = _oncotree_term($sample);
    $biosample->{histologicalDiagnosis} = $diagnosis if $diagnosis;

    if ( $self->{source_info} // 1 ) {
        $biosample->{info}{cbioportal}{sample} = dclone($sample);
    }

    if ( ref( $self->{data_mapping_file} ) eq 'HASH'
        && ref( $self->{data_mapping_file}{beacon}{biosamples} ) eq 'HASH' )
    {
        my $mapped = map_tabular_biosamples( $self, $sample, $individual_id );
        die "The cBioPortal mapping produced multiple biosamples for SAMPLE_ID <$id>; define one matching biosample rule per sample row\n"
          if @{$mapped} > 1;
        if ( @{$mapped} ) {
            my $mapped_sample = $mapped->[0];
            die "A cBioPortal mapping cannot rewrite SAMPLE_ID <$id> as <$mapped_sample->{id}>\n"
              unless defined $mapped_sample->{id}
              && "$mapped_sample->{id}" eq $id;
            die "A cBioPortal mapping cannot relink SAMPLE_ID <$id> to another individual\n"
              if defined $mapped_sample->{individualId}
              && "$mapped_sample->{individualId}" ne $individual_id;
            _merge_hash_into( $biosample, $mapped_sample );
            $biosample->{id}           = $id;
            $biosample->{individualId} = $individual_id;
        }
    }

    $biosample->{info}{convertPheno} = $self->{convertPheno}
      if !$self->{test} && defined $self->{convertPheno};

    return $biosample;
}

sub _map_dataset {
    my ( $self, $study ) = @_;
    my $meta = $study->{metadata};
    my $dataset = {
        id          => $study->{id},
        name        => $meta->{name},
        description => $meta->{description} // "cBioPortal study $study->{id}.",
        info        => {
            sourceEntity    => 'cBioPortal clinical study',
            individualCount => 0 + $study->{patientCount},
            biosampleCount  => 0 + $study->{sampleCount},
        },
    };

    if ( $self->{source_info} // 1 ) {
        $dataset->{info}{cbioportal} = {
            source                     => $study->{source},
            study                      => dclone($meta),
            patientAttributeDefinitions => dclone(
                $study->{patientAttributeDefinitions}
            ),
            sampleAttributeDefinitions => dclone(
                $study->{sampleAttributeDefinitions}
            ),
        };
    }

    _apply_dataset_overrides( $self, $dataset );
    $dataset->{info}{convertPheno} = $self->{convertPheno}
      if !$self->{test} && defined $self->{convertPheno};
    return $dataset;
}

sub _map_cohorts {
    my ( $self, $study ) = @_;
    my @cohorts;

    for my $case ( @{ $study->{caseLists} || [] } ) {
        my $meta = $case->{metadata};
        my $cohort = {
            id         => $meta->{stable_id},
            name       => $meta->{case_list_name},
            cohortType => 'study-defined',
            cohortSize => scalar @{ $case->{individualIds} },
            info       => {
                cbioportal => {
                    membership => {
                        sampleIds     => dclone( $case->{sampleIds} ),
                        individualIds => dclone( $case->{individualIds} ),
                    },
                },
            },
        };

        if ( $self->{source_info} // 1 ) {
            $cohort->{info}{cbioportal}{caseList} = dclone($meta);
            $cohort->{info}{cbioportal}{source}   = $case->{source};
        }

        _apply_cohort_overrides( $self, $cohort );
        push @cohorts, $cohort;
    }

    return \@cohorts;
}

sub _map_sex {
    my ($patient) = @_;
    my $value;
    for my $field (qw(SEX GENDER)) {
        next unless defined $patient->{$field} && !ref( $patient->{$field} );
        $value = lc _trim( $patient->{$field} );
        last if length $value;
    }

    return dclone( $DEFAULT->{sex}{male} )
      if defined $value && $value =~ /\A(?:m|male)\z/;
    return dclone( $DEFAULT->{sex}{female} )
      if defined $value && $value =~ /\A(?:f|female)\z/;
    return dclone( $DEFAULT->{sex}{other} )
      if defined $value && $value eq 'other';
    return dclone( $DEFAULT->{sex}{unknown} );
}

sub _map_vital_status {
    my ($patient) = @_;
    my $status = $patient->{OS_STATUS};
    return unless defined $status && !ref($status);

    return { status => 'DECEASED' } if $status =~ /DECEASED/i;
    return { status => 'ALIVE' } if $status =~ /(?:LIVING|ALIVE)/i;
    return;
}

sub _oncotree_term {
    my ($sample) = @_;
    my $code = _trim( $sample->{ONCOTREE_CODE} );
    return unless _has_source_value($code);
    $code =~ s/\s+/_/g;

    my $label = _trim( $sample->{CANCER_TYPE_DETAILED} );
    $label = _trim( $sample->{CANCER_TYPE} ) unless _has_source_value($label);
    $label = $code unless _has_source_value($label);
    return { id => "OncoTree:$code", label => $label };
}

sub _apply_dataset_overrides {
    my ( $self, $dataset ) = @_;
    for my $source (
        $self->{mapping_file_derived_entity_overrides},
        $self->{derived_entity_overrides},
      )
    {
        next unless ref($source) eq 'HASH'
          && ref( $source->{datasets} ) eq 'HASH';
        _merge_hash_into( $dataset, dclone( $source->{datasets} ) );
    }
    return 1;
}

sub _apply_cohort_overrides {
    my ( $self, $cohort ) = @_;
    for my $source (
        $self->{mapping_file_derived_entity_overrides},
        $self->{derived_entity_overrides},
      )
    {
        next unless ref($source) eq 'HASH'
          && ref( $source->{cohorts} ) eq 'HASH';
        my $overrides = dclone( $source->{cohorts} );
        delete @{$overrides}{qw(id name cohortSize)};
        _merge_hash_into( $cohort, $overrides );
    }
    return 1;
}

sub _merge_hash_into {
    my ( $target, $source ) = @_;
    return $target unless ref($source) eq 'HASH';

    for my $key ( keys %{$source} ) {
        my $value = $source->{$key};
        next unless defined $value;

        if ( ref($value) eq 'HASH' ) {
            my $merged = ref( $target->{$key} ) eq 'HASH'
              ? _clone_data( $target->{$key} )
              : {};
            _merge_hash_into( $merged, $value );
            $target->{$key} = $merged;
            next;
        }
        $target->{$key} = _clone_data($value) if ref($value);
        $target->{$key} = $value unless ref($value);
    }
    return $target;
}

sub _clone_data {
    my ($value) = @_;
    return { map { $_ => _clone_data( $value->{$_} ) } keys %{$value} }
      if ref($value) eq 'HASH';
    return [ map { _clone_data($_) } @{$value} ]
      if ref($value) eq 'ARRAY';
    return $value;
}

sub _required_scalar {
    my ( $value, $field ) = @_;
    die "Normalized cBioPortal input is missing <$field>\n"
      unless defined $value && !ref($value) && length _trim($value);
    return _trim($value);
}

sub _has_source_value {
    my ($value) = @_;
    return 0 unless defined $value && !ref($value) && length $value;
    return 0 if $value =~ /\A(?:NA|N\/A|\[Not Available\]|Not Available)\z/i;
    return 1;
}

sub _trim {
    my ($value) = @_;
    return unless defined $value;
    return $value if ref($value);
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub _context_requests_entity {
    my ( $context, $entity ) = @_;
    return scalar grep { $_ eq $entity } @{ $context->entities };
}

1;
