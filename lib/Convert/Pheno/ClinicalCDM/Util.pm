package Convert::Pheno::ClinicalCDM::Util;

use strict;
use warnings;

use Exporter 'import';
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);

use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(
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

my $DEFAULT = get_defaults();

sub table_rows {
    my ( $record, @tables ) = @_;
    my @rows;
    push @rows, @{ $record->{tables}{$_} || [] } for @tables;
    return \@rows;
}

sub first_value {
    my ( $row, @fields ) = @_;
    return unless ref($row) eq 'HASH';
    for my $field (@fields) {
        next unless exists $row->{$field};
        my $value = $row->{$field};
        next unless defined $value && !ref($value);
        $value =~ s/^\s+|\s+$//g;
        next unless length $value;
        next if $value =~ /\A(?:NULL|\\N|\.)\z/i;
        return $value;
    }
    return;
}

sub numeric_value {
    my ( $row, @fields ) = @_;
    my $value = first_value( $row, @fields );
    return unless defined $value && looks_like_number($value);
    return 0 + $value;
}

sub map_sex {
    my ($value) = @_;
    my $sex = uc( defined $value && !ref($value) ? $value : q{} );
    $sex =~ s/^\s+|\s+$//g;
    return dclone( $DEFAULT->{sex}{male} )
      if $sex eq 'M' || $sex eq 'MALE' || $sex eq '1';
    return dclone( $DEFAULT->{sex}{female} )
      if $sex eq 'F' || $sex eq 'FEMALE' || $sex eq '2';
    return dclone( $DEFAULT->{sex}{other} )
      if $sex eq 'A' || $sex eq 'AMBIGUOUS' || $sex eq 'OTHER' || $sex eq 'OT';
    return dclone( $DEFAULT->{sex}{unknown} );
}

sub coded_term {
    my (%arg) = @_;
    my $code = _trim( $arg{code} );
    return unless defined $code && length $code;
    my $label = _trim( $arg{label} );
    $label = $code unless defined $label && length $label;

    if ( $code =~ /\A([^:\s]+):(.+)\z/ ) {
        my ( $prefix, $local ) = ( $1, $2 );
        my $normalized = _known_prefix( $prefix, $arg{kind} );
        return {
            id    => $normalized . ':' . _local_id($local),
            label => $label,
        };
    }

    my $prefix = _prefix_for_type( $arg{type}, $arg{kind} );
    return {
        id    => defined $prefix
          ? $prefix . ':' . _local_id($code)
          : _source_id( $arg{model}, $arg{kind}, $code ),
        label => $label,
    };
}

sub source_term {
    my ( $model, $kind, $value, $label ) = @_;
    $value = _trim($value);
    return unless defined $value && length $value;
    $label = _trim($label);
    $label = $value unless defined $label && length $label;
    return {
        id    => _source_id( $model, $kind, $value ),
        label => $label,
    };
}

sub date_value {
    my ($value) = @_;
    $value = _trim($value);
    return unless defined $value && length $value;
    return "$1-$2-$3" if $value =~ /\A(\d{4})[-\/](\d{2})[-\/](\d{2})/;
    return "$1-$2-$3" if $value =~ /\A(\d{4})(\d{2})(\d{2})\z/;
    return "$3-$1-$2" if $value =~ /\A(\d{2})\/(\d{2})\/(\d{4})\z/;
    return;
}

sub timestamp_value {
    my ($value) = @_;
    $value = _trim($value);
    return unless defined $value && length $value;
    if ( $value =~ /\A\d{4}-\d{2}-\d{2}T/ ) {
        $value =~ s/\s+//g;
        return $value =~ /(?:Z|[+-]\d{2}:?\d{2})\z/ ? $value : $value . 'Z';
    }
    if ( $value =~ /\A(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)(?:\s*(Z|[+-]\d{2}:?\d{2}))?\z/ ) {
        return $1 . 'T' . $2 . ( defined $3 ? $3 : 'Z' );
    }
    my $date = date_value($value);
    return defined $date ? $date . 'T00:00:00Z' : undef;
}

sub row_visit {
    my ( $record, $row, %arg ) = @_;
    my $visit_id = first_value( $row, qw(ENCOUNTERID ENCOUNTER_NUM VISIT_ID) );
    return unless defined $visit_id;

    my $visit_row = $record->{visits}{$visit_id} || {};
    my $start = timestamp_value(
        first_value(
            $visit_row,
            qw(START_DATE ADMIT_DATE ADATE ENCOUNTER_DATE)
        ) // first_value( $row, qw(START_DATE ADMIT_DATE ADATE ENCOUNTER_DATE) )
    );
    my $end = timestamp_value(
        first_value(
            $visit_row,
            qw(END_DATE DISCHARGE_DATE DDATE)
        ) // first_value( $row, qw(END_DATE DISCHARGE_DATE DDATE) )
    );
    my $type = first_value(
        $visit_row,
        qw(ENC_TYPE INOUT_CD VISIT_TYPE_CD ENCOUNTER_TYPE)
    ) // first_value( $row, qw(ENC_TYPE INOUT_CD VISIT_TYPE_CD ENCOUNTER_TYPE) );

    my $visit = {
        id            => "$visit_id",
        occurrence_id => "$visit_id",
        composite     => $record->{personId} . ':' . $visit_id,
    };
    $visit->{start_date} = $start if defined $start;
    $visit->{end_date}   = $end   if defined $end;
    $visit->{concept} = source_term( $arg{model}, 'Encounter', $type, $type )
      if defined $type;
    return $visit;
}

sub _prefix_for_type {
    my ( $type, $kind ) = @_;
    $type = uc( _trim($type) // q{} );
    $type =~ s/[^A-Z0-9]+//g;
    return unless length $type;

    return 'ICD9CM' if $type =~ /\A(?:09|9|ICD9|ICD9CM)\z/;
    if ( $type =~ /\A(?:10|ICD10|ICD10CM|ICD10PCS)\z/ ) {
        return defined $kind && lc($kind) eq 'procedure'
          ? 'ICD10PCS'
          : 'ICD10CM';
    }
    return 'ICD11'    if $type =~ /\A(?:11|ICD11|ICD11CM|ICD11PCS)\z/;
    return 'SNOMEDCT' if $type =~ /\A(?:SM|SNOMED|SNOMEDCT|SCT)\z/;
    return 'LOINC'    if $type =~ /\A(?:LC|LN|LOINC)\z/;
    return 'RxNorm'   if $type =~ /\A(?:RX|RXNORM|RXCUI)\z/;
    return 'NDC'      if $type =~ /\A(?:ND|NDC)\z/;
    return 'CVX'      if $type =~ /\A(?:CV|CVX)\z/;
    return 'CPT4'     if $type =~ /\A(?:CPT|CPT4)\z/;
    return 'HCPCS'    if $type eq 'HCPCS';
    return 'ICD10PCS' if $type eq 'PCS';
    return;
}

sub _known_prefix {
    my ( $prefix, $kind ) = @_;
    return _prefix_for_type( $prefix, $kind ) || $prefix;
}

sub _source_id {
    my ( $model, $kind, $value ) = @_;
    my %namespace = (
        i2b2     => 'i2b2',
        sentinel => 'Sentinel',
        pcornet  => 'PCORnet',
    );
    my $prefix = $namespace{ lc($model // q{}) } || 'Source';
    my $category = defined $kind ? $kind : 'Term';
    $category =~ s/[^A-Za-z0-9_.-]+/_/g;
    return $prefix . ':' . $category . '.' . _local_id($value);
}

sub _local_id {
    my ($value) = @_;
    $value = _trim($value) // 'unknown';
    $value =~ s/%/percent/g;
    $value =~ s/\s+/_/g;
    $value =~ s/[^A-Za-z0-9_.~+\/-]+/_/g;
    $value =~ s/_+/_/g;
    $value =~ s/^[_\.]+|[_\.]+$//g;
    return length $value ? $value : 'unknown';
}

sub _trim {
    my ($value) = @_;
    return unless defined $value && !ref($value);
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

1;
