package Convert::Pheno::CDISC::SDTM::ToBFF;

use strict;
use warnings;

use Exporter 'import';
use JSON::PP ();
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);

use Convert::Pheno::CDISC::SDTM::Terminology qw(resolve_sdtm_term);
use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(run_sdtm_to_bundle);

my $DEFAULT = get_defaults();
my %MAPPED_DOMAIN = map { $_ => 1 } qw(DM MH AE LB VS CM EX PR);

sub run_sdtm_to_bundle {
    my ( $self, $subject, $context ) = @_;

    my $source_format = ref($subject) eq 'HASH'
      ? ( $subject->{sourceFormat} // 'dataset-json' )
      : 'dataset-json';
    my $format_label = $source_format eq 'dataset-xml'
      ? 'Dataset-XML'
      : 'Dataset-JSON';
    my $provenance_key = $source_format eq 'dataset-xml'
      ? 'datasetXml'
      : 'datasetJson';

    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => $source_format,
            target_format => 'beacon',
            entities      => $self->{entities} || ['individuals'],
        }
    );

    die "Normalized $format_label subject input must contain an object\n"
      unless ref($subject) eq 'HASH';
    die "Normalized $format_label subject input is missing its id\n"
      unless defined $subject->{id} && length $subject->{id};
    die "Normalized $format_label subject <$subject->{id}> is missing DM\n"
      unless ref( $subject->{domains}{DM} ) eq 'ARRAY'
      && @{ $subject->{domains}{DM} } == 1;

    my $bundle = Convert::Pheno::Model::Bundle->new(
        {
            context  => $context,
            entities => $context->entities,
        }
    );

    my $dm = $subject->{domains}{DM}[0];
    my $individual = {
        id  => $subject->{id},
        sex => _map_sex( $dm->{SEX} ),
    };

    _map_demographics( $self, $dm, $individual );
    _append_mapped_rows( $self, $subject->{domains}{MH}, $individual, 'diseases',                  \&_map_medical_history, 'MH' );
    _append_mapped_rows( $self, $subject->{domains}{AE}, $individual, 'phenotypicFeatures',        \&_map_adverse_event, 'AE' );
    _append_mapped_rows( $self, $subject->{domains}{LB}, $individual, 'measures',                  \&_map_measurement, 'LB' );
    _append_mapped_rows( $self, $subject->{domains}{VS}, $individual, 'measures',                  \&_map_measurement, 'VS' );
    _append_mapped_rows( $self, $subject->{domains}{CM}, $individual, 'treatments',                \&_map_treatment, 'CM' );
    _append_mapped_rows( $self, $subject->{domains}{EX}, $individual, 'treatments',                \&_map_treatment, 'EX' );
    _append_mapped_rows( $self, $subject->{domains}{PR}, $individual, 'interventionsOrProcedures', \&_map_procedure, 'PR' );

    if ( $self->{source_info} // 1 ) {
        my @unmapped = sort grep { !$MAPPED_DOMAIN{$_} } keys %{ $subject->{domains} || {} };
        $individual->{info}{$provenance_key} = {
            %{ dclone( $subject->{metadata} || {} ) },
            domains => dclone( $subject->{domains} || {} ),
        };
        $individual->{info}{$provenance_key}{unmappedDomains} = \@unmapped
          if @unmapped;
    }

    unless ( $self->{test} ) {
        $individual->{info}{convertPheno} = $self->{convertPheno}
          if defined $self->{convertPheno};
    }

    $bundle->add_entity( individuals => $individual );
    return $bundle;
}

