package Convert::Pheno::Bff2Omop;

use strict;
use warnings;
use autodie;
use feature qw(say);
use POSIX   qw(strftime);
use Math::BigInt;
use Convert::Pheno::Default qw(get_defaults);
use Convert::Pheno::Mapping;
use Data::Dumper;
use Exporter 'import';

our @EXPORT = qw(do_bff2omop);

my $DEFAULT = get_defaults();

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

    # Create a new OMOP structure.
    # This will be a hash with keys corresponding to OMOP table names.
    my $omop = {};

    # Convert individual components.
    _convert_person( $self, $bff, $omop );
    _convert_diseases( $self, $bff, $omop );
    _convert_exposures( $self, $bff, $omop );
    _convert_phenotypicFeatures( $self, $bff, $omop );
    _convert_procedures( $self, $bff, $omop );
    _convert_measurements( $self, $bff, $omop );
    _convert_treatments( $self, $bff, $omop );

    # (Optionally, additional tables such as VISIT_OCCURRENCE or OBSERVATION_PERIOD
    # could be derived from extra info in $bff.)
    #print Dumper $omop;
    return $omop;
}

###############################################################################
# Private conversion subs (each inverts part of the OMOP2BFF mapping)
###############################################################################

# Convert BFF subject and info into a PERSON record.
sub _convert_person {
    my ( $self, $bff, $omop_ref ) = @_;

    my %person;

    # Use BFF id as the OMOP person_id.
    $person{person_id} = string2number( $bff->{id} );

    # Map dateOfBirth (if available) to birth_datetime.
    $person{birth_datetime} = $bff->{info}{dateOfBirth}
      // $DEFAULT->{timestamp};

    # Map dateOfBirth (if available) to birth_datetime.
    $person{year_of_birth} =
      defined( $bff->{info}{dateOfBirth} )
      ? get_year( $bff->{info}{dateOfBirth} )
      : $DEFAULT->{year};

    # Convert sex: now done via our new generic inverse_map.
    $person{gender_concept_id} =
      inverse_map( 'gender', $bff->{sex}, 'label', $self );

    $person{race_concept_id} =
      exists $bff->{ethnicity}
      ? inverse_map( 'race', $bff->{ethnicity}, 'label', $self )
      : $DEFAULT->{concept_id};

    $person{ethnicity_concept_id} =
      exists $bff->{geographicOrigin}
      ? inverse_map( 'ethnicity', $bff->{geographicOrigin}, 'label', $self )
      : $DEFAULT->{concept_id};

    # Save the PERSON record one person per individual)
    $omop_ref->{PERSON} = \%person;

    #print Dumper \%person;
}

