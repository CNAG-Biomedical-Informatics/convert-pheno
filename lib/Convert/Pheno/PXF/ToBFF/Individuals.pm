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
            my $disease = $pxf_disease;
            $disease->{diseaseCode} = $disease->{term};
            $disease->{ageOfOnset}  = $disease->{onset}
              if exists $disease->{onset};

            for (qw/excluded negated/) {
                $disease->{$_} = $disease->{$_} if exists $disease->{$_};
            }

            for (qw/term onset/) {
                delete $disease->{$_} if exists $disease->{$_};
            }

            push @{ $individual->{diseases} }, $disease;
        }
    }
}

sub _map_exposures {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{exposures} ) {
        for my $pxf_exposure ( @{ $phenopacket->{exposures} } ) {
            my $exposure = $pxf_exposure;
            $exposure->{exposureCode} = $exposure->{type};
            $exposure->{date} =
              substr( $exposure->{occurrence}{timestamp}, 0, 10 );

            $exposure->{ageAtExposure} = $DEFAULT->{iso8601duration};
            $exposure->{duration}      = $DEFAULT->{duration};
            unless ( exists $exposure->{unit} ) {
                $exposure->{unit} = $DEFAULT->{ontology_term};
            }

            for (qw/type occurence/) {
                delete $exposure->{$_} if exists $exposure->{$_};
            }

            push @{ $individual->{exposures} }, $exposure;
        }
    }
}

sub _map_id {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{subject}{id} ) {
        $individual->{id} = $phenopacket->{subject}{id};
    }
}

sub _map_info {
    my ( $self, $phenopacket, $cohort, $family, $individual ) = @_;

    for my $term (
        qw(dateOfBirth genes interpretations metaData variants files biosamples pedigree)
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
                my $procedure = $action->{procedure};
                $procedure->{procedureCode} =
                  exists $action->{procedure}{code}
                  ? $action->{procedure}{code}
                  : $DEFAULT->{ontology_term};
                $procedure->{ageOfProcedure} =
                  exists $action->{procedure}{performed}
                  ? $action->{procedure}{performed}
                  : $DEFAULT->{timestamp};

                for (qw/code performed/) {
                    delete $procedure->{$_} if exists $procedure->{$_};
                }

                push @{ $individual->{interventionsOrProcedures} }, $procedure;
            }
        }
    }
}

sub _map_karyotypicSex {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{subject}{karyotypicSex} ) {
        $individual->{karyotypicSex} = $phenopacket->{subject}{karyotypicSex};
    }
}

sub _map_measures {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{measurements} ) {
        for my $measurement ( @{ $phenopacket->{measurements} } ) {
            my $measure = $measurement;

            $measure->{assayCode} = $measure->{assay};

            map_complexValue( $measure->{complexValue} )
              if exists $measure->{complexValue};

            $measure->{measurementValue} =
                exists $measure->{value}        ? $measure->{value}
              : exists $measure->{complexValue} ? $measure->{complexValue}
              :                                   $DEFAULT->{value};
            $measure->{observationMoment} = $measure->{timeObserved}
              if exists $measure->{timeObserved};

            for (qw/assay value complexValue/) {
                delete $measure->{$_} if exists $measure->{$_};
            }

            push @{ $individual->{measures} }, $measure;
        }
    }
}

sub _map_phenotypic_features {
    my ( $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{phenotypicFeatures} ) {
        for my $feature ( @{ $phenopacket->{phenotypicFeatures} } ) {
            my $phenotypicFeature = $feature;

            for (qw/excluded negated/) {
                $phenotypicFeature->{excluded} = $phenotypicFeature->{$_}
                  if exists $phenotypicFeature->{$_};
            }

            $phenotypicFeature->{featureType} = $phenotypicFeature->{type}
              if exists $phenotypicFeature->{type};

            for (qw/negated type/) {
                delete $phenotypicFeature->{$_}
                  if exists $phenotypicFeature->{$_};
            }

            push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature;
        }
    }
}

sub _map_sex {
    my ( $self, $phenopacket, $individual ) = @_;

    if ( exists $phenopacket->{subject}{sex}
        && $phenopacket->{subject}{sex} ne '' )
    {
        $individual->{sex} = map_ontology_term(
            {
                query    => $phenopacket->{subject}{sex},
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
                my $treatment = $action->{treatment};
                $treatment->{treatmentCode} =
                  exists $action->{treatment}{agent}
                  ? $action->{treatment}{agent}
                  : $DEFAULT->{ontology_term};

                delete $treatment->{agent} if exists $treatment->{agent};

                if ( exists $treatment->{doseIntervals} ) {
                    for ( @{ $treatment->{doseIntervals} } ) {
                        unless ( exists $_->{quantity} ) {
                            $_->{quantity} = $DEFAULT->{quantity};
                        }

                        unless ( exists $_->{scheduleFrequency} ) {
                            $_->{scheduleFrequency} = $DEFAULT->{ontology_term};
                        }
                    }
                }

                push @{ $individual->{treatments} }, $treatment;
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
