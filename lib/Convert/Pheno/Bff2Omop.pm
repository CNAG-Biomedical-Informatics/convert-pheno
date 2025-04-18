package Convert::Pheno::Bff2Omop;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Math::BigInt;
use Scalar::Util                   qw(looks_like_number);
use Convert::Pheno::Utils::Default qw(get_defaults);
use Convert::Pheno::Utils::Mapping;
use Data::Dumper;
use Exporter 'import';

our @EXPORT = qw(do_bff2omop);
my $DEFAULT                       = get_defaults();
my $MEASUREMENT_ID_COUNT          = 0;
my $DRUG_EXPOSURE_ID_COUNT        = 0;
my $OBSERVATION_ID_COUNT          = 0;
my $CONDITION_OCCURRENCE_COUNT    = 0;
my $PROCEDURE_OCCURRENCE_ID_COUNT = 0;

# one-time dispatch table
my %INVERSE_DISPATCH = map { $_ => \&_map_ohdsi_label } qw(
  gender race ethnicity disease stage
  exposure phenotypicFeature procedure
  measurement treatment unit route
);

###############
###############
#  BFF2OMOP   #
###############
###############

sub do_bff2omop {
    my ( $self, $bff ) = @_;

    # Premature return if no input
    return unless defined($bff);

    # Validate that input is in BFF format.
    die "Input format error: Are you sure your input is not already OMOP?\n"
      unless validate_format( $bff, 'bff' );

    # Convert ID string to ID integer
    my $person_id = looks_like_number( $bff->{id} )
      ? $bff->{id}    # If it already looks numeric, use it.
      : string2number( $bff->{id} );

    # Create a new OMOP structure.
    # This will be a hash with keys corresponding to OMOP table names.
    my $omop = {};

    # Convert individual components.
    # Pass the precomputed $person_id to each conversion sub.
    _map_person( $self, $bff, $omop, $person_id );
    _map_diseases( $self, $bff, $omop, $person_id );
    _map_exposures( $self, $bff, $omop, $person_id );
    _map_phenotypicFeatures( $self, $bff, $omop, $person_id );
    _map_interventionsOrProcedures( $self, $bff, $omop, $person_id );
    _map_measurements( $self, $bff, $omop, $person_id );
    _map_treatments( $self, $bff, $omop, $person_id );

    # (Optionally, additional tables such as VISIT_OCCURRENCE or OBSERVATION_PERIOD
    # could be derived from extra info in $bff.)
    #print Dumper $omop;
    return $omop;
}

###############################################################################
# Private conversion subs (each inverts part of the OMOP2BFF mapping)
###############################################################################

# Convert BFF subject and info into a PERSON record.
sub _map_person {
    my ( $self, $bff, $omop_ref, $person_id ) = @_;

    my $person;

    # Miscellanea id
    $person->{person_id}           = $person_id;
    $person->{person_source_value} = $bff->{id};

    # Map dateOfBirth (if available) to birth_datetime.
    $person->{birth_datetime} = $bff->{info}{dateOfBirth}
      // $DEFAULT->{timestamp};

    # Map dateOfBirth (if available) to birth_datetime.
    if ( defined( $bff->{info}{dateOfBirth} ) ) {
        for (qw/year month day/) {
            $person->{ $_ . '_of_birth' } =
              get_date_component( $bff->{info}{dateOfBirth}, $_ );
        }
    }
    else {
        $person->{year_of_birth} = $DEFAULT->{year};
    }

    # Convert sex: now done via our new generic inverse_map.
    ( $person->{gender_concept_id}, $person->{gender_source_value} ) =
      inverse_map( 'gender', $bff->{sex}, 'label', $self );

    ( $person->{race_concept_id}, $person->{race_source_value} ) =
      exists $bff->{ethnicity}
      ? inverse_map( 'race', $bff->{ethnicity}, 'label', $self )
      : ( $DEFAULT->{concept_id}, '' );

    ( $person->{ethnicity_concept_id}, $person->{ethnicity_source_value} ) =
      exists $bff->{geographicOrigin}
      ? inverse_map( 'ethnicity', $bff->{geographicOrigin}, 'label', $self )
      : ( $DEFAULT->{concept_id}, '' );

    # Save the PERSON record one person per individual)
    $omop_ref->{PERSON} = $person;

}

