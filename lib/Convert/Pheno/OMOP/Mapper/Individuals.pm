package Convert::Pheno::OMOP::Mapper::Individuals;

use strict;
use warnings;
use autodie;
use feature qw(say);

use Exporter 'import';
use Convert::Pheno::OMOP::Definitions;
use Convert::Pheno::Utils::Default qw(get_defaults);
use Convert::Pheno::Mapping::Shared;

our @EXPORT_OK = qw(map_participant);

my $DEFAULT = get_defaults();

use constant DEVEL_MODE => 0;

# Initialize global hash for seen_individual entries in --stream
my %seen_individual = ();

sub map_participant {
    my ( $self, $participant ) = @_;

    my $ohdsi_dict = $self->{data_ohdsi_dict};

    # Initiate BFF structure as an empty hash reference
    my $individual = {};

    # Get cursors for 1D terms
    my $person = $participant->{PERSON};

    # Premature return as undef
    return unless defined $person->{gender_concept_id};

    _map_person( $self, $participant, $individual, $ohdsi_dict, $person );
    _map_diseases( $self, $participant, $individual, $person, $ohdsi_dict );
    _map_exposures( $self, $participant, $individual, $person, $ohdsi_dict );
    _map_phenotypicFeatures( $self, $participant, $individual, $person,
        $ohdsi_dict );
    _map_interventionsOrProcedures( $self, $participant, $individual,
        $person, $ohdsi_dict );
    _map_measures( $self, $participant, $individual, $person, $ohdsi_dict );
    _map_treatments( $self, $participant, $individual, $person, $ohdsi_dict );

    return ( $self->{stream} && avoid_seen_individuals($individual) )
      ? undef
      : $individual;
}

sub _map_person {
    my ( $self, $participant, $individual, $ohdsi_dict, $person ) = @_;

    $individual->{ethnicity} = map_ontology_term(
        {
            query    => $person->{race_source_value},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }
    ) if defined $person->{race_source_value};

    $individual->{geographicOrigin} = map_ontology_term(
        {
            query    => $person->{ethnicity_source_value},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }
    ) if defined $person->{ethnicity_source_value};

    $individual->{id} = $person->{person_id};
    $individual->{id} = qq/$individual->{id}/;

    my $table = 'PERSON';
    $individual->{info}{$table}{OMOP_columns} = $person;
    $individual->{info}{dateOfBirth} =
      map_iso8601_date2timestamp( $person->{birth_datetime} );

    unless ( $self->{test} ) {
        $individual->{info}{metaData}     = $self->{metaData};
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }

    my $sex = map2ohdsi(
        {
            ohdsi_dict => $ohdsi_dict,
            concept_id => $person->{gender_concept_id},
            self       => $self
        }
    );

    $individual->{sex} = map_ontology_term(
        {
            query    => $sex->{label},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }

    ) if $sex;
}

