package Convert::Pheno::ClinicalCDM::Claims;

use strict;
use warnings;

use Exporter 'import';
use Storable qw(dclone);

use Convert::Pheno::ClinicalCDM::Util qw(
  coded_term
  date_value
  first_value
  map_sex
  numeric_value
  row_visit
  source_term
  table_rows
  timestamp_value
);
use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(map_claims_individual);

my $DEFAULT = get_defaults();

sub map_claims_individual {
    my ( $self, $record ) = @_;
    my $model = $record->{model};
    die "Claims-CDM mapping supports Sentinel and PCORnet input\n"
      unless $model eq 'sentinel' || $model eq 'pcornet';

    my $patient = $record->{patient};
    my $individual = {
        id  => "$record->{personId}",
        sex => map_sex( first_value( $patient, qw(SEX SEX_AT_BIRTH GENDER) ) ),
    };

    _map_demographics( $individual, $patient, $model );
    _map_death( $individual, $record );
    _map_diagnoses( $individual, $record );
    _map_procedures( $individual, $record );
    _map_labs( $individual, $record );
    _map_vitals( $individual, $record );
    _map_medications( $individual, $record );
    _map_observations( $individual, $record );

    if ( $self->{source_info} // 1 ) {
        $individual->{info}{$model} = {
            patient => dclone($patient),
            tables  => dclone( $record->{tables} ),
        };
    }
    $individual->{info}{convertPheno} = $self->{convertPheno}
      if !$self->{test} && defined $self->{convertPheno};
    return $individual;
}

sub _map_demographics {
    my ( $individual, $patient, $model ) = @_;
    my $birth = timestamp_value(
        first_value( $patient, qw(BIRTH_DATE BIRTHDATE DATE_OF_BIRTH) )
    );
    $individual->{info}{phenopacket}{dateOfBirth} = $birth
      if defined $birth;

    my $ethnicity = first_value( $patient, qw(ETHNICITY ETHNIC HISPANIC) );
    if ( defined $ethnicity ) {
        my %label = (
            Y   => 'Hispanic or Latino',
            N   => 'Not Hispanic or Latino',
            OT  => 'Other',
            UN  => 'Unknown',
            NI  => 'No information',
            R   => 'Refused to answer',
        );
        $individual->{ethnicity} = source_term(
            $model,
            'Ethnicity',
            $ethnicity,
            $label{ uc($ethnicity) } // $ethnicity,
        );
    }
}

sub _map_death {
    my ( $individual, $record ) = @_;
    my $rows = table_rows( $record, qw(DEATH) );
    return unless @{$rows};

    my $status = { status => 'DECEASED' };
    my $date = timestamp_value(
        first_value( $rows->[0], qw(DEATH_DATE DOD DATE_OF_DEATH) )
    );
    $status->{timeOfDeath} = { timestamp => $date } if defined $date;
    $individual->{info}{phenopacket}{vitalStatus} = $status;
}

sub _map_diagnoses {
    my ( $individual, $record ) = @_;
    my @diseases;
    for my $table (qw(DIAGNOSIS CONDITION)) {
        for my $row ( @{ table_rows( $record, $table ) } ) {
            my $code = first_value(
                $row,
                $table eq 'DIAGNOSIS'
                  ? qw(DX DIAGNOSIS_CODE CODE)
                  : qw(CONDITION CONDITION_CODE DX CODE)
            );
            next unless defined $code;
            my $type = first_value(
                $row,
                $table eq 'DIAGNOSIS'
                  ? qw(DX_TYPE DX_CODETYPE CODE_TYPE)
                  : qw(CONDITION_TYPE DX_TYPE CODE_TYPE)
            );
            my $label = first_value(
                $row,
                qw(DX_NAME DIAGNOSIS_NAME CONDITION_NAME DESCRIPTION)
            );
            my $term = coded_term(
                model => $record->{model},
                kind  => 'Diagnosis',
                code  => $code,
                type  => $type,
                label => $label,
            );
            next unless $term;
            my $disease = { diseaseCode => $term };
            my $visit = row_visit( $record, $row, model => $record->{model} );
            $disease->{_visit} = $visit if $visit;
            push @diseases, $disease;
        }
    }
    $individual->{diseases} = \@diseases if @diseases;
}