# Convert BFF diseases into OMOP CONDITION_OCCURRENCE rows.
sub _map_diseases {
    my ( $self, $bff, $omop_ref, $person_id ) = @_;

    my @conditions;

    for my $disease ( @{ $bff->{diseases} // [] } ) {
        my $cond;

        $cond->{condition_occurrence_id} = ++$CONDITION_OCCURRENCE_COUNT;

        # We now call our generic inverse_map:
        ( $cond->{condition_concept_id}, $cond->{condition_source_value} ) =
          inverse_map( 'disease', $disease->{diseaseCode}, 'label', $self );

        # Convert onset (e.g., an ISO8601 duration) to a date
        if ( $disease->{ageOfOnset}{age}{iso8601duration} ) {
            $cond->{condition_start_date} = get_date_at_age(
                $disease->{ageOfOnset}{age}{iso8601duration},
                $omop_ref->{PERSON}{year_of_birth}
            );
        }
        else {
            $cond->{condition_start_date} = $DEFAULT->{date};
        }

        # TEMPORARY SOLUTION: Setting defaults
        # mrueda: Apr-2025
        $cond->{condition_type_concept_id} = $DEFAULT->{concept_id};

        _attach_common( $cond, $disease, $person_id );

        # Optionally map stage to condition_status_concept_id.
        #if ( exists $disease->{stage} ) {
        #}

        push @conditions, $cond;
    }
    $omop_ref->{CONDITION_OCCURRENCE} = \@conditions if @conditions;

}

# Convert BFF exposures into OMOP OBSERVATION rows.
sub _map_exposures {
    my ( $self, $bff, $omop_ref, $person_id ) = @_;

    my @observations;

    for my $exposure ( @{ $bff->{exposures} // [] } ) {
        my $obs;

        $obs->{observation_id} = ++$OBSERVATION_ID_COUNT;

        # e.g., $exposure->{exposureCode} used in a generic mapping:
        ( $obs->{observation_concept_id}, $obs->{observation_source_value} ) =
          inverse_map( 'exposure', $exposure->{exposureCode}, 'label', $self );

        # Date
        $obs->{observation_date} = $exposure->{date};

        # BFF only accepts numeric
        $obs->{value_as_number} =
          defined $exposure->{value} ? $exposure->{value} : -1;

        ( $obs->{unit_concept_id}, $obs->{unit_source_value} ) =
          inverse_map( 'unit', $exposure->{unit}, 'label', $self );

        # TEMPORARY: BFF only accepts numeric
        $obs->{value_as_concept_id} = '';
        $obs->{value_as_string}     = '';

        # TEMPORARY SOLUTION: Setting defaults
        # mrueda: Apr-2025
        $obs->{observation_type_concept_id} = $DEFAULT->{concept_id};

        _attach_common( $obs, $exposure, $person_id );

        push @observations, $obs;
    }
    $omop_ref->{OBSERVATION} = \@observations if @observations;
}

# Convert BFF phenotypicFeatures into additional OMOP OBSERVATION rows.
sub _map_phenotypicFeatures {
    my ( $self, $bff, $omop_ref, $person_id ) = @_;

    my @observations;

    for my $feature ( @{ $bff->{phenotypicFeatures} // [] } ) {

        my $obs;

        next
          if ( $feature->{excluded} && $feature->{excluded} == JSON::PP::true );

        $obs->{observation_id} = ++$OBSERVATION_ID_COUNT;

        # e.g., $feature->{featureType} used in a generic mapping:
        ( $obs->{observation_concept_id}, $obs->{observation_source_value} ) =
          inverse_map( 'phenotypicFeature', $feature->{featureType},
            'label', $self );

        # Date
        if ( $feature->{onset}{iso8601duration} ) {
            $obs->{observation_date} = get_date_at_age(
                $feature->{onset}{iso8601duration},
                $omop_ref->{PERSON}{year_of_birth}
            );
        }
        else {
            $obs->{observation_date} = $DEFAULT->{date};
        }

        # BFF only accepts numeric
        $obs->{value_as_number} =
          defined $feature->{value} ? $feature->{value} : -1;

        ( $obs->{unit_concept_id}, $obs->{unit_source_value} ) =
          inverse_map( 'unit', $feature->{unit}, 'label', $self );

        # TEMPORARY: BFF only accepts numeric
        $obs->{value_as_concept_id} = '';
        $obs->{value_as_string}     = '';

        # TEMPORARY SOLUTION: Setting defaults
        # mrueda: Apr-2025
        $obs->{observation_type_concept_id} = $DEFAULT->{concept_id};

        _attach_common( $obs, $feature, $person_id );

        push @observations, $obs;
    }

    # Append these observations to any existing ones.
    if (@observations) {
        if ( exists $omop_ref->{OBSERVATION} ) {
            push @{ $omop_ref->{OBSERVATION} }, @observations;
        }
        else {
            $omop_ref->{OBSERVATION} = \@observations;
        }
    }
}

# Convert BFF interventionsOrProcedures into OMOP PROCEDURE_OCCURRENCE rows.
sub _map_interventionsOrProcedures {
    my ( $self, $bff, $omop_ref, $person_id ) = @_;
    my @procedures;

    for my $proc ( @{ $bff->{interventionsOrProcedures} // [] } ) {

        my $procedure;

        $procedure->{procedure_occurrence_id} =
          ++$PROCEDURE_OCCURRENCE_ID_COUNT;

        (
            $procedure->{procedure_concept_id},
            $procedure->{procedure_source_value}
          )
          = inverse_map( 'procedure', $proc->{procedureCode}, 'label', $self );

        $procedure->{procedure_date} =
          defined $proc->{dateOfProcedure}
          ? $proc->{dateOfProcedure}
          : $DEFAULT->{date};

        $procedure->{procedure_datetime} =
          defined $proc->{dateOfProcedure}
          ? map_iso8601_date2timestamp( $proc->{dateOfProcedure} )
          : $DEFAULT->{timestamp};

        # TEMPORARY SOLUTION: Setting defaults
        # mrueda: Apr-2025
        $procedure->{procedure_type_concept_id} = $DEFAULT->{concept_id};

        _attach_common( $procedure, $proc, $person_id );

        push @procedures, $procedure;
    }
    $omop_ref->{PROCEDURE_OCCURRENCE} = \@procedures if @procedures;
}

# Convert BFF measures into OMOP MEASUREMENT rows.
sub _map_measurements {
    my ( $self, $bff, $omop_ref, $person_id ) = @_;
    my @measurements;

    for my $measure ( @{ $bff->{measures} // [] } ) {

        my $m;
        $m->{measurement_id} = ++$MEASUREMENT_ID_COUNT;

        ( $m->{measurement_concept_id}, $m->{measurement_source_value} ) =
          inverse_map( 'measurement', $measure->{assayCode}, 'label', $self );
        $m->{measurement_date} = $measure->{date};

        # Determine measurement value.
        if ( exists $measure->{measurementValue} ) {

            # If measurementValue is a hash (e.g., with quantity details)
            if ( ref $measure->{measurementValue} eq 'HASH' ) {
                $m->{value_as_number} =
                  $measure->{measurementValue}{quantity}{value}
                  // $measure->{measurementValue}{quantity} // -1;
                $m->{range_low} =
                  $measure->{measurementValue}{quantity}{referenceRange}{low};
                $m->{range_high} =
                  $measure->{measurementValue}{quantity}{referenceRange}{high};
                ( $m->{unit_concept_id}, $m->{unit_source_value} ) =
                  inverse_map( 'unit',
                    $measure->{measurementValue}{quantity}{unit},
                    'label', $self );

            }
            else {
                $m->{value_as_number} = $measure->{measurementValue};
            }
        }
        else {
            $m->{value_as_number} = -1;
        }

        $m->{value_source_value} = $m->{value_as_number};

        # Optionally map procedure details from measurement if available.
        if ( exists $measure->{procedure} ) {
            (
                $m->{measurement_type_concept_id},
                $m->{measurement_type_source_value}
              )
              = inverse_map( 'procedure', $measure->{procedure}{procedureCode},
                'label', $self );
        }
        else {
            $m->{measurement_type_concept_id}   = $DEFAULT->{concept_id};
            $m->{measurement_type_source_value} = '';
        }

        _attach_common( $m, $measure, $person_id );

        push @measurements, $m;
    }
    $omop_ref->{MEASUREMENT} = \@measurements if @measurements;
}

# Convert BFF treatments into OMOP DRUG_EXPOSURE rows.
sub _map_treatments {
    my ( $self, $bff, $omop_ref, $person_id ) = @_;
    my @treatments;

    for my $treatment ( @{ $bff->{treatments} // [] } ) {
        my $drug;

        $drug->{drug_exposure_id} = ++$DRUG_EXPOSURE_ID_COUNT;

        # TEMPORARY
        $drug->{drug_type_concept_id} = 0;

        ( $drug->{drug_concept_id}, $drug->{drug_source_value} ) =
          inverse_map( 'treatment', $treatment->{treatmentCode},
            'label', $self );

        if ( exists $treatment->{doseIntervals}
            and @{ $treatment->{doseIntervals} } )
        {
            my $dose = $treatment->{doseIntervals}[0];
            $drug->{quantity}               = $dose->{quantity}{value} // -1;
            $drug->{dose_unit_source_value} = $dose->{quantity}{unit}{label};

        }
        else {
            $drug->{quantity} = -1;
        }

        ( $drug->{route_concept_id}, $drug->{route_source_value} ) =
          inverse_map( 'route', $treatment->{routeOfAdministration},
            'label', $self );

        # TEMPORARY: Using 1st array element
        if ( exists $treatment->{doseIntervals}
            and @{ $treatment->{doseIntervals} } )
        {
            if (   $treatment->{doseIntervals}[0]{interval}{start}
                && $treatment->{doseIntervals}[0]{interval}{end} )
            {
                #$drug->{drug_exposure_start_date} = map_iso8601_timestamp2date($treatment->{doseIntervals}[0]{interval}{start});
                #$drug->{drug_exposure_end_date} = map_iso8601_timestamp2date($treatment->{doseIntervals}[0]{interval}{send});
            }
        }
        elsif ( $treatment->{ageOfOnset}{age}{iso8601duration} ) {
            $drug->{drug_exposure_start_date} =
              get_date_at_age( $treatment->{ageOfOnset}{age}{iso8601duration},
                $omop_ref->{PERSON}{year_of_birth} );

            # TEMPORARY
            $drug->{drug_exposure_end_date} = $drug->{drug_exposure_start_date};
        }
        else {
            $drug->{drug_exposure_start_date} = $DEFAULT->{date};

            # TEMPORARY
            $drug->{drug_exposure_end_date} = $drug->{drug_exposure_start_date};
        }

        $drug->{days_supply} =
          $treatment->{cumulativeDose}{unit}{label}
          ? convert_label_to_days( $treatment->{cumulativeDose}{unit}{label},
            $drug->{quantity} )
          : '';

        _attach_common( $drug, $treatment, $person_id );

        push @treatments, $drug;
    }
    $omop_ref->{DRUG_EXPOSURE} = \@treatments if @treatments;
}

###############################################################################
# Helper sub for repeated call to map_ontology_term with ohdsi label
###############################################################################
sub _map_ohdsi_label {
    my ( $source_value, $self ) = @_;

    my $result = map_ontology_term(
        {
            query              => $source_value,
            column             => 'label',
            ontology           => 'ohdsi',
            require_concept_id => 1,
            self               => $self
        }
    );

    return ( $result->{concept_id}, $source_value );
}

###############################################################################
# New single generic sub that merges old inverse_map_* logic via a dispatch table
###############################################################################
sub inverse_map {
    my ( $mapping_type, $hashref, $key, $self ) = @_;

    # grab the handler from our static table
    my $handler = $INVERSE_DISPATCH{$mapping_type};
    unless ($handler) {
        warn "Unknown mapping type <$mapping_type>; returning (0,'')\n";
        return ( 0, '' );
    }

    # pull the value and invoke
    my $value = $hashref->{$key} // '';
    return $handler->( $value, $self );
}

sub _attach_common {

    # Individuals default schema does not provice anything related to visit
    # Taking information if Convert-Pheno set it

    my ( $row, $ent, $pid ) = @_;
    my $v = $ent->{_visit} // undef;
    $row->{visit_occurrence_id} = $v->{occurrence_id} // '';
    $row->{visit_detail_id}     = $v->{detail_id} // '';
    $row->{person_id}           = $pid;
}

1;
