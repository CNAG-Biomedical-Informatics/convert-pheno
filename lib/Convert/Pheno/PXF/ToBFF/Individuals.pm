package Convert::Pheno::PXF::ToBFF::Individuals;

use strict;
use warnings;
use autodie;

use Exporter 'import';

use Convert::Pheno::Utils::Default qw(get_defaults);
use Convert::Pheno::Mapping::Shared;

our @EXPORT_OK = qw(map_pxf_to_individual);

my $DEFAULT = get_defaults();

sub map_pxf_to_individual {
    my ( $self, $phenopacket, $cohort, $family ) = @_;

    my $individual = {};

    _map_diseases( $phenopacket, $individual );
    _map_exposures( $phenopacket, $individual );
    _map_id( $phenopacket, $individual );
    _map_info( $self, $phenopacket, $cohort, $family, $individual );
    _map_interventions_or_procedures( $phenopacket, $individual );
    _map_karyotypicSex( $phenopacket, $individual );
    _map_measures( $phenopacket, $individual );
    _map_phenotypic_features( $phenopacket, $individual );
    _map_sex( $self, $phenopacket, $individual );
    _map_treatments( $phenopacket, $individual );

    return $individual;
}

sub _map_diseases {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{diseases} ) {
        for my $pxf_disease ( @{ $phenopacket->{diseases} } ) {
            my %disease = %{$pxf_disease};
            $disease{diseaseCode} = $disease{term};
            $disease{ageOfOnset}  = _map_time_element_value( $disease{onset} )
              if exists $disease{onset};

            for (qw/excluded negated/) {
                $disease{$_} = $disease{$_} if exists $disease{$_};
            }

            for (qw/term onset/) {
                delete $disease{$_} if exists $disease{$_};
            }

            push @{ $individual->{diseases} }, \%disease;
        }
    }
}

sub _map_exposures {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{exposures} ) {
        for my $pxf_exposure ( @{ $phenopacket->{exposures} } ) {
            my %exposure = %{$pxf_exposure};
            $exposure{exposureCode} = $exposure{type};

            if ( exists $exposure{occurrence} ) {
                my $occurrence = delete $exposure{occurrence};
                my ( $date, $age_at_exposure, $unmapped_occurrence ) =
                  _map_exposure_occurrence($occurrence);

                $exposure{date} = $date if defined $date;
                $exposure{ageAtExposure} = $age_at_exposure
                  if defined $age_at_exposure;

                if ( defined $unmapped_occurrence ) {
                    $exposure{info}{phenopacket}{occurrence} = $unmapped_occurrence;
                }
            }

            unless ( exists $exposure{ageAtExposure} ) {
                $exposure{ageAtExposure} = $DEFAULT->{iso8601duration};
            }

            $exposure{duration} = $DEFAULT->{duration}
              unless exists $exposure{duration};

            unless ( exists $exposure{unit} ) {
                $exposure{unit} = $DEFAULT->{ontology_term};
            }

            delete $exposure{type} if exists $exposure{type};

            push @{ $individual->{exposures} }, \%exposure;
        }
    }
}

sub _subject_value {
    my ( $phenopacket, @keys ) = @_;

    return unless exists $phenopacket->{subject}
      && ref( $phenopacket->{subject} ) eq 'HASH';

    for my $key (@keys) {
        return $phenopacket->{subject}{$key}
          if exists $phenopacket->{subject}{$key};
    }

    return;
}

sub _top_level_value {
    my ( $phenopacket, @keys ) = @_;

    for my $key (@keys) {
        return $phenopacket->{$key} if exists $phenopacket->{$key};
    }

    return;
}

sub _map_time_element_value {
    my ($time) = @_;
    return unless defined $time;

    return $time unless ref($time);

    return $time unless ref($time) eq 'HASH';

    for my $key (
        qw(
          age
          ageRange
          age_range
          gestationalAge
          gestational_age
          interval
          timeInterval
          time_interval
          ontologyClass
          ontology_class
          timestamp
        )
      )
    {
        return $time->{$key} if exists $time->{$key};
    }

    return $time;
}