sub _map_demographics {
    my ( $self, $dm, $individual ) = @_;

    my $ethnicity = _first_value( $dm, qw(ETHNIC) );
    $individual->{ethnicity} = _resolved_source_term(
        $self, 'DM', 'ETHNIC', $ethnicity, $ethnicity, 'ETHNIC', 'DM[1]'
      )
      if defined $ethnicity;

    my $country = _first_value( $dm, qw(COUNTRY) );
    if ( defined $country ) {
        my $country_code = uc $country;
        my $fallback =
          $country_code =~ /\A[A-Z]{2,3}\z/
          ? { id => "ISO3166-1:$country_code", label => $country }
          : _source_term( 'COUNTRY', $country, $country );
        $individual->{geographicOrigin} = resolve_sdtm_term(
            {
                self          => $self,
                domain        => 'DM',
                field         => 'COUNTRY',
                value         => $country,
                label         => $country,
                source_record => 'DM[1]',
                fallback      => $fallback,
            }
        );
    }

    my $birth = _timestamp( _first_value( $dm, qw(BRTHDTC) ) );
    $individual->{info}{phenopacket}{dateOfBirth} = $birth
      if defined $birth;

    my $death_flag = uc( _first_value( $dm, qw(DTHFL) ) // q{} );
    my $death_date = _first_value( $dm, qw(DTHDTC) );
    if ( $death_flag eq 'Y' || defined $death_date ) {
        $individual->{info}{phenopacket}{vitalStatus} = {
            status => 'DECEASED',
        };
        my $death_timestamp = _timestamp($death_date);
        $individual->{info}{phenopacket}{vitalStatus}{timeOfDeath} = {
            timestamp => $death_timestamp,
          }
          if defined $death_timestamp;
    }

    return 1;
}

sub _map_medical_history {
    my ( $self, $row, $source_record ) = @_;
    my ( $code_field, $code ) = _first_named_value( $row, qw(MHDECOD MHTERM) );
    return unless defined $code;

    my $label = _first_value( $row, qw(MHTERM MHDECOD) );
    return {
        diseaseCode => _resolved_source_term(
            $self, 'MH', $code_field, $code, $label, $code_field, $source_record
        ),
    };
}

sub _map_adverse_event {
    my ( $self, $row, $source_record ) = @_;
    my ( $code_field, $code ) = _first_named_value( $row, qw(AEDECOD AETERM) );
    return unless defined $code;

    my $label = _first_value( $row, qw(AETERM AEDECOD) );
    my $feature = {
        featureType => _resolved_source_term(
            $self, 'AE', $code_field, $code, $label, $code_field, $source_record
        ),
        excluded    => JSON::PP::false(),
    };

    my $severity = _first_value( $row, qw(AESEV) );
    $feature->{severity} = _resolved_source_term(
        $self, 'AE', 'AESEV', $severity, $severity, 'AESEV', $source_record
      )
      if defined $severity;

    my $onset = _timestamp( _first_value( $row, qw(AESTDTC) ) );
    my $resolution = _timestamp( _first_value( $row, qw(AEENDTC) ) );
    $feature->{onset}      = { timestamp => $onset }      if defined $onset;
    $feature->{resolution} = { timestamp => $resolution } if defined $resolution;

    return $feature;
}

sub _map_measurement {
    my ( $self, $row, $source_record ) = @_;
    my $domain = uc( _first_value( $row, qw(DOMAIN) ) // q{} );
    return unless $domain eq 'LB' || $domain eq 'VS';

    my $test_code_field = $domain . 'TESTCD';
    my $test_label_field = $domain . 'TEST';
    my $result_number_field = $domain . 'STRESN';
    my $result_text_field   = $domain . 'STRESC';
    my $unit_field          = $domain . 'STRESU';
    my $low_field           = $domain . 'STNRLO';
    my $high_field          = $domain . 'STNRHI';
    my $date_field          = $domain . 'DTC';

    my ( $code_field, $code ) =
      _first_named_value( $row, $test_code_field, $test_label_field );
    return unless defined $code;

    my $label = _first_value( $row, $test_label_field, $test_code_field );
    my $measure = {
        assayCode => _resolved_source_term(
            $self, $domain, $code_field, $code, $label, $code_field, $source_record
        ),
    };

    my $numeric = _first_value( $row, $result_number_field );
    if ( defined $numeric && looks_like_number($numeric) ) {
        my $unit_label = _first_value( $row, $unit_field );
        my $unit = defined $unit_label
          ? _resolved_source_term(
              $self, $domain, $unit_field, $unit_label, $unit_label, 'UNIT', $source_record
            )
          : dclone( $DEFAULT->{ontology_term} );
        my $quantity = {
            value => 0 + $numeric,
            unit  => $unit,
        };

        my $low  = _first_value( $row, $low_field );
        my $high = _first_value( $row, $high_field );
        if ( defined $low
            && defined $high
            && looks_like_number($low)
            && looks_like_number($high) )
        {
            $quantity->{referenceRange} = {
                low  => 0 + $low,
                high => 0 + $high,
                unit => dclone($unit),
            };
        }

        $measure->{measurementValue} = { quantity => $quantity };
    }
    else {
        my $text = _first_value( $row, $result_text_field );
        return unless defined $text;
        $measure->{measurementValue} = _resolved_source_term(
            $self, $domain, $result_text_field, $text, $text,
            $result_text_field, $source_record
        );
    }

    my $date = _date( _first_value( $row, $date_field ) );
    $measure->{date} = $date if defined $date;

    return $measure;
}

sub _map_treatment {
    my ( $self, $row, $source_record ) = @_;
    my $domain = uc( _first_value( $row, qw(DOMAIN) ) // q{} );
    return unless $domain eq 'CM' || $domain eq 'EX';

    my @code_fields = $domain eq 'CM' ? qw(CMDECOD CMTRT) : qw(EXTRT);
    my ( $code_field, $code ) = _first_named_value( $row, @code_fields );
    return unless defined $code;

    my $label = $domain eq 'CM'
      ? _first_value( $row, qw(CMTRT CMDECOD) )
      : _first_value( $row, qw(EXTRT) );
    my $treatment = {
        treatmentCode => _resolved_source_term(
            $self, $domain, $code_field, $code, $label, $code_field, $source_record
        ),
    };

    my $route_field = $domain . 'ROUTE';
    my $route = _first_value( $row, $route_field );
    $treatment->{routeOfAdministration} =
      _resolved_source_term(
        $self, $domain, $route_field, $route, $route, $route_field, $source_record
      )
      if defined $route;

    return $treatment;
}

sub _map_procedure {
    my ( $self, $row, $source_record ) = @_;
    my ( $code_field, $code ) = _first_named_value( $row, qw(PRDECOD PRTRT) );
    return unless defined $code;

    my $label = _first_value( $row, qw(PRTRT PRDECOD) );
    my $procedure = {
        procedureCode => _resolved_source_term(
            $self, 'PR', $code_field, $code, $label, $code_field, $source_record
        ),
    };

    my $date = _date( _first_value( $row, qw(PRSTDTC) ) );
    $procedure->{dateOfProcedure} = $date if defined $date;

    my $body_site = _first_value( $row, qw(PRLOC) );
    $procedure->{bodySite} = _resolved_source_term(
        $self, 'PR', 'PRLOC', $body_site, $body_site, 'PRLOC', $source_record
      )
      if defined $body_site;

    return $procedure;
}

sub _append_mapped_rows {
    my ( $self, $rows, $individual, $target, $mapper, $domain ) = @_;
    return 1 unless ref($rows) eq 'ARRAY';

    for my $index ( 0 .. $#{$rows} ) {
        my $mapped = $mapper->(
            $self,
            $rows->[$index],
            $domain . '[' . ( $index + 1 ) . ']',
        );
        push @{ $individual->{$target} }, $mapped if defined $mapped;
    }

    delete $individual->{$target}
      if exists $individual->{$target} && !@{ $individual->{$target} };
    return 1;
}

sub _resolved_source_term {
    my ( $self, $domain, $field, $value, $label, $fallback_field, $source_record ) = @_;
    return resolve_sdtm_term(
        {
            self          => $self,
            domain        => $domain,
            field         => $field,
            value         => $value,
            label         => $label,
            source_record => $source_record,
            fallback      => _source_term( $fallback_field, $value, $label ),
        }
    );
}

sub _map_sex {
    my ($value) = @_;
    my $sex = uc( _trim($value) // q{} );

    return dclone( $DEFAULT->{sex}{male} )   if $sex eq 'M' || $sex eq 'MALE';
    return dclone( $DEFAULT->{sex}{female} ) if $sex eq 'F' || $sex eq 'FEMALE';
    return dclone( $DEFAULT->{sex}{other} )
      if $sex eq 'UNDIFFERENTIATED' || $sex eq 'OTHER';
    return dclone( $DEFAULT->{sex}{unknown} );
}

# Dataset-JSON supplies SDTM codelist values rather than resolved ontology
# identifiers. These source-derived CURIEs preserve that identity without
# claiming that the value was mapped to an external terminology. Whitespace and
# punctuation are normalized because Beacon API implementations commonly use
# CURIEs as path or query values even though the Beacon schema is permissive.
sub _source_term {
    my ( $field, $value, $label ) = @_;
    my $component = _curie_component($value);
    my $namespace = _curie_component($field);
    return {
        id    => "CDISC:$namespace.$component",
        label => defined $label && length _trim($label) ? _trim($label) : $value,
    };
}

sub _curie_component {
    my ($value) = @_;
    $value = uc( _trim($value) // 'NA' );
    $value =~ s/[^A-Z0-9._~-]+/_/g;
    $value =~ s/_+/_/g;
    $value =~ s/^[_\.]+|[_\.]+$//g;
    return length($value) ? $value : 'NA';
}

sub _first_named_value {
    my ( $row, @fields ) = @_;
    for my $field (@fields) {
        my $value = _first_value( $row, $field );
        return ( $field, $value ) if defined $value;
    }
    return;
}

sub _first_value {
    my ( $row, @fields ) = @_;
    for my $field (@fields) {
        next unless exists $row->{$field};
        my $value = _trim( $row->{$field} );
        return $value if defined $value && length $value;
    }
    return;
}

sub _date {
    my ($value) = @_;
    return unless defined $value;
    return $1 if $value =~ /\A(\d{4}-\d{2}-\d{2})(?:T|\z)/;
    return;
}

sub _timestamp {
    my ($value) = @_;
    return unless defined $value;
    return "$1T00:00:00Z" if $value =~ /\A(\d{4}-\d{2}-\d{2})\z/;
    return $value if $value =~ /\A\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:?\d{2})\z/;
    return $value . 'Z'
      if $value =~ /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?\z/;
    return;
}

sub _trim {
    my ($value) = @_;
    return unless defined $value;
    return $value if ref($value);
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

1;
