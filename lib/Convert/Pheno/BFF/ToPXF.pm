package Convert::Pheno::BFF::ToPXF;

use strict;
use warnings;
use autodie;
use feature                        qw(say);
use JSON::PP                       ();
use Scalar::Util                   qw(blessed);
use Convert::Pheno::Utils::Default qw(get_defaults);
use Convert::Pheno::Mapping::Shared;
use Exporter 'import';
our @EXPORT = qw(do_bff2pxf);

my $DEFAULT = get_defaults();

#############
#############
#  BFF2PXF  #
#############
#############

sub do_bff2pxf {
    my ( $self, $bff ) = @_;

    # Premature return
    return unless defined($bff);

    # Validate format
    die "Are you sure that your input is not already a pxf?\n"
      unless validate_format( $bff, 'bff' );

    #########################################
    # START MAPPING TO PHENOPACKET V2 TERMS #
    #########################################

    # Initiate PXF structure
    my $pxf = {};

    # Map id
    _map_id( $self, $bff, $pxf );

    # Map subject
    _map_subject( $self, $bff, $pxf );

    # ===================
    # phenotypicFeatures
    # ===================
    _map_phenotypic_features( $self, $bff, $pxf );

    # ============
    # measurements
    # ============
    _map_measurements( $self, $bff, $pxf );

    # ========
    # diseases
    # ========
    _map_diseases( $self, $bff, $pxf );

    # ===============
    # medicalActions
    # ===============
    _map_medical_actions( $self, $bff, $pxf );

    # =================================================
    # Phenopacket payload preserved under info.phenopacket
    # =================================================
    _map_phenopacket_payload( $self, $bff, $pxf );

    # =====
    # files
    # =====
    # (Not mapped, see original code comments)

    # =========
    # metaData
    # =========
    _map_metaData( $self, $bff, $pxf );

# =========
# exposures
# =========

# Phenopackets v2 does not define an "exposures" field in the Phenopacket schema.
#
# Sept 2023 -> pxf-tools error:
#   Message type "org.phenopackets.schema.v2.Phenopacket" has no field named "exposures".
#   Available fields: ['id', 'subject', 'phenotypicFeatures', 'measurements', 'biosamples',
#                      'interpretations', 'diseases', 'medicalActions', 'files', 'metaData']
#
# Explanation provided by @gsfk (issue #4): Exposure was proposed for v2 but not
# adopted and later removed (ga4gh/phenopacket-schema@cb8bf58). Some documentation
# still incorrectly lists it.
#
# Do not map exposures; this block is legacy.
# Tracking: https://github.com/CNAG-Biomedical-Informatics/convert-pheno/issues/4
# Observed Sept 2023; reconfirmed Feb 2026

#   $pxf->{exposures} =
#
#      [
#        map {
#            {
#                type       => $_->{exposureCode},
#                occurrence => { timestamp => $_->{date} }
#            }
#        } @{ $bff->{exposures} }
#      ]
#      if exists $bff->{exposures};

    #######################################
    # END MAPPING TO PHENOPACKET V2 TERMS #
    #######################################

    return $pxf;
}

sub _map_id {
    my ( $self, $bff, $pxf ) = @_;

    # ==
    # id
    # ==
    $pxf->{id} =
      $self->{test}
      ? undef
      : 'phenopacket_id.' . generate_random_alphanumeric_string(8);
}

sub _map_subject {
    my ( $self, $bff, $pxf ) = @_;

    # =======
    # subject
    # =======
    $pxf->{subject} = {
        id          => $bff->{id},
        vitalStatus => { status => 'ALIVE' }
        ,    #["UNKNOWN_STATUS", "ALIVE", "DECEASED"]
    };

    my $sex = _map_sex( $bff->{sex} );
    $pxf->{subject}{sex} = $sex if defined $sex;

    my $dateOfBirth = _get_phenopacket_info_term( $bff, 'dateOfBirth' );
    $pxf->{subject}{dateOfBirth} = $dateOfBirth if defined $dateOfBirth;

    # karyotypicSex
    $pxf->{subject}{karyotypicSex} = $bff->{karyotypicSex}
      if exists $bff->{karyotypicSex};
}