sub _map_exposure_occurrence {
    my ($occurrence) = @_;
    return unless defined $occurrence;

    return ( substr( $occurrence, 0, 10 ), undef, undef )
      unless ref($occurrence);

    return ( undef, undef, $occurrence ) unless ref($occurrence) eq 'HASH';

    my $date;
    my $age_at_exposure;
    my $handled = 0;

    if ( exists $occurrence->{timestamp} && defined $occurrence->{timestamp} ) {
        $date    = substr( $occurrence->{timestamp}, 0, 10 );
        $handled = 1;
    }

    for my $key (qw/age/) {
        next unless exists $occurrence->{$key};
        $age_at_exposure = $occurrence->{$key};
        $handled         = 1;
        last;
    }

    return ( $date, $age_at_exposure, undef ) if $handled;

    return ( undef, undef, $occurrence );
}

sub _map_procedure_performed {
    my ($performed) = @_;
    return unless defined $performed;

    my %mapped;

    if ( !ref($performed) ) {
        $mapped{dateOfProcedure} = substr( $performed, 0, 10 );
        return \%mapped;
    }

    return { info => { phenopacket => { performed => $performed } } }
      unless ref($performed) eq 'HASH';

    if ( exists $performed->{timestamp} && defined $performed->{timestamp} ) {
        $mapped{dateOfProcedure} = substr( $performed->{timestamp}, 0, 10 );
    }

    for my $key (
        qw(
          age
          ageRange
          age_range
          gestationalAge
          gestational_age
          interval
          timeInterval
          time_interval
          ontologyClass
          ontology_class
        )
      )
    {
        next unless exists $performed->{$key};
        $mapped{ageAtProcedure} = $performed->{$key};
        last;
    }

    unless ( exists $mapped{ageAtProcedure} || exists $mapped{dateOfProcedure} ) {
        $mapped{info}{phenopacket}{performed} = $performed;
    }

    return \%mapped;
}

sub _map_evidence {
    my ($evidence) = @_;
    return unless defined $evidence;

    my $mapped = _normalize_evidence(
        ref($evidence) eq 'ARRAY' ? $evidence->[0] : $evidence
    );

    return unless defined $mapped;

    if ( ref($evidence) eq 'ARRAY' ) {
        # Beacon v2 individuals still models evidence as a single object.
        $mapped->{info}{phenopacket}{evidence} = $evidence;
    }

    return $mapped;
}

sub _normalize_evidence {
    my ($evidence) = @_;
    return unless ref($evidence) eq 'HASH';

    my %mapped = %{$evidence};
    $mapped{reference} = { %{ $mapped{reference} } }
      if exists $mapped{reference}
      && ref( $mapped{reference} ) eq 'HASH';

    if ( exists $mapped{reference}
        && ref( $mapped{reference} ) eq 'HASH'
        && exists $mapped{reference}{description}
        && !exists $mapped{reference}{notes} )
    {
        $mapped{reference}{notes} = delete $mapped{reference}{description};
    }

    return \%mapped;
}

sub _merge_info_hash {
    my ( $target, $source ) = @_;
    return unless ref($source) eq 'HASH';

    for my $key ( keys %{$source} ) {
        if ( exists $target->{$key}
            && ref( $target->{$key} ) eq 'HASH'
            && ref( $source->{$key} ) eq 'HASH' )
        {
            _merge_info_hash( $target->{$key}, $source->{$key} );
            next;
        }

        $target->{$key} = $source->{$key};
    }
}

sub _map_id {
    my ( $phenopacket, $individual ) = @_;

    my $id = _subject_value( $phenopacket, qw/id/ );
    $individual->{id} = $id if defined $id;
}

sub _map_info {
    my ( $self, $phenopacket, $cohort, $family, $individual ) = @_;

    my $date_of_birth = _subject_value( $phenopacket, qw/dateOfBirth date_of_birth/ );
    $date_of_birth = _top_level_value( $phenopacket, qw/dateOfBirth date_of_birth/ )
      unless defined $date_of_birth;
    $individual->{info}{phenopacket}{dateOfBirth} = $date_of_birth
      if defined $date_of_birth;

    for my $term (
        qw(genes interpretations metaData variants files biosamples pedigree)
      )
    {
        $individual->{info}{phenopacket}{$term} = $phenopacket->{$term}
          if exists $phenopacket->{$term};
    }

    $individual->{info}{cohort} = $cohort if defined $cohort;
    $individual->{info}{family} = $family if defined $family;

    unless ( $self->{test} ) {
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }
}

