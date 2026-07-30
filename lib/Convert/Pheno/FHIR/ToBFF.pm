package Convert::Pheno::FHIR::ToBFF;

use strict;
use warnings;

use Exporter 'import';
use JSON::PP ();
use Scalar::Util qw(looks_like_number refaddr);
use Storable qw(dclone);

use Convert::Pheno::Context;
use Convert::Pheno::FHIR::Util qw(
  canonical_reference
  codeable_concept_to_term
  quantity_unit_to_term
  resolve_reference
  source_term
);
use Convert::Pheno::Mapping::Shared qw(get_age_from_date_and_birthday);
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(run_fhir_to_bundle);

my $DEFAULT = get_defaults();
my %MAPPED_RESOURCE = map { $_ => 1 } qw(
  Condition
  MedicationAdministration
  MedicationRequest
  MedicationStatement
  Observation
  Procedure
  Specimen
);

sub run_fhir_to_bundle {
    my ( $self, $record, $context ) = @_;

    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => 'fhir',
            target_format => 'beacon',
            entities      => $self->{entities} || ['individuals'],
        }
    );

    die "Normalized FHIR input must contain a patient-scoped object\n"
      unless ref($record) eq 'HASH';
    die "Normalized FHIR input is missing its Patient resource\n"
      unless ref( $record->{patient} ) eq 'HASH'
      && ( $record->{patient}{resourceType} || q{} ) eq 'Patient';

    my $bundle = Convert::Pheno::Model::Bundle->new(
        {
            context  => $context,
            entities => $context->entities,
        }
    );

    my $patient    = $record->{patient};
    my $resources  = $record->{resources} || [];
    my $index      = $record->{resourceIndex} || {};
    my $individual = _map_patient( $patient, $record->{id} );

    my ( @specimens, @specimen_observations );
    for my $resource ( @{$resources} ) {
        next unless ref($resource) eq 'HASH';
        my $type = $resource->{resourceType} || q{};

        if ( $type eq 'Condition' ) {
            _push_mapped( $individual, 'diseases', _map_condition( $resource, $patient ) );
            next;
        }

        if ( $type eq 'Observation' ) {
            if ( ref( $resource->{specimen} ) eq 'HASH'
                && defined $resource->{specimen}{reference} )
            {
                push @specimen_observations, $resource;
                next;
            }

            my $feature = _map_hpo_observation( $resource, $patient );
            if ($feature) {
                _push_mapped( $individual, 'phenotypicFeatures', $feature );
            }
            else {
                _push_mapped( $individual, 'measures', $_ )
                  for @{ _map_observation_measurements($resource) };
            }
            next;
        }

        if ( $type eq 'Procedure' ) {
            _push_mapped(
                $individual,
                'interventionsOrProcedures',
                _map_procedure($resource),
            );
            next;
        }

        if ( $type eq 'MedicationRequest'
            || $type eq 'MedicationAdministration'
            || $type eq 'MedicationStatement' )
        {
            _push_mapped(
                $individual,
                'treatments',
                _map_medication( $resource, $index, $patient ),
            );
            next;
        }

        push @specimens, $resource if $type eq 'Specimen';
    }

    my @biosamples = grep { defined } map {
        _map_specimen(
            $self,
            $_,
            $individual->{id},
            \@specimen_observations,
            $index,
        )
    } @specimens;

    # The primary BFF view contains individuals only. Preserve a semantic
    # Phenopackets biosample representation so the fhir2pxf pipeline does not
    # lose specimens when the first-class Beacon biosamples collection is not
    # carried between pipeline stages.
    if (@biosamples) {
        $individual->{info}{phenopacket}{biosamples} = [
            map { _biosample_to_phenopacket($_) } @biosamples
        ];
    }

    if ( $self->{source_info} // 1 ) {
        my @unmapped_types = _unmapped_resource_types($resources);
        $individual->{info}{fhir} = {
            version   => 'R4',
            patient   => dclone($patient),
            resources => dclone($resources),
            bundles   => dclone( $record->{bundleMetadata} || [] ),
        };
        $individual->{info}{fhir}{unmappedResourceTypes} = \@unmapped_types
          if @unmapped_types;
    }

    unless ( $self->{test} ) {
        $individual->{info}{convertPheno} = $self->{convertPheno}
          if defined $self->{convertPheno};
    }

    $bundle->add_entity( individuals => $individual );
    if ( _context_requests_entity( $context, 'biosamples' ) ) {
        $bundle->add_entity( biosamples => $_ ) for @biosamples;
    }

    return $bundle;
}

