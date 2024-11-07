package Convert::Pheno::OMOP;

use strict;
use warnings;
use autodie;
use feature qw(say);

#use Data::Dumper;
use Convert::Pheno::Default qw(get_defaults);
use Convert::Pheno::Mapping;
use Exporter 'import';
our @EXPORT =
  qw(do_omop2bff $omop_version $omop_main_table @omop_array_tables @omop_essential_tables @stream_ram_memory_tables);

my $DEFAULT = get_defaults();

use constant DEVEL_MODE => 0;

our $omop_version    = 'v5.4';
our $omop_main_table = {
    'v5.4' => [
        qw(
          PERSON
          OBSERVATION_PERIOD
          VISIT_OCCURRENCE
          VISIT_DETAIL
          CONDITION_OCCURRENCE
          DRUG_EXPOSURE
          PROCEDURE_OCCURRENCE
          DEVICE_EXPOSURE
          MEASUREMENT
          OBSERVATION
          NOTE
          NOTE_NLP
          SPECIMEN
          FACT_RELATIONSHIP
          SURVEY_CONDUCT
        )
    ],
    'v6' => [
        qw(
          PERSON
          OBSERVATION_PERIOD
          VISIT_OCCURRENCE
          VISIT_DETAIL
          CONDITION_OCCURRENCE
          DRUG_EXPOSURE
          PROCEDURE_OCCURRENCE
          DEVICE_EXPOSURE
          MEASUREMENT
          OBSERVATION
          DEATH
          NOTE
          NOTE_NLP
          SPECIMEN
          FACT_RELATIONSHIP
        )
    ]
};

# NB: Direct export w/o encapsulation in subroutine
our @omop_array_tables = qw(
  MEASUREMENT
  OBSERVATION
  CONDITION_OCCURRENCE
  PROCEDURE_OCCURRENCE
  DRUG_EXPOSURE
  VISIT_OCCURRENCE
);

# NB: Direct export w/o encapsulation in subroutine
our @omop_essential_tables = qw(
  CONCEPT
  CONDITION_OCCURRENCE
  PERSON
  PROCEDURE_OCCURRENCE
  MEASUREMENT
  OBSERVATION
  DRUG_EXPOSURE
  VISIT_OCCURRENCE
);

# NB: Direct export w/o encapsulation in subroutine
our @stream_ram_memory_tables = qw/CONCEPT PERSON VISIT_OCCURRENCE/;

# Initialize global hash for seen_individual entries in --stream
my %seen_individual = ();

##############
##############
#  OMOP2BFF  #
##############
##############