sub _map_diseases {
    my ( $self, $participant, $individual, $person, $ohdsi_dict ) = @_;
    my $table = 'CONDITION_OCCURRENCE';

    if ( defined $participant->{$table} ) {
        for my $field ( @{ $participant->{$table} } ) {
            my $disease;

            $disease->{ageOfOnset} = {
                age => {
                    iso8601duration => get_age_from_date_and_birthday(
                        {
                            date      => $field->{condition_start_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            $disease->{diseaseCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{condition_concept_id},
                    self       => $self
                }
            ) if defined $field->{condition_concept_id};

            $disease->{_info}{$table}{OMOP_columns} = $field;
            $disease->{stage} = $field->{condition_status_concept_id}
              ? map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{condition_status_concept_id},
                    self       => $self

                }
              )
              : $DEFAULT->{ontology_term};

            if ( exists $self->{visit_occurrence} ) {
                my $visit = map_omop_visit_occurrence(
                    {
                        person_id           => $field->{person_id},
                        visit_occurrence_id => $field->{visit_occurrence_id},
                        self                => $self,
                        ohdsi_dict          => $ohdsi_dict
                    }
                );
                $disease->{_visit} = $visit if defined $visit;
            }

            push @{ $individual->{diseases} }, $disease;
        }
    }
}

sub _map_exposures {
    my ( $self, $participant, $individual, $person, $ohdsi_dict ) = @_;
    my $table = 'OBSERVATION';

    if ( defined $participant->{$table} ) {
        for my $field ( @{ $participant->{$table} } ) {
            $field->{observation_concept_id} = 35609831 if DEVEL_MODE;

            my $field_observation_concept_id = $field->{observation_concept_id};
            next unless exists $self->{exposures}{$field_observation_concept_id};
            my $exposure;

            $exposure->{ageAtExposure} = {
                age => {
                    iso8601duration => get_age_from_date_and_birthday(
                        {
                            date      => $field->{observation_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            $exposure->{date}     = $field->{observation_date};
            $exposure->{duration} = $DEFAULT->{duration_OMOP};
            $exposure->{_info}{$table}{OMOP_columns} = $field;

            $exposure->{exposureCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{observation_concept_id},
                    self       => $self
                }
            ) if defined $field->{observation_concept_id};

            my $unit = $field->{unit_concept_id}
              ? map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{unit_concept_id},
                    self       => $self

                }
              )
              : $DEFAULT->{ontology_term};

            $exposure->{unit} = $unit;
            $exposure->{value} =
              $field->{value_as_number} eq '\\N'
              ? -1
              : $field->{value_as_number} + 0;

            push @{ $individual->{exposures} }, $exposure;
        }
    }
}

sub _map_phenotypicFeatures {
    my ( $self, $participant, $individual, $person, $ohdsi_dict ) = @_;
    my $table = 'OBSERVATION';

    if ( defined $participant->{$table} ) {
        $individual->{phenotypicFeatures} = [];

        for my $field ( @{ $participant->{$table} } ) {
            my $field_observation_concept_id = $field->{observation_concept_id};
            next if exists $self->{exposures}{$field_observation_concept_id};

            my $phenotypicFeature;

            $phenotypicFeature->{featureType} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{observation_concept_id},
                    self       => $self

                }
            ) if defined $field->{observation_concept_id};

            $phenotypicFeature->{_info}{$table}{OMOP_columns} = $field;

            $phenotypicFeature->{onset} = {
                iso8601duration => get_age_from_date_and_birthday(
                    {
                        date      => $field->{observation_date},
                        birth_day => $person->{birth_datetime}
                    }
                )
            };

            if ( exists $self->{visit_occurrence} ) {
                my $visit = map_omop_visit_occurrence(
                    {
                        person_id           => $field->{person_id},
                        visit_occurrence_id => $field->{visit_occurrence_id},
                        self                => $self,
                        ohdsi_dict          => $ohdsi_dict
                    }
                );
                $phenotypicFeature->{_visit} = $visit if defined $visit;
            }

            push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature;
        }
    }
}

sub _map_interventionsOrProcedures {
    my ( $self, $participant, $individual, $person, $ohdsi_dict ) = @_;
    my $table = 'PROCEDURE_OCCURRENCE';

    if ( defined $participant->{$table} ) {
        $individual->{interventionsOrProcedures} = [];

        for my $field ( @{ $participant->{$table} } ) {
            my $intervention;

            $intervention->{ageAtProcedure} = {
                age => {
                    iso8601duration => get_age_from_date_and_birthday(
                        {
                            date      => $field->{procedure_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            $intervention->{bodySite}        = $DEFAULT->{ontology_term};
            $intervention->{dateOfProcedure} = $field->{procedure_date};
            $intervention->{_info}{$table}{OMOP_columns} = $field;
            $intervention->{procedureCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{procedure_concept_id},
                    self       => $self

                }
            ) if defined $field->{procedure_concept_id};

            if ( exists $self->{visit_occurrence} ) {
                my $visit = map_omop_visit_occurrence(
                    {
                        person_id           => $field->{person_id},
                        visit_occurrence_id => $field->{visit_occurrence_id},
                        self                => $self,
                        ohdsi_dict          => $ohdsi_dict
                    }
                );
                $intervention->{_visit} = $visit if defined $visit;
            }

            push @{ $individual->{interventionsOrProcedures} }, $intervention;
        }
    }
}

sub _map_measures {
    my ( $self, $participant, $individual, $person, $ohdsi_dict ) = @_;
    my $table = 'MEASUREMENT';

    if ( defined $participant->{$table} ) {
        for my $field ( @{ $participant->{$table} } ) {
            $field->{unit_concept_id}             = 18753   if DEVEL_MODE;
            $field->{value_as_number}             = 20      if DEVEL_MODE;
            $field->{operator_concept_id}         = 4172756 if DEVEL_MODE;
            $field->{measurement_type_concept_id} = 4024958 if DEVEL_MODE;
            $field->{value_as_concept_id}         = 18753   if DEVEL_MODE;

            my $measure;

            if ( $field->{measurement_concept_id} ) {
                $measure->{assayCode} = map2ohdsi(
                    {
                        ohdsi_dict => $ohdsi_dict,
                        concept_id => $field->{measurement_concept_id},
                        self       => $self
                    }
                );
            }
            else {
                $measure = set_default_measure();
                next;
            }

            $measure->{date} = $field->{measurement_date};

            my $unit =
              $field->{unit_concept_id}
              ? map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{unit_concept_id},
                    self       => $self
                }
              )
              : {
                id    => "NCIT:C126101",
                label => "Not Available"
              };

            my $measurement_value;

            if ( $field->{value_as_concept_id} ) {
                $measurement_value = map2ohdsi(
                    {
                        ohdsi_dict => $ohdsi_dict,
                        concept_id => $field->{value_as_concept_id},
                        self       => $self
                    }
                );
            }
            else {
                if ( $field->{value_as_number} eq '\\N' ) {
                    $measurement_value = { quantity => $DEFAULT->{quantity} };
                }
                else {
                    $measurement_value = {
                        quantity => {
                            unit           => $unit,
                            value          => $field->{value_as_number},
                            referenceRange => $field->{operator_concept_id}
                            ? map_operator_concept_id(
                                {
                                    operator_concept_id =>
                                      $field->{operator_concept_id},
                                    value_as_number =>
                                      $field->{value_as_number},
                                    unit => $unit
                                }
                              )
                            : undef
                        }
                    };
                }
            }

            $measure->{measurementValue} = $measurement_value;
            $measure->{_info}{$table}{OMOP_columns} = $field;
            $measure->{observationMoment} = {
                age => {
                    iso8601duration => get_age_from_date_and_birthday(
                        {
                            date      => $field->{measurement_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            $measure->{procedure}{ageAtProcedure} = $measure->{observationMoment};
            $measure->{procedure}{bodySite}        = $DEFAULT->{ontology_term};
            $measure->{procedure}{dateOfProcedure} = $field->{measurement_date};
            $measure->{procedure}{procedureCode}   = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{measurement_type_concept_id},
                    self       => $self

                }
            );

            if ( exists $self->{visit_occurrence} ) {
                my $visit = map_omop_visit_occurrence(
                    {
                        person_id           => $field->{person_id},
                        visit_occurrence_id => $field->{visit_occurrence_id},
                        self                => $self,
                        ohdsi_dict          => $ohdsi_dict
                    }
                );
                $measure->{_visit} = $visit if defined $visit;
            }

            push @{ $individual->{measures} }, $measure;
        }
    }
}

sub _map_treatments {
    my ( $self, $participant, $individual, $person, $ohdsi_dict ) = @_;
    my $table = 'DRUG_EXPOSURE';

    if ( defined $participant->{$table} ) {
        $individual->{treatments} = [];

        for my $field ( @{ $participant->{$table} } ) {
            my $treatment;

            $treatment->{ageAtOnset} = {
                age => {
                    iso8601duration => get_age_from_date_and_birthday(
                        {
                            date      => $field->{drug_exposure_start_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            $treatment->{doseIntervals} = [];
            $treatment->{_info}{$table}{OMOP_columns} = $field;
            $treatment->{routeOfAdministration} = $DEFAULT->{ontology_term};
            $treatment->{treatmentCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{drug_concept_id},
                    self       => $self
                }
            ) if defined $field->{drug_concept_id};

            if ( exists $self->{visit_occurrence} ) {
                my $visit = map_omop_visit_occurrence(
                    {
                        person_id           => $field->{person_id},
                        visit_occurrence_id => $field->{visit_occurrence_id},
                        self                => $self,
                        ohdsi_dict          => $ohdsi_dict
                    }
                );
                $treatment->{_visit} = $visit if defined $visit;
            }

            push @{ $individual->{treatments} }, $treatment;
        }
    }
}

sub avoid_seen_individuals {
    my $individual = shift;
    my $id         = $individual->{id};

    my $expected_keys   = join( '_', sort qw(id info sex) );
    my $individual_keys = join( '_', sort keys %$individual );
    my $key             = $id . '_' . $individual_keys;

    if ( $individual_keys eq $expected_keys ) {
        if ( exists $seen_individual{$key} ) {
            return 1;
        }
        else {
            $seen_individual{$key} = 1;
            return 0;
        }
    }
    return 0;
}

sub set_default_measure {
    return {
        assayCode        => $DEFAULT->{ontology_term},
        date             => $DEFAULT->{date},
        measurementValue => $DEFAULT->{quantity},
        procedure        => $DEFAULT->{ontology_term}
    };
}

1;