sub _map_patient {
    my ( $patient, $fallback_id ) = @_;
    my $id = $patient->{id} // $fallback_id;
    die "FHIR Patient cannot be mapped without an identifier\n"
      unless defined $id && !ref($id) && length $id;

    my $gender = lc( $patient->{gender} // 'unknown' );
    $gender = 'unknown' unless exists $DEFAULT->{sex}{$gender};
    my $individual = {
        id  => $id,
        sex => dclone( $DEFAULT->{sex}{$gender} ),
    };

    if ( defined $patient->{birthDate} && !ref( $patient->{birthDate} ) ) {
        my $date_of_birth = $patient->{birthDate};
        $date_of_birth .= 'T00:00:00Z'
          if $date_of_birth =~ /^\d{4}-\d{2}-\d{2}\z/;
        $individual->{info}{phenopacket}{dateOfBirth} = $date_of_birth;
    }

    my $vital_status = _map_vital_status($patient);
    $individual->{info}{phenopacket}{vitalStatus} = $vital_status
      if $vital_status;

    my $ethnicity = _patient_ethnicity($patient);
    $individual->{ethnicity} = $ethnicity if $ethnicity;

    my $origin = _patient_geographic_origin($patient);
    $individual->{geographicOrigin} = $origin if $origin;

    return $individual;
}

sub _map_vital_status {
    my ($patient) = @_;

    if ( defined $patient->{deceasedDateTime}
        && !ref( $patient->{deceasedDateTime} ) )
    {
        return {
            status      => 'DECEASED',
            timeOfDeath => { timestamp => $patient->{deceasedDateTime} },
        };
    }

    if ( exists $patient->{deceasedBoolean} ) {
        return {
            status => $patient->{deceasedBoolean} ? 'DECEASED' : 'ALIVE',
        };
    }

    return;
}

sub _patient_ethnicity {
    my ($patient) = @_;

    for my $extension ( @{ $patient->{extension} || [] } ) {
        next unless ref($extension) eq 'HASH';
        next unless ( $extension->{url} || q{} ) =~ /us-core-ethnicity\z/;

        my $label;
        for my $part ( @{ $extension->{extension} || [] } ) {
            next unless ref($part) eq 'HASH';
            $label = $part->{valueString}
              if ( $part->{url} || q{} ) eq 'text'
              && defined $part->{valueString};
        }

        for my $part ( @{ $extension->{extension} || [] } ) {
            next unless ref($part) eq 'HASH';
            next unless ref( $part->{valueCoding} ) eq 'HASH';
            my $term = codeable_concept_to_term(
                {
                    coding => [ $part->{valueCoding} ],
                    text   => $label,
                },
                'Ethnicity',
            );
            return $term if $term;
        }

        return source_term( 'Ethnicity', $label, $label )
          if defined $label && length $label;
    }

    return;
}

sub _patient_geographic_origin {
    my ($patient) = @_;

    for my $extension ( @{ $patient->{extension} || [] } ) {
        next unless ref($extension) eq 'HASH';
        next unless ( $extension->{url} || q{} ) =~ /patient-birthPlace\z/;
        next unless ref( $extension->{valueAddress} ) eq 'HASH';

        my $address = $extension->{valueAddress};
        my $country = $address->{country};
        if ( defined $country && !ref($country) && length $country ) {
            my $code = uc $country;
            return $code =~ /^[A-Z]{2,3}\z/
              ? { id => "ISO3166-1:$code", label => $country }
              : source_term( 'BirthPlace', $country, $country );
        }

        my $label = join ', ', grep { defined && length }
          map { $address->{$_} } qw(city state);
        return source_term( 'BirthPlace', $label, $label ) if length $label;
    }

    return;
}

sub _map_condition {
    my ( $condition, $patient ) = @_;
    my $code = codeable_concept_to_term( $condition->{code}, 'Condition' );
    return unless $code;

    my $disease = { diseaseCode => $code };
    my $onset = _time_at_date(
        $condition->{onsetDateTime},
        $patient->{birthDate},
    );
    $disease->{ageOfOnset} = $onset if $onset;

    my $resolution = _time_at_date(
        $condition->{abatementDateTime},
        $patient->{birthDate},
    );
    $disease->{resolution} = $resolution if $resolution;

    my $verification = codeable_concept_to_term(
        $condition->{verificationStatus},
        'ConditionVerificationStatus',
    );
    if ( $verification && $verification->{id} =~ /:(?:refuted|entered-in-error)\z/i ) {
        $disease->{excluded} = JSON::PP::true();
    }

    return $disease;
}

sub _map_hpo_observation {
    my ( $observation, $patient ) = @_;
    my $feature_type = codeable_concept_to_term( $observation->{code}, 'Observation' );

    if ( !$feature_type || $feature_type->{id} !~ /^HP:/ ) {
        my $value = codeable_concept_to_term(
            $observation->{valueCodeableConcept},
            'ObservationValue',
        );
        $feature_type = $value if $value && $value->{id} =~ /^HP:/;
    }

    return unless $feature_type && $feature_type->{id} =~ /^HP:/;

    my $excluded = exists $observation->{valueBoolean}
      && !$observation->{valueBoolean};
    my $feature = {
        featureType => $feature_type,
        excluded    => $excluded ? JSON::PP::true() : JSON::PP::false(),
    };

    my $onset = _time_at_date(
        _observation_datetime($observation),
        $patient->{birthDate},
    );
    $feature->{onset} = $onset if $onset;

    return $feature;
}

sub _map_observation_measurements {
    my ($observation) = @_;
    my @measurements;

    my $measure = _map_measurement_part(
        $observation->{code},
        $observation,
        $observation,
    );
    push @measurements, $measure if $measure;

    for my $component ( @{ $observation->{component} || [] } ) {
        next unless ref($component) eq 'HASH';
        my $component_measure = _map_measurement_part(
            $component->{code},
            $component,
            $observation,
        );
        push @measurements, $component_measure if $component_measure;
    }

    return \@measurements;
}

sub _map_measurement_part {
    my ( $codeable, $value_holder, $observation ) = @_;
    my $assay = codeable_concept_to_term( $codeable, 'Observation' );
    return unless $assay;

    my $value = _measurement_value( $value_holder, $observation );
    return unless $value;

    my $measure = {
        assayCode        => $assay,
        measurementValue => $value,
    };

    my $date = _date( _observation_datetime($observation) );
    $measure->{date} = $date if $date;

    my $procedure = codeable_concept_to_term(
        $observation->{method},
        'ObservationMethod',
    );
    $measure->{procedure} = { procedureCode => $procedure }
      if $procedure;

    return $measure;
}

sub _measurement_value {
    my ( $holder, $observation ) = @_;

    if ( ref( $holder->{valueQuantity} ) eq 'HASH'
        && defined $holder->{valueQuantity}{value}
        && looks_like_number( $holder->{valueQuantity}{value} ) )
    {
        my $source = $holder->{valueQuantity};
        my $unit = quantity_unit_to_term($source)
          || dclone( $DEFAULT->{ontology_term} );
        my $quantity = {
            value => 0 + $source->{value},
            unit  => $unit,
        };

        my $range = _measurement_reference_range( $observation, $unit );
        $quantity->{referenceRange} = $range if $range;
        return { quantity => $quantity };
    }

    my $categorical = codeable_concept_to_term(
        $holder->{valueCodeableConcept},
        'ObservationValue',
    );
    return $categorical if $categorical;

    for my $field (qw(valueInteger valueDecimal)) {
        next unless defined $holder->{$field}
          && !ref( $holder->{$field} )
          && looks_like_number( $holder->{$field} );
        return {
            quantity => {
                value => 0 + $holder->{$field},
                unit  => dclone( $DEFAULT->{ontology_term} ),
            }
        };
    }

    if ( exists $holder->{valueBoolean} ) {
        my $label = $holder->{valueBoolean} ? 'true' : 'false';
        return source_term( 'Boolean', $label, $label );
    }

    for my $field (qw(valueString valueCode valueDateTime valueDate)) {
        next unless defined $holder->{$field}
          && !ref( $holder->{$field} )
          && length $holder->{$field};
        return source_term( 'ObservationValue', $holder->{$field}, $holder->{$field} );
    }

    return;
}

sub _measurement_reference_range {
    my ( $observation, $fallback_unit ) = @_;

    for my $range ( @{ $observation->{referenceRange} || [] } ) {
        next unless ref($range) eq 'HASH';
        next unless ref( $range->{low} ) eq 'HASH'
          && ref( $range->{high} ) eq 'HASH';
        next unless defined $range->{low}{value}
          && defined $range->{high}{value}
          && looks_like_number( $range->{low}{value} )
          && looks_like_number( $range->{high}{value} );

        my $unit = quantity_unit_to_term( $range->{low} )
          || quantity_unit_to_term( $range->{high} )
          || dclone($fallback_unit);
        return {
            low  => 0 + $range->{low}{value},
            high => 0 + $range->{high}{value},
            unit => $unit,
        };
    }

    return;
}

sub _map_procedure {
    my ($resource) = @_;
    my $code = codeable_concept_to_term( $resource->{code}, 'Procedure' );
    return unless $code;

    my $procedure = { procedureCode => $code };
    my $performed = $resource->{performedDateTime};
    $performed = $resource->{performedPeriod}{start}
      if !defined $performed && ref( $resource->{performedPeriod} ) eq 'HASH';
    my $date = _date($performed);
    $procedure->{dateOfProcedure} = $date if $date;

    if ( ref( $resource->{bodySite} ) eq 'ARRAY'
        && @{ $resource->{bodySite} } )
    {
        my $body_site = codeable_concept_to_term(
            $resource->{bodySite}[0],
            'BodySite',
        );
        $procedure->{bodySite} = $body_site if $body_site;
    }

    return $procedure;
}

sub _map_medication {
    my ( $resource, $index, $patient ) = @_;
    my $code = codeable_concept_to_term(
        $resource->{medicationCodeableConcept},
        'Medication',
    );

    if ( !$code && ref( $resource->{medicationReference} ) eq 'HASH' ) {
        my $reference = $resource->{medicationReference}{reference};
        my $medication = _resolve_local_or_bundle_reference(
            $resource,
            $index,
            $reference,
        );
        $code = codeable_concept_to_term( $medication->{code}, 'Medication' )
          if $medication;
    }
    return unless $code;

    my $treatment = { treatmentCode => $code };
    my $dosage = _first_dosage($resource);
    if ($dosage) {
        my $route = codeable_concept_to_term(
            $dosage->{route},
            'RouteOfAdministration',
        );
        $treatment->{routeOfAdministration} = $route if $route;
    }

    my $start = $resource->{authoredOn};
    $start = $resource->{effectiveDateTime}
      if !defined $start && defined $resource->{effectiveDateTime};
    $start = $resource->{effectivePeriod}{start}
      if !defined $start && ref( $resource->{effectivePeriod} ) eq 'HASH';
    my $age = _time_at_date( $start, $patient->{birthDate} );
    $treatment->{ageOfOnset} = $age if $age;

    return $treatment;
}

sub _first_dosage {
    my ($resource) = @_;

    return $resource->{dosage}
      if ref( $resource->{dosage} ) eq 'HASH';
    return $resource->{dosage}[0]
      if ref( $resource->{dosage} ) eq 'ARRAY'
      && @{ $resource->{dosage} }
      && ref( $resource->{dosage}[0] ) eq 'HASH';
    return $resource->{dosageInstruction}[0]
      if ref( $resource->{dosageInstruction} ) eq 'ARRAY'
      && @{ $resource->{dosageInstruction} }
      && ref( $resource->{dosageInstruction}[0] ) eq 'HASH';

    return;
}

sub _resolve_local_or_bundle_reference {
    my ( $owner, $index, $reference ) = @_;
    return unless defined $reference && !ref($reference);

    if ( $reference =~ /^#(.+)/ ) {
        my $id = $1;
        for my $contained ( @{ $owner->{contained} || [] } ) {
            next unless ref($contained) eq 'HASH';
            return $contained
              if defined $contained->{id} && $contained->{id} eq $id;
        }
        return;
    }

    return resolve_reference( $index, $reference );
}

sub _map_specimen {
    my ( $self, $specimen, $individual_id, $observations, $index ) = @_;
    my $id = $specimen->{id};
    return unless defined $id && !ref($id) && length $id;

    my $status = source_term(
        'SpecimenStatus',
        $specimen->{status} // 'unknown',
        $specimen->{status} // 'unknown',
    );
    my $origin = codeable_concept_to_term( $specimen->{type}, 'SpecimenType' )
      || dclone( $DEFAULT->{ontology_term} );

    my $biosample = {
        id               => $id,
        individualId     => $individual_id,
        biosampleStatus  => $status,
        sampleOriginType => $origin,
    };

    if ( ref( $specimen->{collection} ) eq 'HASH' ) {
        my $collection = $specimen->{collection};
        my $date = _date( $collection->{collectedDateTime} );
        $biosample->{collectionDate} = $date if $date;

        my $body_site = codeable_concept_to_term(
            $collection->{bodySite},
            'BodySite',
        );
        $biosample->{sampleOriginDetail} = $body_site if $body_site;

        my $method = codeable_concept_to_term(
            $collection->{method},
            'SpecimenCollectionMethod',
        );
        $biosample->{obtentionProcedure} = { procedureCode => $method }
          if $method;
    }

    my @notes = map { $_->{text} }
      grep { ref($_) eq 'HASH' && defined $_->{text} && !ref( $_->{text} ) }
      @{ $specimen->{note} || [] };
    $biosample->{notes} = join( "\n", @notes ) if @notes;

    my @measurements;
    my @source_observations;
    for my $observation ( @{$observations} ) {
        my $reference = $observation->{specimen}{reference};
        my $resolved  = resolve_reference( $index, $reference );
        my $matches = $resolved
          ? refaddr($resolved) == refaddr($specimen)
          : ( canonical_reference($reference) || q{} ) eq "Specimen/$id";
        next unless $matches;

        push @source_observations, $observation;
        push @measurements, @{ _map_observation_measurements($observation) };
    }
    $biosample->{measurements} = \@measurements if @measurements;

    if ( $self->{source_info} // 1 ) {
        # FHIR Observation.specimen is the provenance for deciding that these
        # measurements belong to this biosample rather than to the individual.
        $biosample->{info}{fhir} = {
            version  => 'R4',
            specimen => dclone($specimen),
        };
        $biosample->{info}{fhir}{observations} = dclone(\@source_observations)
          if @source_observations;
    }

    return $biosample;
}

sub _biosample_to_phenopacket {
    my ($biosample) = @_;
    my $pxf = {
        id             => $biosample->{id},
        individualId   => $biosample->{individualId},
        materialSample => dclone( $biosample->{biosampleStatus} ),
        sampleType     => dclone( $biosample->{sampleOriginType} ),
    };

    $pxf->{sampledTissue} = dclone( $biosample->{sampleOriginDetail} )
      if exists $biosample->{sampleOriginDetail};
    $pxf->{timeOfCollection} = {
        timestamp => $biosample->{collectionDate} . 'T00:00:00Z',
      }
      if exists $biosample->{collectionDate};

    if ( ref( $biosample->{measurements} ) eq 'ARRAY' ) {
        $pxf->{measurements} = [
            map {
                my $measurement = {
                    assay => dclone( $_->{assayCode} ),
                    value => dclone( $_->{measurementValue} ),
                };
                $measurement->{timeObserved} = {
                    timestamp => $_->{date} . 'T00:00:00Z',
                  }
                  if exists $_->{date};
                $measurement;
            } @{ $biosample->{measurements} }
        ];
    }

    return $pxf;
}

sub _observation_datetime {
    my ($observation) = @_;
    return $observation->{effectiveDateTime}
      if defined $observation->{effectiveDateTime};
    return $observation->{effectivePeriod}{start}
      if ref( $observation->{effectivePeriod} ) eq 'HASH'
      && defined $observation->{effectivePeriod}{start};
    return $observation->{issued} if defined $observation->{issued};
    return;
}

sub _time_at_date {
    my ( $timestamp, $birth_date ) = @_;
    return unless defined $timestamp && !ref($timestamp);

    my $date = _date($timestamp);
    return unless $date;

    if ( defined $birth_date && !ref($birth_date) ) {
        my $duration = get_age_from_date_and_birthday(
            {
                date      => $date,
                birth_day => $birth_date,
            }
        );
        return { age => { iso8601duration => $duration } }
          if defined $duration && $duration =~ /^P\d+Y\z/;
    }

    return $timestamp =~ /^\d{4}-\d{2}-\d{2}T/
      ? $timestamp
      : $date . 'T00:00:00Z';
}

sub _date {
    my ($value) = @_;
    return unless defined $value && !ref($value);
    return $1 if $value =~ /^(\d{4}-\d{2}-\d{2})/;
    return;
}

sub _push_mapped {
    my ( $target, $field, $value ) = @_;
    return unless defined $value;
    push @{ $target->{$field} }, $value;
    return 1;
}

sub _unmapped_resource_types {
    my ($resources) = @_;
    my %seen;
    return sort grep { !$MAPPED_RESOURCE{$_} && !$seen{$_}++ }
      map { ref($_) eq 'HASH' ? ( $_->{resourceType} || 'Unknown' ) : 'Unknown' }
      @{$resources};
}

sub _context_requests_entity {
    my ( $context, $entity ) = @_;
    return scalar grep { $_ eq $entity } @{ $context->entities };
}

1;