sub _map_procedures {
    my ( $individual, $record ) = @_;
    my @procedures;
    for my $row ( @{ table_rows( $record, qw(PROCEDURE PROCEDURES IMMUNIZATION) ) } ) {
        my $code = first_value( $row, qw(PX PROCEDURE_CODE VX_CODE CODE) );
        next unless defined $code;
        my $type = first_value(
            $row,
            qw(PX_TYPE PX_CODETYPE PROCEDURE_CODE_TYPE VX_CODE_TYPE CODE_TYPE)
        );
        my $label = first_value(
            $row,
            qw(PX_NAME PROCEDURE_NAME VX_NAME DESCRIPTION)
        );
        my $term = coded_term(
            model => $record->{model},
            kind  => 'Procedure',
            code  => $code,
            type  => $type,
            label => $label,
        );
        next unless $term;
        my $procedure = { procedureCode => $term };
        my $date = date_value(
            first_value( $row, qw(PX_DATE PROCEDURE_DATE VX_DATE ADMIN_DATE) )
        );
        $procedure->{dateOfProcedure} = $date if defined $date;
        my $visit = row_visit( $record, $row, model => $record->{model} );
        $procedure->{_visit} = $visit if $visit;
        push @procedures, $procedure;
    }
    $individual->{interventionsOrProcedures} = \@procedures if @procedures;
}

sub _map_labs {
    my ( $individual, $record ) = @_;
    my @measures;
    for my $row ( @{ table_rows( $record, qw(LAB_RESULT LAB_RESULT_CM) ) } ) {
        my $loinc = first_value( $row, qw(LAB_LOINC LOINC) );
        my $code = $loinc // first_value(
            $row,
            qw(LAB_NAME TEST_NAME RAW_LAB_NAME LAB_TEST_CODE)
        );
        next unless defined $code;
        my $label = first_value(
            $row,
            qw(RAW_LAB_NAME TEST_NAME LAB_NAME DESCRIPTION)
        );
        my $assay = coded_term(
            model => $record->{model},
            kind  => 'Laboratory',
            code  => $code,
            type  => defined $loinc ? 'LOINC' : undef,
            label => $label,
        );
        my $value = _measurement_value($record, $row);
        next unless $assay && $value;

        my $measure = {
            assayCode        => $assay,
            measurementValue => $value,
        };
        my $date = date_value(
            first_value(
                $row,
                qw(RESULT_DATE SPECIMEN_DATE LAB_DATE ORDER_DATE)
            )
        );
        $measure->{date} = $date if defined $date;
        my $visit = row_visit( $record, $row, model => $record->{model} );
        $measure->{_visit} = $visit if $visit;
        push @measures, $measure;
    }
    push @measures, @{ _observation_measures($record) };
    $individual->{measures} = \@measures if @measures;
}

sub _measurement_value {
    my ( $record, $row ) = @_;
    my $number = numeric_value(
        $row,
        qw(RESULT_NUM RESULT_NUMERIC RESULT_VALUE_NUM NVAL_NUM NUMERIC_RESULT OBSCLIN_RESULT_NUM OBSCLIN_RESULT_NUMERIC)
    );
    if ( defined $number ) {
        my $unit_label = first_value(
            $row,
            qw(RESULT_UNIT UNITS_CD UNIT NUMERIC_MODIFIER_UNIT OBSCLIN_RESULT_UNIT)
        );
        my $unit = defined $unit_label
          ? source_term( $record->{model}, 'Unit', $unit_label, $unit_label )
          : dclone( $DEFAULT->{ontology_term} );
        my $quantity = { value => $number, unit => $unit };
        my $low = numeric_value( $row, qw(NORM_RANGE_LOW NORMAL_LOW_C RANGE_LOW) );
        my $high = numeric_value( $row, qw(NORM_RANGE_HIGH NORMAL_HIGH_C RANGE_HIGH) );
        if ( defined $low && defined $high ) {
            $quantity->{referenceRange} = {
                low  => $low,
                high => $high,
                unit => dclone($unit),
            };
        }
        return { quantity => $quantity };
    }

    my $text = first_value(
        $row,
        qw(RESULT_QUAL RESULT_CHAR RESULT_TEXT TVAL_CHAR RAW_RESULT OBSCLIN_RESULT_TEXT OBSCLIN_RESULT_QUAL)
    );
    return unless defined $text;
    return source_term( $record->{model}, 'Result', $text, $text );
}

sub _map_vitals {
    my ( $individual, $record ) = @_;
    my @measures = @{ $individual->{measures} || [] };
    my @definition = (
        [ [qw(HT HEIGHT)],          'LOINC:8302-2',  'Body height',             qw(HT_UNIT HEIGHT_UNIT) ],
        [ [qw(WT WEIGHT)],          'LOINC:29463-7', 'Body weight',             qw(WT_UNIT WEIGHT_UNIT) ],
        [ [qw(BMI)],                'LOINC:39156-5', 'Body mass index',          qw(BMI_UNIT) ],
        [ [qw(SYSTOLIC SBP)],       'LOINC:8480-6',  'Systolic blood pressure', qw(BP_UNIT) ],
        [ [qw(DIASTOLIC DBP)],      'LOINC:8462-4',  'Diastolic blood pressure', qw(BP_UNIT) ],
    );

    for my $row ( @{ table_rows( $record, qw(VITAL VITAL_SIGNS) ) } ) {
        for my $definition (@definition) {
            my ( $fields, $code, $label, @unit_fields ) = @{$definition};
            my $value = numeric_value( $row, @{$fields} );
            next unless defined $value;
            my $unit_label = first_value( $row, @unit_fields );
            my $unit = defined $unit_label
              ? source_term( $record->{model}, 'Unit', $unit_label, $unit_label )
              : dclone( $DEFAULT->{ontology_term} );
            my $measure = {
                assayCode        => coded_term(
                    model => $record->{model}, kind => 'Vital',
                    code => $code, label => $label,
                ),
                measurementValue => { quantity => { value => $value, unit => $unit } },
            };
            my $date = date_value(
                first_value( $row, qw(MEASURE_DATE VITAL_DATE OBS_DATE) )
            );
            $measure->{date} = $date if defined $date;
            my $visit = row_visit( $record, $row, model => $record->{model} );
            $measure->{_visit} = $visit if $visit;
            push @measures, $measure;
        }
    }
    $individual->{measures} = \@measures if @measures;
}

