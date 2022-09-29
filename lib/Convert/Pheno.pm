package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature               qw(say);
use Carp qw(confess);
use FindBin               qw($Bin);
use Data::Dumper;
use JSON::XS;
use Path::Tiny;
use File::Basename;
use Sys::Hostname;
use Cwd             qw(cwd abs_path);
use List::Util qw(any);
use Convert::Pheno::CSV;
use Convert::Pheno::IO;
use Convert::Pheno::SQLite;
use Convert::Pheno::Mapping;
use Exporter 'import';
our @EXPORT = qw($VERSION write_json write_yaml $omop_version $omop_main_table); # Symbols imported by default
#our @EXPORT_OK = qw(write_json write_yaml);       # Symbols imported by request

use constant DEVEL_MODE => 0;

# Global variables:
our $VERSION = '0.0.0b';
my $omop_version    = 'v5.4';
my $omop_main_table = {
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

my @omop_extra_tables = qw(
  CDM_SOURCE
  CONCEPT_ANCESTOR
  CONCEPT
  CONCEPT_RELATIONSHIP
  CONCEPT_SYNONYM
  CONDITION_ERA
  DOMAIN
  OBSERVATION_PERIOD
  VOCABULARY
);

# Constructor method
sub new {

    my ( $class, $self ) = @_;
    bless $self, $class;
    return $self;
}

# NB1: In general, we'll only display terms that exist and have content
# NB2: Using pure OO Perl but we may switch to others (e.g., Moose) if things get trickier...

#############
#############
#  PXF2BFF  #
#############
#############

sub pxf2bff {

    # <array_dispatcher> will deal with JSON arrays
    return array_dispatcher(shift);
}

sub do_pxf2bff {

    my ( $self, $data ) = @_;
    my $sth = $self->{sth};

    # Get cursors for 1D terms
    my $interpretation = $data->{interpretation};
    my $phenopacket    = $data->{phenopacket};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # NB: In PXF some terms are = []
    my $individual;

    # ========
    # diseases
    # ========

    $individual->{diseases} =
      [ map { $_ = { diseaseCode => $_->{term} } }
          @{ $phenopacket->{diseases} } ]
      if exists $phenopacket->{diseases};

    # ==
    # id
    # ==

    $individual->{id} = $phenopacket->{subject}{id}
      if exists $phenopacket->{subject}{id};

    # ====
    # info
    # ====

    # **** $data->{phenopacket} ****
    $individual->{info}{phenopacket}{dateOfBirth} =
      $phenopacket->{subject}{dateOfBirth};

    # CNAG files have 'meta_data' nomenclature, but PHX documentation uses 'metaData'
    # We search for both 'meta_data' and 'metaData' and leave them untouched
    for my $term (qw (dateOfBirth genes meta_data metaData variants)) {
        $individual->{info}{phenopacket}{$term} = $phenopacket->{$term}
          if exists $phenopacket->{$term};
    }

    # **** $data->{interpretation} ****
    for my $term (qw (meta_data metaData)) {
        $individual->{info}{interpretation}{phenopacket}{$term} =
          $interpretation->{phenopacket}{$term}
          if $interpretation->{phenopacket}{$term};
    }

    # <diseases> and <phenotypicFeatures> are identical to those of $data->{phenopacket}{diseases,phenotypicFeatures}
    for my $term (
        qw (diagnosis diseases resolutionStatus phenotypicFeatures genes variants)
      )
    {
        $individual->{info}{interpretation}{$term} = $interpretation->{$term}
          if exists $interpretation->{$term};
    }

    # ==================
    # phenotypicFeatures
    # ==================

    $individual->{phenotypicFeatures} = [
        map {
            $_ = {
                "excluded" => (
                    exists $_->{negated} ? JSON::XS::true : JSON::XS::false
                ),
                "featureType" => $_->{type}
            }
        } @{ $phenopacket->{phenotypicFeatures} }
      ]
      if exists $phenopacket->{phenotypicFeatures};

    # ===
    # sex
    # ===

    $individual->{sex} = map_ontology(
        {
            query    => $phenopacket->{subject}{sex},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }
      )
      if ( exists $phenopacket->{subject}{sex}
        && $phenopacket->{subject}{sex} ne '' );

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    # print Dumper $individual;
    return $individual;
}

#############
#############
#  BFF2PXF  #
#############
#############

sub bff2pxf {

    # <array_dispatcher> will deal with JSON arrays
    return array_dispatcher(shift);
}

sub do_bff2pxf {

    my ( $self, $data ) = @_;

    # Premature return
    return unless defined($data);

    #########################################
    # START MAPPING TO PHENOPACKET V2 TERMS #
    #########################################

    # We need to shuffle a bit some Beacon v2 properties to be Phenopacket compliant
    # https://phenopacket-schema.readthedocs.io/en/latest/phenopacket.html
    my $pxf;

    # ==
    # id
    # ==

    $pxf->{id} = 'phenopacket_id.' . randStr(8);

    # =======
    # subject
    # =======

    $pxf->{subject} = {
        id  => $data->{id},
        sex => uc( $data->{sex}{label} ),
        age => $data->{info}{age}
    };

    # ===================
    # phenotypic_features
    # ===================

    $pxf->{phenotypicFeatures} = [
        map {
            {
                type => $_->{featureType}

                  #_notes => $_->{notes}
            }
        } @{ $data->{phenotypicFeatures} }
      ]
      if defined $data->{phenotypicFeatures};

    # ============
    # measurements
    # ============

    $pxf->{measurements} = [
        map {
            {
                assay        => $_->{assayCode},
                timeObserved => exists $_->{date} ? $_->{date} : undef,
                value        => $_->{measurementValue}
            }
        } @{ $data->{measures} }
    ] if defined $data->{measures};    # Only 1 element at $_->{measurementValue}

    # ==========
    # biosamples
    # ==========

    # ===============
    # interpretations
    # ===============

    #$data->{interpretation} = {};

    # ========
    # diseases
    # ========

    $pxf->{diseases} =
      [ map { { term => $_->{diseaseCode}, onset => $_->{ageOfOnset} } }
          @{ $data->{diseases} } ];

    # ===============
    # medical_actions
    # ===============

    # **** procedures ****
    my @procedures = map {
        {
            procedure => {
                code      => $_->{procedureCode},
                performed => {
                    timestamp => exists $_->{dateOfProcedure}
                    ? _map2iso8601( $_->{dateOfProcedure} )
                    : undef
                }
            }
        }
    } @{ $data->{interventionsOrProcedures} };

    # **** treatments ****
    my @treatments = map {
        {
            treatment => {
                agent                 => $_->{treatmentCode},
                routeOfAdministration => $_->{routeOfAdministration},
                doseIntervals         => $_->{doseIntervals}

                  #performed => { timestamp => exists $_->{dateOfProcedure} ? $_->{dateOfProcedure} : undef}
            }
        }
    } @{ $data->{treatments} };

    # Load
    push @{ $pxf->{medicalActions} }, @procedures if @procedures;
    push @{ $pxf->{medicalActions} }, @treatments if @treatments;

    # =====
    # files
    # =====

    # =========
    # meta_data
    # =========

    # Depending on the origion (redcap) , _info and resources may exist
    $pxf->{metaData} =
      exists $data->{info}{metaData}
      ? $data->{info}{metaData}
      : get_metaData();

    #######################################
    # END MAPPING TO PHENOPACKET V2 TERMS #
    #######################################

    return $pxf;
}

################
################
#  REDCAP2BFF  #
################
################

sub redcap2bff {

    my $self = shift;

    # Read and load data from REDCap export
    my $data = read_csv_export( { in => $self->{in_file}, sep => undef } );

    # $data = [
    #       {
    #         'abdominal_mass' => '0',
    #         'abdominal_pain' => '1',
    #         'age' => '2',
    #         'age_first_diagnosis' => '0',
    #         'alcohol' => '4',
    #        }, {},,,
    #        ]

    # Read and load REDCap CSV dictionary
    my $data_redcap_dic = read_redcap_dictionary( $self->{redcap_dictionary} );

    print Dumper $data_redcap_dic if ( $self->{debug} && $self->{debug} > 1 );

    $self->{data}            = $data;               # Dynamically adding attributes (setter)
    $self->{data_redcap_dic} = $data_redcap_dic;    # Dynamically adding attributes (setter)

    # array_dispatcher will deal with JSON arrays
    return array_dispatcher($self);
}

sub do_redcap2bff {

    my ( $self, $participant ) = @_;
    my $redcap_dic = $self->{data_redcap_dic};
    my $sth        = $self->{sth};

    ##############################
    # <Variable> names in REDCap #
    ##############################
    #
    # REDCap does not enforce any particular "Variable" name.
    # Extracted from https://www.ctsi.ufl.edu/wordpress/files/2019/02/Project-Creation-User-Guide.pdf
    # ---
    # "Variable Names: Variable names are critical in the data analysis process. If you export your data to a
    # statistical software program, the variable names are what you or your statistician will use to conduct
    # the analysis"
    #
    # "We always recommend reviewing your variable names with a statistician or whoever will be
    # analyzing your data. This is especially important if this is the first time you are building a
    # database"
    #---
    # If "Variable" names are not consensuated, then we need to do the mapping manually "a posteriori".
    # This is what we are attempting here:

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # $participant =
    #       {
    #         'abdominal_mass' => '0',
    #         'abdominal_pain' => '1',
    #         'age' => '2',
    #         'age_first_diagnosis' => '0',
    #         'alcohol' => '4',
    #        }

    print Dumper $redcap_dic  if $self->{debug};
    print Dumper $participant if $self->{debug};

    # ABOUT REQUIRED PROPERTIES
    # 'id' and 'sex' are required properties in <individuals> entry type
    # Premature return
    return
      unless (
        (
            exists $participant->{ids_complete}
            && $participant->{ids_complete} ne ''
        )
        && ( exists $participant->{sex} && $participant->{sex} ne '' )
      );

    # Data structure (hashref) for each individual
    my $individual;

    # ========
    # diseases
    # ========

    $individual->{diseases} = [];

    #my %disease = ( 'Inflamatory Bowel Disease' => 'ICD10:K51.90' ); # it does not exist as it is at ICD10
    #my @diseases = ('Unspecified asthma, uncomplicated', 'Inflamatory Bowel Disease', "Crohn's disease, unspecified, without complications");
    my @diseases = ('Inflammatory Bowel Disease');    # Note the 2 mm
    for my $field (@diseases) {
        my $disease;

        $disease->{ageOfOnset} = map_age_range(
            map2redcap_dic(
                {
                    redcap_dic  => $redcap_dic,
                    participant => $participant,
                    field       => 'age_first_diagnosis'
                }
            )
        ) if $participant->{age_first_diagnosis} ne '';
        $disease->{diseaseCode} = map_ontology(
            {
                query  => $field,
                column => 'label',

                #ontology       => 'icd10',                        # ICD:10 Inflammatory Bowel Disease does not exist
                ontology => 'ncit',
                self     => $self
            }
        );
        $disease->{familyHistory} = convert2boolean(
            map2redcap_dic(
                {
                    redcap_dic  => $redcap_dic,
                    participant => $participant,
                    field       => 'family_history'
                }
            )
        ) if $participant->{family_history} ne '';

        #$disease->{notes}    = undef;
        $disease->{severity} = { id => 'NCIT:NA000', label => 'NA' };
        $disease->{stage}    = { id => 'NCIT:NA000', label => 'NA' };

        push @{ $individual->{diseases} }, $disease
          if defined $disease->{diseaseCode};
    }

    # =========
    # ethnicity
    # =========

    $individual->{ethnicity} = map_ethnicity(
        map2redcap_dic(
            {
                redcap_dic  => $redcap_dic,
                participant => $participant,
                field       => 'ethnicity'
            }
        )
    ) if $participant->{ethnicity} ne '';

    # =========
    # exposures
    # =========

    $individual->{exposures} = [];
    my @exposures = (
        qw (alcohol smoking cigarettes_days cigarettes_years packyears smoking_quit)
    );

    for my $field (@exposures) {
        next if $participant->{$field} eq '';
        my $exposure;

        $exposure->{ageAtExposure} = { id => 'NCIT:NA0000', label => 'NA' };
        $exposure->{date}          = '1900-01-01';
        $exposure->{duration}      = 'P999Y';
        $exposure->{exposureCode}  = map_ontology(
            {
                query    => $field,
                column   => 'label',
                ontology => 'ncit',
                self     => $self
            }
        );

        # We first extract 'unit' that supposedly will be used in <measurementValue> and <referenceRange>??
        my $unit = map_ontology(
            {
                query => ( $field eq 'alcohol' || $field eq 'smoking' )
                ? map_exposures(
                    {
                        key => $field,
                        str => map2redcap_dic(
                            {
                                redcap_dic  => $redcap_dic,
                                participant => $participant,
                                field       => $field
                            }
                        )
                    }
                  )
                : $field,
                column   => 'label',
                ontology => 'ncit',
                self     => $self
            }
        );
        $exposure->{unit}  = $unit;
        $exposure->{value} = dotify_and_coerce_number( $participant->{$field} );
        push @{ $individual->{exposures} }, $exposure
          if defined $exposure->{exposureCode};
    }

    # ================
    # geographicOrigin
    # ================

    #$individual->{geographicOrigin} = {};

    # ==
    # id
    # ==

    $individual->{id} = $participant->{ids_complete};

    # ====
    # info
    # ====

    my @fields =
      qw(study_id dob diet redcap_event_name age first_name last_name consent consent_date consent_noneu consent_devices consent_recontact consent_week2_endo education zipcode consents_and_demographics_complete);
    for my $field (@fields) {
        $individual->{info}{$field} =
          $field eq 'age'
          ? { iso8601duration => 'P' . $participant->{$field} . 'Y' }
          : ( any { /^$field$/ } qw(education diet) ) ? map2redcap_dic(
            {
                redcap_dic  => $redcap_dic,
                participant => $participant,
                field       => $field
            }
          )
          : $field =~ m/^consent/ ? {
            value => dotify_and_coerce_number( $participant->{$field} ),
            map { $_ => $redcap_dic->{$field}{$_} }
              ( "Field Label", "Field Note", "Field Type" )
          }
          : $participant->{$field}
          if $participant->{$field} ne '';
    }
    $individual->{info}{metaData} = get_metaData();

    # =========================
    # interventionsOrProcedures
    # =========================

    $individual->{interventionsOrProcedures} = [];

    #my @surgeries = map { $_ = 'surgery_details___' . $_ } ( 1 .. 8, 99 );
    my %surgery = ();
    for ( 1 .. 8, 99 ) {
        $surgery{ 'surgery_details___' . $_ } =
          $redcap_dic->{surgery_details}{_labels}{$_};
    }
    for my $field (
        qw(endoscopy_performed intestinal_surgery partial_mayo complete_mayo prev_endosc_dilatation),
        keys %surgery
      )
    {
        if ( $participant->{$field} ) {
            my $intervention;

            #$intervention->{ageAtProcedure} = undef;
            $intervention->{bodySite} =
              { id => 'NCIT:C12736', label => 'intestine' };
            $intervention->{dateOfProcedure} =
                $field eq 'endoscopy_performed'
              ? $participant->{endoscopy_date}
              : '1900-01-01';
            $intervention->{procedureCode} = map_ontology(
                {
                    query    => $surgery{$field},
                    column   => 'label',
                    ontology => 'ncit',
                    self     => $self
                }
            ) if ( exists $surgery{$field} && $surgery{$field} ne '' );
            push @{ $individual->{interventionsOrProcedures} }, $intervention
              if defined $intervention->{procedureCode};
        }
    }

    # =============
    # karyotypicSex
    # =============

    # $individual->{karyotypicSex} = undef;

    # ========
    # measures
    # ========

    $individual->{measures} = [];

    # lab_remarks was removed
    my @measures = (
        qw (leucocytes hemoglobin hematokrit mcv mhc thrombocytes neutrophils lymphocytes eosinophils creatinine gfr bilirubin gpt ggt lipase crp iron il6 calprotectin)
    );
    my @indexes =
      qw (nancy_index_acute  nancy_index_chronic nancy_index_ulceration);
    my @others = qw(endo_mayo);

    for my $field ( @measures, @indexes, @others ) {
        next if $participant->{$field} eq '';
        my $measure;

        $measure->{assayCode} = map_ontology(
            {
                query    => $field,
                column   => 'label',
                ontology => 'ncit',
                self     => $self,
            }
        );
        $measure->{date} = '1900-01-01';

        # We first extract 'unit' and %range' for <measurementValue>
        my $unit = map_ontology(
            {
                query    => map_quantity( $redcap_dic->{$field}{'Field Note'} ),
                column   => 'label',
                ontology => 'ncit',
                self     => $self
            }
        );
        $measure->{measurementValue} = {
            quantity => {
                unit  => $unit,
                value => dotify_and_coerce_number( $participant->{$field} ),
                referenceRange => map_unit_range(
                    { redcap_dic => $redcap_dic, field => $field }
                )
            }
        };
        $measure->{notes} =
          "$field, Field Label=$redcap_dic->{$field}{'Field Label'}";

        #$measure->{observationMoment} = undef;          # Age
        $measure->{procedure} = {
            procedureCode => map_ontology(
                {
                      query => $field eq 'calprotectin' ? 'Feces'
                    : $field =~ m/^nancy/ ? 'Histologic'
                    : 'Blood Test Result',
                    column   => 'label',
                    ontology => 'ncit',
                    self     => $self
                }
            )
        };

        # Add to array
        push @{ $individual->{measures} }, $measure
          if defined $measure->{assayCode};
    }

    # =========
    # pedigrees
    # =========

    $individual->{pedigrees} = [];

    # disease, id, members, numSubjects
    my @pedigrees = (qw ( x y ));
    for my $field (@pedigrees) {

        my $pedigree;
        $pedigree->{disease}     = {};      # P32Y6M1D
        $pedigree->{id}          = undef;
        $pedigree->{members}     = [];
        $pedigree->{numSubjects} = 0;

        # Add to array
        #push @{ $individual->{pedigrees} }, $pedigree; # SWITCHED OFF on 072622

    }

    # ==================
    # phenotypicFeatures
    # ==================

    $individual->{phenotypicFeatures} = [];
    my @comorbidities =
      qw ( comorb_asthma comorb_copd comorb_ms comorb_sle comorb_ra comorb_pso comorb_ad comorb_cancer comorb_cancer_specified comorb_hypertension comorb_diabetes comorb_lipids comorb_stroke comorb_other_ai comorb_other_ai_specified);
    my @phenotypicFeatures = qw(immunodeficiency rectal_bleeding);

    for my $field ( @comorbidities, @phenotypicFeatures ) {
        my $phenotypicFeature;

        if ( $participant->{$field} ne '' && $participant->{$field} == 1 ) {

            #$phenotypicFeature->{evidence} = undef;    # P32Y6M1D
            #$phenotypicFeature->{excluded} =
            #  { quantity => { unit => { id => '', label => '' }, value => undef } };
            $phenotypicFeature->{featureType} = map_ontology(
                {
                    query    => $field =~ m/comorb/ ? 'Comorbidity' : $field,
                    column   => 'label',
                    ontology => 'ncit',
                    self     => $self

                }
            );

            #$phenotypicFeature->{modifiers}   = { id => '', label => '' };
            $phenotypicFeature->{notes} =
              "$field, Field Label=$redcap_dic->{$field}{'Field Label'}";

            #$phenotypicFeature->{onset}       = { id => '', label => '' };
            #$phenotypicFeature->{resolution}  = { id => '', label => '' };
            #$phenotypicFeature->{severity}    = { id => '', label => '' };

            # Add to array
            push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature
              if defined $phenotypicFeature->{featureType};
        }
    }

    # ===
    # sex
    # ===

    $individual->{sex} = map_ontology(
        {
            query => map2redcap_dic(
                {
                    redcap_dic  => $redcap_dic,
                    participant => $participant,
                    field       => 'sex'
                }
            ),
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }
    );

    # ==========
    # treatments
    # ==========

    $individual->{treatments} = [];

    my %drug = (
        aza => 'azathioprine',
        asa => 'aspirin',
        mtx => 'methotrexate',
        mp  => 'mercaptopurine'
    );

    my @drugs  = qw (budesonide prednisolone asa aza mtx mp);
    my @routes = qw (oral rectal);

    #        '_labels' => {
    #                                                       '1' => 'never treated',
    #                                                       '2' => 'former treatment',
    #                                                       '3' => 'current treatment'
    #                                                     }

    # FOR DRUGS
    for my $drug (@drugs) {

        # Getting the right name for the drug (if any)
        my $drug_name = exists $drug{$drug} ? $drug{$drug} : $drug;

        # FOR ROUTES
        for my $route (@routes) {

            # Rectal route only happens in some drugs (ad hoc)
            next
              if ( $route eq 'rectal' && !any { /^$drug$/ }
                qw(budesonide asa) );

            # Discarding if drug_route_status is empty
            my $tmp_var =
              ( $drug eq 'budesonide' || $drug eq 'asa' )
              ? $drug . '_' . $route . '_status'
              : $drug . '_status';
            next if $participant->{$tmp_var} eq '';

            #say "$drug $route";

            # Initialize field $treatment
            my $treatment;

            $treatment->{_info} = {
                field     => $tmp_var,
                drug      => $drug,
                drug_name => $drug_name,
                status    => map2redcap_dic(
                    {
                        redcap_dic  => $redcap_dic,
                        participant => $participant,
                        field       => $tmp_var
                    }
                ),
                route => $route,
                value => $participant->{$tmp_var},
                map { $_ => $participant->{ $drug . $_ } }
                  qw(start dose duration)
            };    # ***** INTERNAL FIELD
            $treatment->{ageAtOnset} =
              { age => { iso8601duration => "P999Y" } };
            $treatment->{cumulativeDose} =
              { unit => { id => 'NCIT:00000', label => 'NA' }, value => -1 };
            $treatment->{doseIntervals}         = [];
            $treatment->{routeOfAdministration} = map_ontology(
                {
                    query    => ucfirst($route) . ' Route of Administration',  # Oral Route of Administration
                    column   => 'label',
                    ontology => 'ncit',
                    self     => $self
                }
            );

            $treatment->{treatmentCode} = map_ontology(
                {
                    query    => $drug_name,
                    column   => 'label',
                    ontology => 'ncit',
                    self     => $self
                }
            );
            push @{ $individual->{treatments} }, $treatment
              if defined $treatment->{treatmentCode};
        }
    }

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individual;
}

################
################
#  REDCAP2PXF  #
################
################

sub redcap2pxf {

    my $self = shift;

    # First iteration: redcap2bff
    $self->{method} = 'redcap2bff';    # setter - we have to change the value of attr {method}
    my $bff = redcap2bff($self);       # array

    # Preparing for second iteration: bff2pxf
    $self->{method}      = 'bff2pxf';    # setter
    $self->{data}        = $bff;         # setter
    $self->{in_textfile} = 0;            # setter

    # Run second iteration
    return array_dispatcher($self);
}

##############
##############
#  OMOP2BFF  #
##############
##############

sub omop2bff {

    my $self = shift;

    # The idea here is that we'll load all $omop_main_table and @omop_extra_tables in $data,
    # regardless of wheter they are concepts or truly records. Dictionaries (e.g. <CONCEPT>) will be parsed latter from $data

    # Check if data comes from variable or from file
    my $data;

    # Variable
    if ( exists $self->{data} ) {
        $data = $self->{data};
    }

    # File(s)
    else {

        # Read and load data from OMOP-CDM export
        # First we need to know if we have PostgreSQL dump or a bunch of csv
        my @exts = qw(.csv .tsv .txt .sql);
        for my $file ( @{ $self->{in_files} } ) {
            my ( $table_name, undef, $ext ) = fileparse( $file, @exts );
            if ( $ext eq '.sql' ) {

                # We'll load all OMOP tables ('main' and 'extra') as long as they're not empty
                $data = read_sqldump( $file, $self );
                sqldump2csv( $data, $self->{out_dir} ) if $self->{sql2csv};
                last;
            }
            else {

                # We'll load all OMOP tables (as CSV) as long they have a match in 'main' or 'extra'
                warn "<$table_name> is not a valid table in OMOP-CDM"
                  and next
                  unless any { /^$table_name$/ }
                  ( @{ $omop_main_table->{$omop_version} },
                    @omop_extra_tables );    # global
                $data->{$table_name} =
                  read_csv_export( { in => $file, sep => $self->{sep} } );
            }
        }
    }

    #print Dumper_tidy($data);

    # Primarily with CSV, it can happen that user does not provide <CONCEPT.csv>
    confess 'We could not find table CONCEPT, maybe missing <CONCEPT.csv> ???'
      unless exists $data->{CONCEPT};

    # We  create a dictionary for $data->{CONCEPT}
    $self->{data_ohdsi_dic} = remap_ohdsi_dictionary( $data->{CONCEPT} );    # Dynamically adding attributes (setter)

    # Now we need to perform a tranformation of the data where 'person_id' is one row of data
    # NB: Transformation is due ONLY IN $omop_main_table FIELDS, the rest of the tables are not used
    $self->{data} = transpose_omop_data_structure($data);    # Dynamically adding attributes (setter)

    # array_dispatcher will deal with JSON arrays
    return array_dispatcher($self);
}

sub do_omop2bff {

    my ( $self, $participant ) = @_;

    my $ohdsi_dic = $self->{data_ohdsi_dic};
    my $sth       = $self->{sth};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################
    my $individual;

    # Get cursors for 1D terms
    my $person = $participant->{PERSON};

    # $participant = input data
    # $person = cursor to $participant->PERSON
    # $individual = output data

    # ABOUT REQUIRED PROPERTIES
    # 'id' and 'sex' are required properties in <individuals> entry type
    # 'person_id' must exist at this point otherwise it would have not been created
    # Premature return
    return
      unless ( exists $person->{gender_concept_id}
        && $person->{gender_concept_id} ne '' );

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

    if ( exists $participant->{$table} ) {

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

            $disease->{diseaseCode} = map2ohdsi_dic(
                {
                    ohdsi_dic  => $ohdsi_dic,
                    concept_id => $field->{condition_concept_id}
                }
              )
              or map_ontology(
                {
                    query    => $field->{condition_concept_id},
                    column   => 'concept_id',
                    ontology => 'ohdsi',
                    self     => $self
                }
              ) if $field->{condition_concept_id} ne '';

            #$disease->{familyHistory} = convert2boolean(
            #    map2redcap_dic(
            #        {
            #            redcap_dic  => $redcap_dic,
            #            participant => $participant,
            #            field       => 'family_history'
            #        }
            #    )
            #) if $participant->{family_history} ne '';

            # notes MUST be string
            $disease->{_info}{$table}{OMOP_columns} = $field;          # Autovivification
                                                                       #$disease->{severity} = undef;
            $disease->{stage}                       = map2ohdsi_dic(
                {
                    ohdsi_dic  => $ohdsi_dic,
                    concept_id => $field->{condition_status_concept_id}
                }
              )
              or map_ontology(
                {
                    query    => $field->{condition_status_concept_id},
                    column   => 'concept_id',
                    ontology => 'ohdsi',
                    self     => $self
                }
              ) if $field->{condition_status_concept_id} ne '';

            push @{ $individual->{diseases} }, $disease;
        }
    }

    # =========
    # ethnicity
    # =========

    $individual->{ethnicity} = map_ontology(
        {
            query    => $person->{race_source_value},
            column   => 'label',
            ontology => 'ncit',

            #ontology => 'ohdsi',
            self => $self
        }
    ) if exists $person->{race_source_value};

    # =========
    # exposures
    # =========

    #**************************************************
    # IMPORTANT
    # WE HAVEN'T FOUND TOBACCO, ALCOHOL, ETC in OMOP
    #*************************************************
    #
    #    $table = 'OBSERVATION';
    #
    #    if ( exists $participant->{$table} ) {
    #
    #        $individual->{exposures} = [];
    #
    #        for my $field ( @{ $participant->{$table} } ) {
    #            my $exposure;
    #
    #            $exposure->{ageAtExposure} = {
    #                age => find_age(
    #                    {
    #
    #                        date      => $field->{observation_date},
    #                        birth_day => $person->{birth_datetime}
    #                    }
    #                ),
    #                _birth_datetime => $person->{birth_datetime},
    #                _observation_date => $field->{observation_date}
    #            };
    #            #$exposure->{bodySite} = undef;
    #            $exposure->{date} = $field->{observation_date};
    #
    #            # _info
    #            for ( keys %{$field} ) {
    #
    #                # Autovivification
    #                $exposure->{_info}{$table}{OMOP_columns}{$_} = $field->{$_};
    #            }
    #
    #            $exposure->{exposureCode} = map2ohdsi_dic(
    #                {
    #                    ohdsi_dic  => $ohdsi_dic,
    #                    concept_id => $field->{observation_concept_id}
    #                }
    #              )
    #              or map_ontology(
    #                {
    #                    query    => $field->{observation_concept_id},
    #                    column   => 'concept_id',
    #                    ontology => 'ohdsi',
    #                    self     => $self
    #                }
    #              ) if $field->{observation_concept_id} ne '';
    #
    #            #push @{ $individual->{exposures} }, $exposure;
    #        }
    #    }

    # ================
    # geographicOrigin
    # ================

    $individual->{geographicOrigin} = map_ontology(
        {
            query    => $person->{ethnicity_source_value},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }
    ) if exists $person->{ethnicity_source_value};

    # ==
    # id
    # ==

    $individual->{id} = $person->{person_id};

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

    for (
        qw (birth_datetime care_site_id day_of_birth month_of_birth provider_id year_of_birth)
      )
    {
        # Autovivification
        $individual->{info}{$table}{OMOP_columns}{$_} = $person->{$_}
          if exists $person->{$_};
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

    if ( exists $participant->{$table} ) {

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

            # _info
            for ( keys %{$field} ) {

                # Autovivification
                $intervention->{_info}{$table}{OMOP_columns}{$_} = $field->{$_};
            }

            $intervention->{procedureCode} = map2ohdsi_dic(
                {
                    ohdsi_dic  => $ohdsi_dic,
                    concept_id => $field->{procedure_concept_id}
                }
              )
              or map_ontology(
                {
                    query    => $field->{procedure_concept_id},
                    column   => 'concept_id',
                    ontology => 'ohdsi',
                    self     => $self
                }
              ) if $field->{procedure_concept_id} ne '';

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

    #  "measurement_concept_id" : "3006322",
    #  "measurement_date" : "1943-02-03",
    #  "measurement_datetime" : "1943-02-03 00:00:00",
    #  "measurement_id" : "9852",
    #  "measurement_source_concept_id" : "3006322",
    #  "measurement_source_value" : "8331-1",
    #  "measurement_time" : "1943-02-03",
    #  "measurement_type_concept_id" : "5001",
    #  "operator_concept_id" : "0",
    #  "person_id" : "929",
    #  "provider_id" : "0",
    #  "range_high" : "\\N",
    #  "range_low" : "\\N",
    #  "unit_concept_id" : "0",
    #  "unit_source_value" : null,
    #  "value_as_concept_id" : "0",
    #  "value_as_number" : "\\N",
    #  "value_source_value" : null,
    #  "visit_detail_id" : "0",
    #  "visit_occurrence_id" : "61837"

    if ( exists $participant->{$table} ) {

        for my $field ( @{ $participant->{$table} } ) {

            # Exiting the loop if we don't have any value
            last if $field->{value_as_number} eq '\\N';
            my $measure;

            my $tmp_field = $field->{measurement_concept_id};
            $measure->{assayCode} = map2ohdsi_dic(
                {
                    ohdsi_dic  => $ohdsi_dic,
                    concept_id => $tmp_field
                }
              )
              or map_ontology(
                {
                    query    => $tmp_field,
                    column   => 'concept_id',
                    ontology => 'ohdsi',
                    self     => $self
                }
              ) if $tmp_field ne '';
            $measure->{date} = $field->{measurement_datetime};
            $measure->{measurementValue} =
                $field->{value_as_number} ne '\\N'
              ? $field->{value_as_number}
              : undef;

            # notes MUST be string
            $measure->{_info}{$table}{OMOP_columns} = $field;                  # Autovivification
                                                                               #$measure->{observationMoment}           = undef;
            $measure->{procedure}                   = $measure->{assayCode};
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

    #      1	observation_concept_id
    #      2	observation_date
    #      3	observation_datetime
    #      4	observation_id
    #      5	observation_source_concept_id
    #      6	observation_source_value
    #      7	observation_type_concept_id
    #      8	person_id
    #      9	provider_id
    #     10	qualifier_concept_id
    #     11	qualifier_source_value
    #     12	unit_concept_id
    #     13	unit_source_value
    #     14	value_as_concept_id
    #     15	value_as_number
    #     16	value_as_string
    #     17	visit_detail_id
    #     18	visit_occurrence_id

    if ( exists $participant->{$table} ) {

        $individual->{phenotypicFeatures} = [];

        for my $field ( @{ $participant->{$table} } ) {
            my $phenotypicFeature;

            #$phenotypicFeature->{evidence} = undef;
            #$phenotypicFeature->{excluded} = undef;
            $phenotypicFeature->{featureType} = map2ohdsi_dic(
                {
                    ohdsi_dic  => $ohdsi_dic,
                    concept_id => $field->{observation_concept_id}
                }
              )
              or map_ontology(
                {
                    query    => $field->{observation_concept_id},
                    column   => 'concept_id',
                    ontology => 'ohdsi',
                    self     => $self
                }
              ) if $field->{observation_concept_id} ne '';

            #$phenotypicFeature->{modifiers} = undef;

            # notes MUST be string
            for ( keys %{$field} ) {

                # Autovivification
                $phenotypicFeature->{_info}{$table}{OMOP_columns}{$_} =
                  $field->{$_};
            }

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
            push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature;
        }
    }

    # ===
    # sex
    # ===

    # OHSDI CONCEPT.vocabulary_id = Gender (i.e., ad hoc)
    my $sex = map2ohdsi_dic(
        {
            ohdsi_dic  => $ohdsi_dic,
            concept_id => $person->{gender_concept_id}
        }
      )
      or map_ontology(
        {
            query    => $person->{gender_concept_id},
            column   => 'concept_id',
            ontology => 'ohdsi',
            self     => $self
        }
      );

    # $sex = {id, label), we need to use 'label'
    $individual->{sex} = map_ontology(
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

    #            'days_supply' => '35',
    #            'dose_unit_source_value' => undef,
    #            'drug_concept_id' => '19078461',
    #            'drug_exposure_end_date' => '2014-11-19',
    #            'drug_exposure_end_datetime' => '2014-11-19 00:00:00',
    #            'drug_exposure_id' => '9656',
    #            'drug_exposure_start_date' => '2014-10-15',
    #            'drug_exposure_start_datetime' => '2014-10-15 00:00:00',
    #            'drug_source_concept_id' => '19078461',
    #            'drug_source_value' => '310965',
    #            'drug_type_concept_id' => '38000177',
    #            'lot_number' => '0',
    #            'person_id' => '807',
    #            'provider_id' => '0',
    #            'quantity' => '0',
    #            'refills' => '0',
    #            'route_concept_id' => '0',
    #            'route_source_value' => undef,
    #            'sig' => '',
    #            'stop_reason' => '',
    #            'verbatim_end_date' => '2014-11-19',
    #            'visit_detail_id' => '0',
    #            'visit_occurrence_id' => '53547'
    #          },

    if ( exists $participant->{$table} ) {

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

            # _info
            for ( keys %{$field} ) {

                # Autovivification
                $treatment->{_info}{$table}{OMOP_columns}{$_} = $field->{$_};
            }

            $treatment->{routeOfAdministration} =
              { id => "NCIT:NA0000", label => "Fake" };
            $treatment->{treatmentCode} = map2ohdsi_dic(
                {
                    ohdsi_dic  => $ohdsi_dic,
                    concept_id => $field->{drug_concept_id}
                }
              )
              or map_ontology(
                {
                    query    => $field->{drug_concept_id},
                    column   => 'concept_id',
                    ontology => 'ohdsi',
                    self     => $self
                }
              ) if $field->{drug_concept_id} ne '';

            push @{ $individual->{treatments} }, $treatment;
        }
    }

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individual;
}

##############
##############
#  OMOP2PXF  #
##############
##############

sub omop2pxf {

    my $self = shift;

    # First iteration: omop2bff
    $self->{method} = 'omop2bff';    # setter - we have to change the value of attr {method}
    my $bff = omop2bff($self);       # array

    # Preparing for second iteration: bff2pxf
    # NB: This 2nd round may take a while if #inviduals > 1000!!!
    $self->{method}      = 'bff2pxf';    # setter
    $self->{data}        = $bff;         # setter
    $self->{in_textfile} = 0;            # setter

    # Run second iteration
    return array_dispatcher($self);
}


######################
######################
#  MISCELLANEA SUBS  #
######################
######################

sub array_dispatcher {

    my $self = shift;

    # Load the input data as Perl data structure
    my $in_data =
      ( $self->{in_textfile} && $self->{method} !~ m/^redcap2|^omop2/ )
      ? read_json( $self->{in_file} )
      : $self->{data};

    # Define the methods to call (naming 'func' to avoid confussion with $self->{method})
    my %func = (
        pxf2bff    => \&do_pxf2bff,
        redcap2bff => \&do_redcap2bff,
        omop2bff   => \&do_omop2bff,
        bff2pxf    => \&do_bff2pxf
    );

    # Open connection to SQLlite databases ONCE
    open_connections_SQLite($self) if $self->{method} ne 'bff2pxf';

    # Proceed depending if we have an ARRAY or not
    my $out_data;
    if ( ref $in_data eq ref [] ) {
        say "$self->{method}: ARRAY" if $self->{debug};

        # Caution with the RAM (we store all in memory)
        my $counter = 0;
        for ( @{$in_data} ) {
            say "[$counter] ARRAY ELEMENT" if $self->{debug};
            $counter++;

            # In $self->{data} we have all participants data, but,
            # WE DELIBERATELY SEPARATE ARRAY ELEMENTS FROM $self->{data}

            # NB: If we get "null" participants the validator will complain
            # about not having "id" or any other required property
            my $method_result = $func{ $self->{method} }->( $self, $_ );    # Method
            push @{$out_data}, $method_result if $method_result;
        }
    }
    else {
        say "$self->{method}: NOT ARRAY" if $self->{debug};
        $out_data = $func{ $self->{method} }->( $self, $in_data );          # Method
    }

    # Close connections ONCE
    close_connections_SQLite($self) unless $self->{method} eq 'bff2pxf';

    return $out_data;
}

sub get_metaData {

    # Setting a few variables
    my $user = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
    chomp( my $ncpuhost = qx{/usr/bin/nproc} ) // 1;
    $ncpuhost = 0 + $ncpuhost;    # coercing it to be a number
    my $info = {
        user            => $user,
        ncpuhost        => $ncpuhost,
        cwd             => cwd,
        hostname        => hostname,
        'Convert-Pheno' => $VERSION
    };
    my $resources = [
        {
            id   => "ICD10",
            name =>
"International Statistical Classification of Diseases and Related Health Problems 10th Revision",
            url             => "https://icd.who.int/browse10/2019/en#",
            version         => "2019",
            namespacePrefix => "ICD-10",
            iriPrefix       => "http://purl.obolibrary.org/obo/ICD10_"
        },
        {
            id              => "NCIT",
            name            => "NCI Thesaurus",
            url             => " http://purl.obolibrary.org/obo/ncit.owl",
            version         => "22.03d",
            namespacePrefix => "NCIT",
            iriPrefix       => "http://purl.obolibrary.org/obo/NCIT_"
        }
    ];
    return {
        #_info => $info,

        created                  => iso8601_time(),    # to alleviate testing
        createdBy                => $user,
        phenopacketSchemaVersion => '2.0',
        resources                => $resources
    };
}

sub Dumper_tidy {
    {
        local $Data::Dumper::Terse     = 1;
        local $Data::Dumper::Indent    = 1;
        local $Data::Dumper::Useqq     = 1;
        local $Data::Dumper::Deparse   = 1;
        local $Data::Dumper::Quotekeys = 1;
        local $Data::Dumper::Sortkeys  = 1;
        local $Data::Dumper::Pair      = ' : ';
        print Dumper shift;
    }
}

1;

=head1 NAME

Convert::Pheno - A module to interconvert common data models for phenotypic data
  
=head1 SYNOPSIS

 use Convert::Pheno;

 # Create a new object
 
 my $convert = Convert::Pheno->new($input);
 
 # Apply a method 
 
 my $data = $convert->redcap2bff;

=head1 DESCRIPTION

=head1 CITATION

The author requests that any published work that utilizes C<Convert-Pheno> includes a cite to the the following reference:

Rueda, M. "Convert-Pheno: A toolbox to interconvert common data models for phenotypic data". I<iManuscript in preparation>.

=head1 AUTHOR

Written by Manuel Rueda, PhD. Info about CNAG can be found at L<https://www.cnag.crg.eu>.

=head1 METHODS

=head2 COMMON ERRORS AND SOLUTIONS

 * Error message: Foo
   Solution: Bar

 * Error message: Foo
   Solution: Bar

=head1 COPYRIGHT

This PERL file is copyrighted. See the LICENSE file included in this distribution.

=cut