sub do_omop2bff {

    my ( $self, $participant ) = @_;

    my $ohdsi_dict = $self->{data_ohdsi_dict};
    my $sth        = $self->{sth};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # Initiate BFF structure
    my $individual;

    # Get cursors for 1D terms
    my $person = $participant->{PERSON};

    # $participant = input data
    # $person = cursor to $participant->PERSON
    # $individual = output data

    # ABOUT REQUIRED PROPERTIES
    # 'id' and 'sex' are required properties in <individuals>
    # 'person_id' must exist at this point otherwise it would have not been created
    # Premature return as undef
    return unless defined $person->{gender_concept_id};

    # ========
    # diseases
    # ========

    my $table = 'CONDITION_OCCURRENCE';

    # Table CONDITION_OCCURRENCE
    #  1	condition_concept_id
    #  2	condition_end_date
    #  3	condition_end_datetime
    #  4	condition_occurrence_id
    #  5	condition_source_concept_id
    #  6	condition_source_value
    #  7	condition_start_date
    #  8	condition_start_datetime
    #  9	condition_status_concept_id
    # 10	condition_status_source_value
    # 11	condition_type_concept_id
    # 12	person_id
    # 13	provider_id
    # 14	stop_reason
    # 15	visit_detail_id
    # 16	visit_occurrence_id

    if ( defined $participant->{$table} ) {

        for my $field ( @{ $participant->{$table} } ) {
            my $disease;

            $disease->{ageOfOnset} = {
                age => {
                    iso8601duration => find_age(

                        #_birth_datetime => $person->{birth_datetime}, # Property not allowed
                        #_procedure_date => $field->{procedure_date},  # Property not allowed
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

            #$disease->{familyHistory} = convert2boolean(
            #    map2redcap_dict(
            #        {
            #            redcap_dict  => $redcap_dict,
            #            participant => $participant,
            #            field       => 'family_history'
            #        }
            #    )
            #) if $participant->{family_history} ne '';

            # notes MUST be string
            # _info (Autovivification)
            $disease->{_info}{$table}{OMOP_columns} = $field;

            #$disease->{severity} = undef;
            $disease->{stage} = $field->{condition_status_concept_id} ? map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{condition_status_concept_id},
                    self       => $self

                }
            ) : $DEFAULT->{ontology_term};

            # NB: PROVISIONAL
            # Longitudinal data are not allowed yet in BFF/PXF
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

    # =========
    # ethnicity
    # =========

    $individual->{ethnicity} = map_ontology_term(
        {
            query    => $person->{race_source_value},    # not getting it from *_concept_id
            column   => 'label',
            ontology => 'ncit',

            #ontology => 'ohdsi',
            self => $self
        }
    ) if defined $person->{race_source_value};

    # =========
    # exposures
    # =========

    #          'observation_concept_id' => 37017711,
    #          'observation_date' => '1945-05-25',
    #          'observation_datetime' => '1945-05-25 00:00:00',
    #          'observation_id' => 919,
    #          'observation_source_concept_id' => 37017711,
    #          'observation_source_value' => 714035009,
    #          'observation_type_concept_id' => 38000280,
    #          'person_id' => 1476,
    #          'provider_id' => 0,
    #          'qualifier_concept_id' => 0,
    #          'qualifier_source_value' => undef,
    #          'unit_concept_id' => 0,
    #          'unit_source_value' => undef,
    #          'value_as_concept_id' => 0,
    #          'value_as_number' => '\\N',
    #          'value_as_string' => undef,
    #          'visit_detail_id' => 0,
    #          'visit_occurrence_id' => 98529

    #**************************************************
    # *** IMPORTANT ***
    # We'll only process if exist in $self->{exposures};
    #*************************************************
    #
    $table = 'OBSERVATION';

    if ( defined $participant->{$table} ) {

        for my $field ( @{ $participant->{$table} } ) {

            # Note that these changes with DEVEL_MODE affect phenotypicFeatures (also uses OBSERVATION)
            $field->{observation_concept_id} = 35609831
              if DEVEL_MODE;    # Note that it affects
                                #$field->{value_as_number} = 10 if DEVEL_MODE;

            # NB: Values in key hashes are stringfied so make a copy to keep them as integer
            my $field_observation_concept_id = $field->{observation_concept_id};
            next
              unless exists $self->{exposures}{$field_observation_concept_id};
            my $exposure;

            $exposure->{ageAtExposure} = {
                age => {
                    iso8601duration => find_age(

                        {

                            date      => $field->{observation_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }

            };

            $exposure->{date}     = $field->{observation_date};
            $exposure->{duration} = $DEFAULT->{duration_OMOP};

            # _info
            $exposure->{_info}{$table}{OMOP_columns} = $field;

            $exposure->{exposureCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{observation_concept_id},
                    self       => $self
                }
            ) if defined $field->{observation_concept_id};

          my $unit = $field->{unit_concept_id} ? map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{unit_concept_id},
                    self       => $self

                }
            ) : $DEFAULT->{ontology_term};

            $exposure->{unit} = $unit;
            $exposure->{value} =
              $field->{value_as_number} eq '\\N'
              ? -1
              : $field->{value_as_number} + 0;

            # NB: We do not include _visit in exposures

            push @{ $individual->{exposures} }, $exposure;
        }
    }

    # ================
    # geographicOrigin
    # ================

    $individual->{geographicOrigin} = map_ontology_term(
        {
            query    => $person->{ethnicity_source_value},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }
    ) if defined $person->{ethnicity_source_value};

    # ==
    # id
    # ==

    $individual->{id} = $person->{person_id};

    # Forcing string w/o changing orig ref ($person)
    $individual->{id} = qq/$individual->{id}/;

    # ====
    # info
    # ====

    $table = 'PERSON';

    # Table PERSON
    #     1	birth_datetime
    #     2	care_site_id
    #     3	day_of_birth
    #     4	ethnicity_concept_id
    #     5	ethnicity_source_concept_id
    #     6	ethnicity_source_value
    #     7	gender_concept_id
    #     8	gender_source_concept_id
    #     9	gender_source_value
    #    10	location_id
    #    11	month_of_birth
    #    12	person_id
    #    13	person_source_value
    #    14	provider_id
    #    15	race_concept_id
    #    16	race_source_concept_id
    #    17	race_source_value
    #    18	year_of_birth

    # info (Autovivification)
    $individual->{info}{$table}{OMOP_columns} = $person;

    # Hard-coded $individual->{info}{dateOfBirth}
    $individual->{info}{dateOfBirth} =
      _map2iso8601( $person->{birth_datetime} );

    # When we use --test we do not serialize changing (metaData) information
    unless ( $self->{test} ) {
        $individual->{info}{metaData}     = $self->{metaData};
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }

    # =========================
    # interventionsOrProcedures
    # =========================

    $table = 'PROCEDURE_OCCURRENCE';

    #      1	modifier_concept_id
    #      2	modifier_source_value
    #      3	person_id
    #      4	procedure_concept_id
    #      5	procedure_date
    #      6	procedure_datetime
    #      7	procedure_occurrence_id
    #      8	procedure_source_concept_id
    #      9	procedure_source_value
    #     10	procedure_type_concept_id
    #     11	provider_id
    #     12	quantity
    #     13	visit_detail_id
    #     14	visit_occurrence_id

    if ( defined $participant->{$table} ) {

        $individual->{interventionsOrProcedures} = [];

        for my $field ( @{ $participant->{$table} } ) {
            my $intervention;

            $intervention->{ageAtProcedure} = {
                age => {

                    iso8601duration => find_age(

                        #_birth_datetime => $person->{birth_datetime}, # Property not allowed
                        #_procedure_date => $field->{procedure_date},  # Property not allowed
                        {

                            date      => $field->{procedure_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            #$intervention->{bodySite} = undef;
            $intervention->{dateOfProcedure} = $field->{procedure_date};

            # _info (Autovivification)
            $intervention->{_info}{$table}{OMOP_columns} = $field;
            $intervention->{procedureCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{procedure_concept_id},
                    self       => $self

                }
            ) if defined $field->{procedure_concept_id};

            push @{ $individual->{interventionsOrProcedures} }, $intervention;
        }
    }

    # =============
    # karyotypicSex
    # =============

    # $individual->{karyotypicSex} = undef;

    # ========
    # measures
    # ========

    $table = 'MEASUREMENT';

    #      1	measurement_concept_id
    #      2	measurement_date
    #      3	measurement_datetime
    #      4	measurement_id
    #      5	measurement_source_concept_id
    #      6	measurement_source_value
    #      7	measurement_time
    #      8	measurement_type_concept_id
    #      9	operator_concept_id
    #     10	person_id
    #     11	provider_id
    #     12	range_high
    #     13	range_low
    #     14	unit_concept_id
    #     15	unit_source_value
    #     16	value_as_concept_id
    #     17	value_as_number
    #     18	value_source_value
    #     19	visit_detail_id
    #     20	visit_occurrence_id

    # Examples:

    #  "measurement_concept_id" : 3006322,
    #  "measurement_date" : "1943-02-03",
    #  "measurement_datetime" : "1943-02-03 00:00:00",
    #  "measurement_id" : 9852,
    #  "measurement_source_concept_id" : 3006322,
    #  "measurement_source_value" : "8331-1",
    #  "measurement_time" : "1943-02-03",
    #  "measurement_type_concept_id" : 5001,
    #  "operator_concept_id" : 0,
    #  "person_id" : 929,
    #  "provider_id" : 0,
    #  "range_high" : "\\N",
    #  "range_low" : "\\N",
    #  "unit_concept_id" : 0,
    #  "unit_source_value" : null,
    #  "value_as_concept_id" : 0,
    #  "value_as_number" : "\\N",
    #  "value_source_value" : null,
    #  "visit_detail_id" : 0,
    #  "visit_occurrence_id" : 61837

    if ( defined $participant->{$table} ) {

        for my $field ( @{ $participant->{$table} } ) {

            # FAKE VALUES FOR DEBUG
            $field->{unit_concept_id}     = 18753   if DEVEL_MODE;
            $field->{value_as_number}     = 20      if DEVEL_MODE;
            $field->{operator_concept_id} = 4172756 if DEVEL_MODE;
            $field->{measurement_type_concept_id} = 4024958 if DEVEL_MODE; 
            $field->{value_as_concept_id} = 18753 if DEVEL_MODE;

            my $measure;

            if ( $field->{measurement_concept_id} ) {    # != 0
                $measure->{assayCode} = map2ohdsi(
                    {
                        ohdsi_dict => $ohdsi_dict,
                        concept_id => $field->{measurement_concept_id},
                        self       => $self
                    }
                );
            }

            # Set default and move on
            else {
                $measure = set_default_measure();
                next;
            }

            $measure->{date} = $field->{measurement_date};

            my $unit = $field->{unit_concept_id} ? map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{unit_concept_id},
                    self       => $self

                }
            ) : $DEFAULT->{ontology_term};

            # *** IMPORTANT ***
            # We can get value_as_concept_id or as value_as_number
            # NB: EUNOMIA always -- $field->{value_as_concept_id} = 0;

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

            # notes MUST be string
            # _info (Autovivification)
            $measure->{_info}{$table}{OMOP_columns} = $field;
            $measure->{observationMoment} = {
                age => {
                    iso8601duration => find_age(
                        {
                            date      => $field->{measurement_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            $measure->{procedure}{procedureCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{measurement_type_concept_id},
                    self       => $self

                }
            );

            # NB: PROVISIONAL
            # Longitudinal data are not allowed yet in BFF/PXF
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

    # =========
    # pedigrees
    # =========

    # ==================
    # phenotypicFeatures
    # ==================

    $table = 'OBSERVATION';

    #          'observation_concept_id' => 37017711,
    #          'observation_date' => '1945-05-25',
    #          'observation_datetime' => '1945-05-25 00:00:00',
    #          'observation_id' => 919,
    #          'observation_source_concept_id' => 37017711,
    #          'observation_source_value' => 714035009,
    #          'observation_type_concept_id' => 38000280,
    #          'person_id' => 1476,
    #          'provider_id' => 0,
    #          'qualifier_concept_id' => 0,
    #          'qualifier_source_value' => undef,
    #          'unit_concept_id' => 0,
    #          'unit_source_value' => undef,
    #          'value_as_concept_id' => 0,
    #          'value_as_number' => '\\N',
    #          'value_as_string' => undef,
    #          'visit_detail_id' => 0,
    #          'visit_occurrence_id' => 98529

    # *** IMPORTANT ***
    # We'll only process if not exist in $self->{exposures};

    if ( defined $participant->{$table} ) {

        $individual->{phenotypicFeatures} = [];

        for my $field ( @{ $participant->{$table} } ) {

            # NB: Values in key hashes are stringfied so make a copy to keep them as integer
            my $field_observation_concept_id = $field->{observation_concept_id};
            next
              if exists $self->{exposures}{$field_observation_concept_id};

            my $phenotypicFeature;

            #$phenotypicFeature->{evidence} = undef;
            #$phenotypicFeature->{excluded} = undef;
            $phenotypicFeature->{featureType} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{observation_concept_id},
                    self       => $self

                }
            ) if defined $field->{observation_concept_id};

            #$phenotypicFeature->{modifiers} = undef;

            # notes MUST be string
            # _info (Autovivification)
            $phenotypicFeature->{_info}{$table}{OMOP_columns} = $field;

            $phenotypicFeature->{onset} = {

                #_birth_datetime   => $person->{birth_datetime}, # property not allowed
                #_observation_date => $field->{observation_date}, # property not allowed

                iso8601duration => find_age(
                    {

                        date      => $field->{observation_date},
                        birth_day => $person->{birth_datetime}
                    }
                )
            };

            #$phenotypicFeature->{resolution} = undef;
            #$phenotypicFeature->{severity} = undef;

            # NB: PROVISIONAL
            # Longitudinal data are not allowed yet in BFF/PXF
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

    # ===
    # sex
    # ===

    # OHSDI CONCEPT.vocabulary_id = Gender (i.e., ad hoc)
    my $sex = map2ohdsi(
        {
            ohdsi_dict => $ohdsi_dict,
            concept_id => $person->{gender_concept_id},
            self       => $self
        }
    );

    # $sex = {id, label), we need to use 'label'
    $individual->{sex} = map_ontology_term(
        {
            query    => $sex->{label},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }

    ) if $sex;

    # ==========
    # treatments
    # ==========

    $table = 'DRUG_EXPOSURE';

    #      1	days_supply
    #      2	dose_unit_source_value
    #      3	drug_concept_id
    #      4	drug_exposure_end_date
    #      5	drug_exposure_end_datetime
    #      6	drug_exposure_id
    #      7	drug_exposure_start_date
    #      8	drug_exposure_start_datetime
    #      9	drug_source_concept_id
    #     10	drug_source_value
    #     11	drug_type_concept_id
    #     12	lot_number
    #     13	person_id
    #     14	provider_id
    #     15	quantity
    #     16	refills
    #     17	route_concept_id
    #     18	route_source_value
    #     19	sig
    #     20	stop_reason
    #     21	verbatim_end_date
    #     22	visit_detail_id
    #     23	visit_occurrence_id

    # Example:

    #            'days_supply' => 35,
    #            'dose_unit_source_value' => undef,
    #            'drug_concept_id' => 19078461,
    #            'drug_exposure_end_date' => '2014-11-19',
    #            'drug_exposure_end_datetime' => '2014-11-19 00:00:00',
    #            'drug_exposure_id' => 9656,
    #            'drug_exposure_start_date' => '2014-10-15',
    #            'drug_exposure_start_datetime' => '2014-10-15 00:00:00',
    #            'drug_source_concept_id' => 19078461,
    #            'drug_source_value' => 310965,
    #            'drug_type_concept_id' => 38000177,
    #            'lot_number' => 0,
    #            'person_id' => 807,
    #            'provider_id' => 0,
    #            'quantity' => 0,
    #            'refills' => 0,
    #            'route_concept_id' => 0,
    #            'route_source_value' => undef,
    #            'sig' => undef,
    #            'stop_reason' => undef,
    #            'verbatim_end_date' => '2014-11-19',
    #            'visit_detail_id' => 0,
    #            'visit_occurrence_id' => 53547
    #          },

    if ( defined $participant->{$table} ) {

        $individual->{treatments} = [];

        for my $field ( @{ $participant->{$table} } ) {
            my $treatment;

            $treatment->{ageAtOnset} = {
                age => {

                    # _birth_datetime               => $person->{birth_datetime}, # property not allowed
                    # _drug_exposure_start_datetime => $field->{drug_exposure_start_date},
                    iso8601duration => find_age(
                        {
                            date      => $field->{drug_exposure_start_date},
                            birth_day => $person->{birth_datetime}
                        }
                    )
                }
            };

            #$treatment->{cumulativeDose} = undef;
            $treatment->{doseIntervals} = [];

            # #[{
            #    #_days_supply => $field->{days_supply}, # Property not allowed
            #    interval     => {
            #        start => $field->{drug_exposure_start_date},
            #        end   => $field->{drug_exposure_end_date}
            #    },
            #     quantity => {},
            #     scheduleFrequency => {}
            #}];

            # _info (Autovivification)
            $treatment->{_info}{$table}{OMOP_columns} = $field;

            $treatment->{routeOfAdministration} =
              { id => "NCIT:NA0000", label => "Fake" };
            $treatment->{treatmentCode} = map2ohdsi(
                {
                    ohdsi_dict => $ohdsi_dict,
                    concept_id => $field->{drug_concept_id},
                    self       => $self
                }
            ) if defined $field->{drug_concept_id};

            # NB: PROVISIONAL
            # Longitudinal data are not allowed yet in BFF/PXF
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

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return ( $self->{stream} && avoid_seen_individuals($individual) )
      ? undef
      : $individual;
}

sub avoid_seen_individuals {

    my $individual = shift;
    my $id         = $individual->{id};

    # Generate a standardized key for each individual based on id, info, and sex
    my $expected_keys   = join( '_', sort qw(id info sex) );
    my $individual_keys = join( '_', sort keys %$individual );
    my $key             = $id . '_' . $individual_keys;

    # Compare the individual's keys with the expected keys
    if ( $individual_keys eq $expected_keys ) {
        if ( exists $seen_individual{$key} ) {

            #say "Duplicate <$key> for $id";
            return 1;    # Duplicate found
        }
        else {
            $seen_individual{$key} = 1;
            return 0;    # No duplicate, individual added to the tracking hash
        }
    }
    return 0;            # The individual does not match the expected keys and is treated as non-duplicate
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