sub _map_medications {
    my ( $individual, $record ) = @_;
    my @treatments;
    for my $table (qw(PRESCRIBING DISPENSING MED_ADMIN INPATIENT_PHARMACY EXTERNAL_MEDS)) {
        for my $row ( @{ table_rows( $record, $table ) } ) {
            my ( $code, $type );
            if ( defined( $code = first_value( $row, qw(RXNORM_CUI RXCUI) ) ) ) {
                $type = 'RxNorm';
            }
            elsif ( defined( $code = first_value( $row, qw(NDC) ) ) ) {
                $type = 'NDC';
            }
            else {
                $code = first_value( $row, qw(RX MEDADMIN_CODE DRUG_CODE) );
                $type = first_value(
                    $row,
                    qw(RX_CODETYPE RX_TYPE MEDADMIN_TYPE DRUG_CODE_TYPE)
                );
            }
            next unless defined $code;
            my $label = first_value(
                $row,
                qw(RAW_RX_MED_NAME RX_NAME MEDICATION_NAME DRUG_NAME DESCRIPTION)
            );
            my $term = coded_term(
                model => $record->{model},
                kind  => 'Medication',
                code  => $code,
                type  => $type,
                label => $label,
            );
            next unless $term;
            my $treatment = { treatmentCode => $term };
            my $route = first_value(
                $row,
                qw(RX_ROUTE DISPENSE_ROUTE MEDADMIN_ROUTE ROUTE)
            );
            $treatment->{routeOfAdministration} = source_term(
                $record->{model}, 'Route', $route, $route,
            ) if defined $route;
            my $visit = row_visit( $record, $row, model => $record->{model} );
            $treatment->{_visit} = $visit if $visit;
            push @treatments, $treatment;
        }
    }
    $individual->{treatments} = \@treatments if @treatments;
}

sub _map_observations {
    my ( $individual, $record ) = @_;
    my @features;
    for my $table (qw(OBS_GEN FEATURE_ENGINEERING)) {
        for my $row ( @{ table_rows( $record, $table ) } ) {
            my $code = first_value(
                $row,
                qw(OBSGEN_CODE FEATURE_CODE FEATURE CODE)
            );
            next unless defined $code;
            my $type = first_value(
                $row,
                qw(OBSGEN_TYPE FE_CODETYPE FEATURE_CODE_TYPE CODE_TYPE)
            );
            my $label = first_value(
                $row,
                qw(OBSGEN_NAME FEATURE_NAME DESCRIPTION)
            );
            my $feature = {
                featureType => coded_term(
                    model => $record->{model}, kind => 'Observation',
                    code => $code, type => $type, label => $label,
                ),
            };
            my $visit = row_visit( $record, $row, model => $record->{model} );
            $feature->{_visit} = $visit if $visit;
            push @features, $feature;
        }
    }
    $individual->{phenotypicFeatures} = \@features if @features;
}

sub _observation_measures {
    my ($record) = @_;
    my @measures;
    for my $row ( @{ table_rows( $record, qw(OBS_CLIN) ) } ) {
        my $code = first_value( $row, qw(OBSCLIN_CODE CODE) );
        next unless defined $code;
        my $value = _measurement_value($record, $row);
        next unless $value;
        my $measure = {
            assayCode => coded_term(
                model => $record->{model}, kind => 'ClinicalObservation',
                code  => $code,
                type  => first_value( $row, qw(OBSCLIN_TYPE CODE_TYPE) ),
                label => first_value( $row, qw(OBSCLIN_NAME DESCRIPTION) ),
            ),
            measurementValue => $value,
        };
        my $date = date_value(
            first_value( $row, qw(OBSCLIN_START_DATE OBS_DATE) )
        );
        $measure->{date} = $date if defined $date;
        my $visit = row_visit( $record, $row, model => $record->{model} );
        $measure->{_visit} = $visit if $visit;
        push @measures, $measure;
    }
    return \@measures;
}

1;