# Convert BFF diseases into OMOP CONDITION_OCCURRENCE rows.
sub _convert_diseases {
    my ( $self, $bff, $omop_ref ) = @_;
    my @conditions;

    for my $disease ( @{ $bff->{diseases} // [] } ) {
        my %cond;

        # In BFF, diseaseCode and onset are provided.

        # Instead of inverse_map_disease($disease->{diseaseCode}),
        # we now call our generic inverse_map:
        $cond{condition_concept_id} =
          inverse_map( 'disease', $disease->{diseaseCode}, 'label', $self );

        # Convert onset (e.g., an ISO8601 duration) to a date (still done with inverse_find_age).
        $cond{condition_start_date} = $disease->{onset} // $DEFAULT->{date};

        # TEMPORARY
        $cond{condition_occurrence_id}   = $DEFAULT->{concept_id};
        $cond{condition_type_concept_id} = $DEFAULT->{concept_id};

        # Optionally map stage to condition_status_concept_id.
        #if ( exists $disease->{stage} ) {
        #    my $stage_hash = { val => $disease->{stage} };
        #    $cond{condition_status_concept_id} =
        #      inverse_map( 'stage', $stage_hash, 'val' );
        #}

        $cond{person_id} = string2number( $bff->{id} );
        push @conditions, \%cond;
    }
    $omop_ref->{CONDITION_OCCURRENCE} = \@conditions if @conditions;

}

# Convert BFF exposures into OMOP OBSERVATION rows.
sub _convert_exposures {
    my ( $self, $bff, $omop_ref ) = @_;
    my @observations;

    for my $exposure ( @{ $bff->{exposures} // [] } ) {
        my %obs;

        # e.g., $exposure->{exposureCode} used in a generic mapping:
        $obs{observation_concept_id} =
          inverse_map( 'exposure', $exposure->{exposureCode}, 'label', $self );
        $obs{observation_date} = $exposure->{date};

        # For this simple example, store a numeric value if available.
        $obs{value_as_number} =
          defined $exposure->{value} ? $exposure->{value} : -1;
        $obs{person_id} = string2number( $bff->{id} );
        push @observations, \%obs;
    }
    $omop_ref->{OBSERVATION} = \@observations if @observations;

    #print Dumper \@observations;
}

# Convert BFF phenotypicFeatures into additional OMOP OBSERVATION rows.
sub _convert_phenotypicFeatures {
    my ( $self, $bff, $omop_ref ) = @_;
    my @observations;

    for my $feature ( @{ $bff->{phenotypicFeatures} // [] } ) {
        my %obs;

        # e.g., $feature->{featureType} used in a generic mapping:
        $obs{observation_concept_id} = inverse_map( 'phenotypicFeature',
            { type => $feature->{featureType} }, 'type' );
        $obs{observation_date} = inverse_find_age( $feature->{onset} );
        $obs{person_id}        = string2number( $bff->{id} );
        push @observations, \%obs;
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
sub _convert_procedures {
    my ( $self, $bff, $omop_ref ) = @_;
    my @procedures;

    for my $proc ( @{ $bff->{interventionsOrProcedures} // [] } ) {
        my %procedure;
        $procedure{procedure_concept_id} =
          inverse_map( 'procedure', $proc->{procedureCode}, 'label', $self );
        $procedure{procedure_date} = $proc->{dateOfProcedure}
          // $DEFAULT->{date};

        # TEMPORARY
        $procedure{procedure_occurrence_id}   = $DEFAULT->{concept_id};
        $procedure{procedure_type_concept_id} = $DEFAULT->{concept_id};

        $procedure{person_id} = string2number( $bff->{id} );
        push @procedures, \%procedure;
    }
    $omop_ref->{PROCEDURE_OCCURRENCE} = \@procedures if @procedures;
}

# Convert BFF measures into OMOP MEASUREMENT rows.
sub _convert_measurements {
    my ( $self, $bff, $omop_ref ) = @_;
    my @measurements;

    for my $measure ( @{ $bff->{measures} // [] } ) {
        my %m;
        $m{measurement_id} = $DEFAULT->{concept_id};
        $m{measurement_concept_id} =
          inverse_map( 'measurement', $measure->{assayCode}, 'label', $self );
        $m{measurement_date} = $measure->{date};

        # Determine measurement value.
        if ( exists $measure->{measurementValue} ) {

            # If measurementValue is a hash (e.g., with quantity details)
            if ( ref $measure->{measurementValue} eq 'HASH' ) {
                $m{value_as_number} =
                  $measure->{measurementValue}{quantity}{value}
                  // $measure->{measurementValue}{quantity} // -1;
            }
            else {
                $m{value_as_number} = $measure->{measurementValue};
            }
        }
        else {
            $m{value_as_number} = -1;
        }

        # Optionally map procedure details from measurement if available.
        if ( exists $measure->{procedure} ) {
            $m{measurement_type_concept_id} =
              inverse_map( 'procedure', $measure->{procedure}{procedureCode},
                'label', $self );
            $m{measurement_date} = $measure->{procedure}{dateOfProcedure}
              // $m{measurement_date};
        }
        else {
            $m{measurement_type_concept_id} = $DEFAULT->{concept_id};
            $m{measurement_date}            = $DEFAULT->{date};
        }
        $m{person_id} = string2number( $bff->{id} );
        push @measurements, \%m;
    }
    $omop_ref->{MEASUREMENT} = \@measurements if @measurements;
}

# Convert BFF treatments into OMOP DRUG_EXPOSURE rows.
sub _convert_treatments {
    my ( $self, $bff, $omop_ref ) = @_;
    my @treatments;

    for my $treatment ( @{ $bff->{treatments} // [] } ) {
        my %drug;
        $drug{drug_concept_id} =
          inverse_map( 'treatment', $treatment->{treatmentCode},
            'label', $self );

        if ( exists $treatment->{doseIntervals}
            and @{ $treatment->{doseIntervals} } )
        {
            my $dose = $treatment->{doseIntervals}[0];
            $drug{quantity} = $dose->{quantity}{value} // 0;
        }
        else {
            $drug{quantity} = 0;
        }

        # For demonstration, use a treatment field "date" if available; otherwise default.
        $drug{drug_exposure_start_date} = $treatment->{date}
          // $DEFAULT->{date};
        $drug{person_id} = string2number( $bff->{id} );
        push @treatments, \%drug;
    }
    $omop_ref->{DRUG_EXPOSURE} = \@treatments if @treatments;
}

###############################################################################
# Additional date or stage logic can remain as separate subs if you prefer.
###############################################################################

sub inverse_find_age {
    my $onset = shift;

    # Dummy conversion: simply return today's date.
    return strftime( "%Y-%m-%d", localtime );
}

###############################################################################
# Helper sub for repeated call to map_ontology_term with ohdsi label
###############################################################################
sub _map_ohdsi_label {
    my ( $value, $self ) = @_;

    my $result = map_ontology_term(
        {
            query              => $value,
            column             => 'label',
            ontology           => 'ohdsi',
            require_concept_id => 1,
            self               => $self
        }
    );
    return $result->{concept_id};
}

###############################################################################
# New single generic sub that merges old inverse_map_* logic via a dispatch table
###############################################################################
sub inverse_map {
    my ( $mapping_type, $hashref, $key, $self ) = @_;

    # We'll look up $value from $hashref->{$key}
    my $value = $hashref->{$key} // '';

    # Dispatch table: each key is a mapping_type, each value is a subref
    my %dispatch = (
        gender => sub {

            # 8532 => female; 8507 => male
            return $value =~ /female/i ? 8532 : 8507;
        },
        map {
            $_ => sub { _map_ohdsi_label( $value, $self ) }
        } qw(race ethnicity disease stage exposure phenotypicFeature procedure measurement treatment)
    );

    # Invoke the sub for this mapping_type if it exists, else warn
    if ( exists $dispatch{$mapping_type} ) {
        return $dispatch{$mapping_type}->();
    }
    else {
        warn "Unknown mapping type <$mapping_type>. Returning 0.\n";
        return 0;
    }
}

sub string2number {
    my $big = Math::BigInt->from_bytes(shift);
    return $big->bstr;    # decimal string representing the byte
}

sub number2string {
    my $decoded_big = Math::BigInt->new(shift);
    return $decoded_big->to_bytes;
}

1;
