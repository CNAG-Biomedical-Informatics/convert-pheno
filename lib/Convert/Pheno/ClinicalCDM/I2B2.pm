package Convert::Pheno::ClinicalCDM::I2B2;

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

our @EXPORT_OK = qw(map_i2b2_individual);

my $DEFAULT = get_defaults();

sub map_i2b2_individual {
    my ( $self, $record ) = @_;
    my $patient = $record->{patient};
    my $individual = {
        id  => "$record->{personId}",
        sex => map_sex(
            first_value( $patient, qw(SEX_CD SEX GENDER_CD GENDER) )
        ),
    };

    my $birth = timestamp_value(
        first_value( $patient, qw(BIRTH_DATE BIRTHDATE DATE_OF_BIRTH) )
    );
    $individual->{info}{phenopacket}{dateOfBirth} = $birth
      if defined $birth;

    my $death = timestamp_value(
        first_value( $patient, qw(DEATH_DATE DEATH_DATE_TIME DOD) )
    );
    if ( defined $death ) {
        $individual->{info}{phenopacket}{vitalStatus} = {
            status      => 'DECEASED',
            timeOfDeath => { timestamp => $death },
        };
    }

    my ( @diseases, @procedures, @measures, @treatments, @features );
    for my $row ( @{ table_rows( $record, 'OBSERVATION_FACT' ) } ) {
        my $code = first_value( $row, qw(CONCEPT_CD CONCEPT_CODE) );
        next unless defined $code;
        my $concept = $record->{concepts}{$code} || {};
        my $label = first_value(
            $concept,
            qw(NAME_CHAR CONCEPT_NAME NAME DESCRIPTION)
        );
        my $term = coded_term(
            model => 'i2b2',
            kind  => 'Concept',
            code  => $code,
            label => $label,
        );
        my $prefix = _concept_prefix($code);
        my $valtype = uc( first_value( $row, qw(VALTYPE_CD VALUETYPE_CD) ) // q{} );
        my $modifier = first_value( $row, qw(MODIFIER_CD) ) // '@';
        my $visit = row_visit( $record, $row, model => 'i2b2' );

        # i2b2 modifier rows describe attributes of the base observation;
        # they are not independent clinical events. Preserve them in source
        # provenance without duplicating the BFF event.
        next unless $modifier eq '@';

        if ( $valtype eq 'N' || $prefix eq 'LOINC' ) {
            my $value = _measurement_value($row);
            next unless $value;
            my $measure = {
                assayCode        => $term,
                measurementValue => $value,
            };
            my $date = date_value( first_value( $row, qw(START_DATE OBS_DATE) ) );
            $measure->{date} = $date if defined $date;
            $measure->{_visit} = $visit if $visit;
            push @measures, $measure;
            next;
        }

        if ( _is_medication_prefix($prefix) ) {
            my $treatment = { treatmentCode => $term };
            $treatment->{_visit} = $visit if $visit;
            push @treatments, $treatment;
            next;
        }

        if ( _is_procedure_prefix($prefix) ) {
            my $procedure = { procedureCode => $term };
            my $date = date_value( first_value( $row, qw(START_DATE OBS_DATE) ) );
            $procedure->{dateOfProcedure} = $date if defined $date;
            $procedure->{_visit} = $visit if $visit;
            push @procedures, $procedure;
            next;
        }

        if ( _is_diagnosis_prefix($prefix) ) {
            my $disease = { diseaseCode => $term };
            $disease->{_visit} = $visit if $visit;
            push @diseases, $disease;
            next;
        }

        my $feature = { featureType => $term };
        $feature->{_visit} = $visit if $visit;
        push @features, $feature;
    }

    $individual->{diseases}                  = \@diseases   if @diseases;
    $individual->{interventionsOrProcedures} = \@procedures if @procedures;
    $individual->{measures}                  = \@measures   if @measures;
    $individual->{treatments}                = \@treatments if @treatments;
    $individual->{phenotypicFeatures}        = \@features   if @features;

    if ( $self->{source_info} // 1 ) {
        $individual->{info}{i2b2} = {
            patient => dclone($patient),
            tables  => dclone( $record->{tables} ),
        };
    }
    $individual->{info}{convertPheno} = $self->{convertPheno}
      if !$self->{test} && defined $self->{convertPheno};
    return $individual;
}

sub _measurement_value {
    my ($row) = @_;
    my $number = numeric_value( $row, qw(NVAL_NUM NUMERIC_VALUE) );
    if ( defined $number ) {
        my $unit_label = first_value( $row, qw(UNITS_CD UNIT) );
        my $unit = defined $unit_label
          ? source_term( 'i2b2', 'Unit', $unit_label, $unit_label )
          : dclone( $DEFAULT->{ontology_term} );
        return { quantity => { value => $number, unit => $unit } };
    }
    my $text = first_value( $row, qw(TVAL_CHAR TEXT_VALUE) );
    return unless defined $text;
    return source_term( 'i2b2', 'Result', $text, $text );
}

sub _concept_prefix {
    my ($code) = @_;
    my ($prefix) = split /:/, $code, 2;
    $prefix = uc( $prefix // q{} );
    $prefix =~ s/[^A-Z0-9]+//g;
    return $prefix;
}

sub _is_diagnosis_prefix {
    my ($prefix) = @_;
    return $prefix =~ /\A(?:ICD9|ICD9CM|ICD10|ICD10CM|ICD11|SNOMED|SNOMEDCT|DX)\z/;
}

sub _is_procedure_prefix {
    my ($prefix) = @_;
    return $prefix =~ /\A(?:CPT|CPT4|HCPCS|ICD10PCS|ICD9PROC|PROC|PX)\z/;
}

sub _is_medication_prefix {
    my ($prefix) = @_;
    return $prefix =~ /\A(?:RXNORM|NDC|MED|MEDICATION|DRUG)\z/;
}

1;