sub _map_interventions_or_procedures {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{medicalActions} ) {
        for my $action ( @{ $phenopacket->{medicalActions} } ) {
            if ( exists $action->{procedure} ) {
                my %procedure = %{ $action->{procedure} };
                $procedure{procedureCode} =
                  exists $action->{procedure}{code}
                  ? $action->{procedure}{code}
                  : $DEFAULT->{ontology_term};

                if ( exists $procedure{performed} ) {
                    my $mapped_performed =
                      _map_procedure_performed( delete $procedure{performed} );
                    _merge_info_hash( \%procedure, $mapped_performed )
                      if defined $mapped_performed;
                }

                delete $procedure{code} if exists $procedure{code};

                push @{ $individual->{interventionsOrProcedures} }, \%procedure;
            }
        }
    }
}

sub _map_karyotypicSex {
    my ( $phenopacket, $individual ) = @_;

    my $karyotypic_sex =
      _subject_value( $phenopacket, qw/karyotypicSex karyotypic_sex/ );
    $individual->{karyotypicSex} = $karyotypic_sex
      if defined $karyotypic_sex;
}

sub _map_measures {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{measurements} ) {
        for my $measurement ( @{ $phenopacket->{measurements} } ) {
            my %measure = %{$measurement};

            $measure{assayCode} = $measure{assay};

            map_complexValue( $measure{complexValue} )
              if exists $measure{complexValue};

            $measure{measurementValue} =
                exists $measure{value}        ? $measure{value}
              : exists $measure{complexValue} ? $measure{complexValue}
              :                                   $DEFAULT->{value};
            $measure{observationMoment} = _map_time_element_value( $measure{timeObserved} )
              if exists $measure{timeObserved};

            for (qw/assay value complexValue/) {
                delete $measure{$_} if exists $measure{$_};
            }

            push @{ $individual->{measures} }, \%measure;
        }
    }
}

sub _map_phenotypic_features {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{phenotypicFeatures} ) {
        for my $feature ( @{ $phenopacket->{phenotypicFeatures} } ) {
            my %phenotypicFeature = %{$feature};

            for (qw/excluded negated/) {
                $phenotypicFeature{excluded} = $phenotypicFeature{$_}
                  if exists $phenotypicFeature{$_};
            }

            $phenotypicFeature{featureType} = $phenotypicFeature{type}
              if exists $phenotypicFeature{type};
            $phenotypicFeature{onset} = _map_time_element_value( $phenotypicFeature{onset} )
              if exists $phenotypicFeature{onset};
            $phenotypicFeature{evidence} = _map_evidence( $phenotypicFeature{evidence} )
              if exists $phenotypicFeature{evidence};

            for (qw/negated type/) {
                delete $phenotypicFeature{$_}
                  if exists $phenotypicFeature{$_};
            }

            push @{ $individual->{phenotypicFeatures} }, \%phenotypicFeature;
        }
    }
}

sub _map_sex {
    my ( $self, $phenopacket, $individual ) = @_;

    my $sex = _subject_value( $phenopacket, qw/sex/ );

    if ( defined $sex && $sex ne '' )
    {
        $individual->{sex} = map_ontology_term(
            {
                query    => $sex,
                column   => 'label',
                ontology => 'ncit',
                self     => $self
            }
        );
    }
}

sub _map_treatments {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{medicalActions} ) {
        for my $action ( @{ $phenopacket->{medicalActions} } ) {
            if ( exists $action->{treatment} ) {
                my %treatment = %{ $action->{treatment} };
                $treatment{treatmentCode} =
                  exists $action->{treatment}{agent}
                  ? $action->{treatment}{agent}
                  : $DEFAULT->{ontology_term};

                delete $treatment{agent} if exists $treatment{agent};

                if ( exists $treatment{doseIntervals} ) {
                    for ( @{ $treatment{doseIntervals} } ) {
                        unless ( exists $_->{quantity} ) {
                            $_->{quantity} = $DEFAULT->{quantity};
                        }

                        unless ( exists $_->{scheduleFrequency} ) {
                            $_->{scheduleFrequency} = $DEFAULT->{ontology_term};
                        }
                    }
                }

                push @{ $individual->{treatments} }, \%treatment;
            }
        }
    }
}

sub map_complexValue {
    my $complexValue = shift;

    for ( @{ $complexValue->{typedQuantities} } ) {
        $_->{quantityType} = delete $_->{type};
    }

    return 1;
}

1;