sub _map_phenotypic_features {
    my ( $self, $bff, $pxf ) = @_;

 # ===================
 # phenotypicFeatures
 # ===================
 # Assign transformed 'phenotypicFeatures' to $pxf, only if it's defined in $bff
    $pxf->{phenotypicFeatures} = [
        map {
            my $feature = _clone_data($_);
            my %mapped  = %{$feature};

            $mapped{type} = delete $mapped{featureType}
              if exists $mapped{featureType};
            $mapped{excluded} =
              exists $mapped{excluded}
              ? delete $mapped{excluded}
              : JSON::PP::false();
            $mapped{evidence} = _map_evidence_to_pxf( $mapped{evidence} )
              if exists $mapped{evidence};
            $mapped{onset} = _map_time_element_to_pxf( $mapped{onset} )
              if exists $mapped{onset};
            $mapped{resolution} = _map_time_element_to_pxf( $mapped{resolution} )
              if exists $mapped{resolution};

            \%mapped;
        } @{ $bff->{phenotypicFeatures} }
      ]
      if defined $bff->{phenotypicFeatures};
}

sub _map_measurements {
    my ( $self, $bff, $pxf ) = @_;

    # ============
    # measurements
    # ============
    if ( defined $bff->{measures} ) {
        $pxf->{measurements} = [];    # Initialize as an empty array reference

        for my $measure ( @{ $bff->{measures} } ) {
            my $measurementValue = _map_measurement_value_to_pxf( $measure->{measurementValue} );
            my $hasTypedQuantities =
              ref($measurementValue) eq 'HASH'
              && exists $measurementValue->{typedQuantities} ? 1 : 0;

            # Construct the hash
            my $result = { assay => _clone_data( $measure->{assayCode} ) };

            # Add the complexValue key if typedQuantities was found
            if ($hasTypedQuantities) {
                $result->{complexValue} = $measurementValue;
            }
            else {
                $result->{value} = $measurementValue;
            }
            $result->{timeObserved} = _map_time_element_to_pxf( $measure->{observationMoment} )
              if exists $measure->{observationMoment};
            $result->{timeObserved} = { timestamp => map_iso8601_date2timestamp( $measure->{date} ) }
              if !exists $result->{timeObserved}
              && exists $measure->{date};
            $result->{procedure} = map_procedures( $measure->{procedure} )
              if defined $measure->{procedure};

            # Push the resulting hash onto the pxf measurements array
            push @{ $pxf->{measurements} }, $result;
        }
    }
}

sub _map_diseases {
    my ( $self, $bff, $pxf ) = @_;

    # ========
    # diseases
    # ========
    $pxf->{diseases} = [
        map {
            my $disease = _clone_data($_);
            my %mapped  = %{$disease};

            $mapped{term} = delete $mapped{diseaseCode}
              if exists $mapped{diseaseCode};
            $mapped{onset} = _map_time_element_to_pxf( $mapped{ageOfOnset} )
              if exists $mapped{ageOfOnset};
            delete $mapped{ageOfOnset};

            \%mapped;
        } @{ $bff->{diseases} }
    ];
}

sub _map_medical_actions {
    my ( $self, $bff, $pxf ) = @_;

    # ===============
    # medicalActions
    # ===============

    # **** procedures ****
    my @procedures = map_procedures( $bff->{interventionsOrProcedures} )
      if defined $bff->{interventionsOrProcedures};

    # **** treatments ****
    my @treatments = map {
        my $treatment = _clone_data($_);
        my %mapped    = %{$treatment};
        {
            treatment => {
                agent => delete $mapped{treatmentCode},
                (
                    exists $mapped{routeOfAdministration}
                    ? ( routeOfAdministration => delete $mapped{routeOfAdministration} )
                    : ()
                ),
                (
                    exists $mapped{doseIntervals}
                    ? ( doseIntervals => delete $mapped{doseIntervals} )
                    : ()
                ),
                %mapped,
            }
        }
    } @{ $bff->{treatments} // [] };

    # Load
    push @{ $pxf->{medicalActions} }, @procedures if @procedures;
    push @{ $pxf->{medicalActions} }, @treatments if @treatments;
}

sub _map_phenopacket_payload {
    my ( $self, $bff, $pxf ) = @_;

    for my $term (qw(biosamples interpretations genes variants files pedigree)) {
        my $value = _get_phenopacket_info_term( $bff, $term );
        $pxf->{$term} = _clone_data($value) if defined $value;
    }
}

sub _map_metaData {
    my ( $self, $bff, $pxf ) = @_;

    # =========
    # metaData
    # =========
    # Depending on the origion (redcap) , _info and resources may exist
    $pxf->{metaData} =
        $self->{test} ? undef
      : defined( _get_phenopacket_info_term( $bff, 'metaData' ) )
      ? _clone_data( _get_phenopacket_info_term( $bff, 'metaData' ) )
      : get_metaData($self);
}

#----------------------------------------------------------------------
# Helper subs
#----------------------------------------------------------------------

sub _get_phenopacket_info_term {
    my ( $bff, $term ) = @_;

    return unless exists $bff->{info} && ref( $bff->{info} ) eq 'HASH';

    return $bff->{info}{phenopacket}{$term}
      if exists $bff->{info}{phenopacket}
      && ref( $bff->{info}{phenopacket} ) eq 'HASH'
      && exists $bff->{info}{phenopacket}{$term};

    return $bff->{info}{$term} if exists $bff->{info}{$term};

    return;
}

sub _clone_data {
    my ($data) = @_;
    return undef unless defined $data;

    if ( ref($data) eq 'HASH' ) {
        return { map { $_ => _clone_data( $data->{$_} ) } keys %{$data} };
    }

    if ( ref($data) eq 'ARRAY' ) {
        return [ map { _clone_data($_) } @{$data} ];
    }

    if ( blessed($data) && blessed($data) eq 'JSON::PP::Boolean' ) {
        return $data ? JSON::PP::true() : JSON::PP::false();
    }

    return $data;
}

sub _map_sex {
    my ($sex) = @_;
    return 'UNKNOWN_SEX' unless defined $sex;

    my $id    = ref($sex) eq 'HASH' ? $sex->{id}    : undef;
    my $label = ref($sex) eq 'HASH' ? $sex->{label} : $sex;

    return 'MALE'   if defined $id && $id eq 'NCIT:C20197';
    return 'FEMALE' if defined $id && $id eq 'NCIT:C16576';

    return 'MALE'        if defined $label && $label =~ /^male$/i;
    return 'FEMALE'      if defined $label && $label =~ /^female$/i;
    return 'OTHER_SEX'   if defined $label && $label =~ /^other(?:_sex)?$/i;
    return 'UNKNOWN_SEX' if defined $label
      && $label =~ /^(?:unknown(?:[_ ]sex)?|not available)$/i;

    return 'UNKNOWN_SEX';
}

sub _looks_like_pxf_time_element {
    my ($time) = @_;
    return 0 unless ref($time) eq 'HASH';

    return scalar grep { exists $time->{$_} }
      qw(age ageRange gestationalAge interval ontologyClass timestamp);
}

sub _map_time_element_to_pxf {
    my ($time) = @_;
    return unless defined $time;

    return _clone_data($time) if _looks_like_pxf_time_element($time);

    if ( !ref($time) ) {
        return {
            timestamp => $time =~ /^\d{4}-\d{2}-\d{2}$/
            ? map_iso8601_date2timestamp($time)
            : $time,
        };
    }

    return _clone_data($time) unless ref($time) eq 'HASH';

    if ( exists $time->{iso8601duration} ) {
        return { age => _clone_data($time) };
    }

    if ( exists $time->{weeks} || exists $time->{days} ) {
        return { gestationalAge => _clone_data($time) };
    }

    if ( exists $time->{id} ) {
        return { ontologyClass => _clone_data($time) };
    }

    if ( exists $time->{start} && exists $time->{end} ) {
        my $start = $time->{start};
        my $end   = $time->{end};
        return {
            ref($start) eq 'HASH' || ref($end) eq 'HASH'
            ? ( ageRange => _clone_data($time) )
            : ( interval => _clone_data($time) )
        };
    }

    return _clone_data($time);
}

sub _normalize_evidence_for_pxf {
    my ($evidence) = @_;
    return unless ref($evidence) eq 'HASH';

    my $mapped = _clone_data($evidence);
    delete $mapped->{info} if exists $mapped->{info};

    if ( exists $mapped->{reference}
        && ref( $mapped->{reference} ) eq 'HASH'
        && exists $mapped->{reference}{notes}
        && !exists $mapped->{reference}{description} )
    {
        $mapped->{reference}{description} = delete $mapped->{reference}{notes};
    }

    return $mapped;
}

sub _map_evidence_to_pxf {
    my ($evidence) = @_;
    return unless defined $evidence;

    if ( ref($evidence) eq 'HASH'
        && exists $evidence->{info}
        && ref( $evidence->{info} ) eq 'HASH'
        && exists $evidence->{info}{phenopacket}
        && ref( $evidence->{info}{phenopacket} ) eq 'HASH'
        && exists $evidence->{info}{phenopacket}{evidence}
        && ref( $evidence->{info}{phenopacket}{evidence} ) eq 'ARRAY' )
    {
        return _clone_data( $evidence->{info}{phenopacket}{evidence} );
    }

    if ( ref($evidence) eq 'ARRAY' ) {
        return [
            map { _normalize_evidence_for_pxf($_) }
              grep { defined $_ }
              map  { _normalize_evidence_for_pxf($_) } @{$evidence}
        ];
    }

    my $mapped = _normalize_evidence_for_pxf($evidence);
    return defined $mapped ? [$mapped] : undef;
}

sub _map_measurement_value_to_pxf {
    my ($value) = @_;
    return unless defined $value;

    my $mapped = _clone_data($value);
    return $mapped unless ref($mapped) eq 'HASH';

    if ( exists $mapped->{typedQuantities}
        && ref( $mapped->{typedQuantities} ) eq 'ARRAY' )
    {
        for my $typedQuantity ( @{ $mapped->{typedQuantities} } ) {
            next unless ref($typedQuantity) eq 'HASH';
            $typedQuantity->{type} = delete $typedQuantity->{quantityType}
              if exists $typedQuantity->{quantityType};
        }
    }

    return $mapped;
}

sub _map_procedure_performed {
    my ($procedure) = @_;
    return unless ref($procedure) eq 'HASH';

    return _map_time_element_to_pxf( $procedure->{ageAtProcedure} )
      if exists $procedure->{ageAtProcedure};

    return { timestamp => map_iso8601_date2timestamp( $procedure->{dateOfProcedure} ) }
      if exists $procedure->{dateOfProcedure};

    return;
}

sub map_procedures {
    my $data = shift;

    # Helper to apply mapping logic to a single item
    my $map_item = sub {
        my $item = shift;
        my %mapped;
        $mapped{bodySite} = _clone_data( $item->{bodySite} )
          if exists $item->{bodySite};
        $mapped{code} = _clone_data( $item->{procedureCode} )
          if exists $item->{procedureCode};

        my $performed = _map_procedure_performed($item);
        $mapped{performed} = $performed if defined $performed;

        return \%mapped;
    };

    # Check if the input is an array reference
    if ( ref $data eq 'ARRAY' ) {
        return map { { procedure => $map_item->($_) } } @$data;
    }

    # Otherwise, assume it's a single hash reference
    elsif ( ref $data eq 'HASH' ) {
        return $map_item->($data);    # Return mapped single object
    }
    else {
        die
          "Invalid input type: expected an array reference or hash reference.";
    }
}

1;
