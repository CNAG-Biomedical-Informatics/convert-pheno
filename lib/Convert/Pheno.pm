package Convert::Pheno;

use strict;
use warnings;
use autodie;
use utf8;
use feature               qw(say);
use FindBin               qw($Bin);
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use DBI;
use YAML::XS qw(LoadFile DumpFile);
use JSON::XS;
use Path::Tiny;
use File::Basename;
use Text::CSV_XS;
use Scalar::Util qw(looks_like_number);
use Sys::Hostname;
use Cwd         qw(cwd abs_path);
use POSIX       qw(strftime);
use Time::HiRes qw/gettimeofday/;
use List::Util  qw(any);
binmode STDOUT, ':encoding(utf-8)';

use constant DEVEL_MODE => 0;
use vars qw{
  $VERSION
  @ISA
  @EXPORT
};

@ISA     = qw( Exporter );
@EXPORT  = qw( $VERSION &write_json &write_yaml );
$VERSION = '0.0.0b';

# Constructor method
sub new {

    my ( $class, $self ) = @_;
    bless $self, $class;
    return $self;
}

# Global variables:
my $seen         = {};
my @sqlites      = qw(ncit icd10);
my $omop_version = 'v5.4';
my $omop_table   = {
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

# NB1: In general, we'll only display terms that exist and have content
# NB2: We are using pure OO Perl but we might switch to Moose if things get trickier...

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
      [ map { $_ = { "diseaseCode" => $_->{term} } }
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
    for my $term (qw (dateOfBirth genes meta_data variants)) {
        $individual->{info}{phenopacket}{$term} = $phenopacket->{$term}
          if exists $phenopacket->{$term};
    }

    # **** $data->{interpretation} ****
    $individual->{info}{interpretation}{phenopacket}{meta_data} =
      $interpretation->{phenopacket}{meta_data};

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
            label          => $phenopacket->{subject}{sex},
            ontology       => 'ncit',
            display_labels => $self->{print_hidden_labels},
            sth            => $sth->{ncit}
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

    # Depending on the origion (redcap) , _info and resources may exist
    $data->{meta_data} =
      exists $data->{info}{meta_data}
      ? $data->{info}{meta_data}
      : get_meta_data();
    $data->{interpretation} = { phenopacket => {} };
    return { phenopacket => $data };
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
    my $data_rcd = read_redcap_dictionary( $self->{redcap_dictionary} );

    print Dumper $data_rcd if ( $self->{debug} && $self->{debug} > 1 );

    $self->{data}     = $data;        # Dynamically adding attributes (setter)
    $self->{data_rcd} = $data_rcd;    # Dynamically adding attributes (setter)

    # array_dispatcher will deal with JSON arrays
    return array_dispatcher($self);
}

sub do_redcap2bff {

    my ( $self, $participant ) = @_;
    my $rcd = $self->{data_rcd};
    my $sth = $self->{sth};

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

    print Dumper $rcd         if $self->{debug};
    print Dumper $participant if $self->{debug};

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
            map2rcd(
                {
                    rcd         => $rcd,
                    participant => $participant,
                    field       => 'age_first_diagnosis'
                }
            )
        ) if $participant->{age_first_diagnosis} ne '';
        $disease->{diseaseCode} = map_ontology(
            {
                label => $field,

                #    ontology       => 'icd10',                        # ICD:10 Inflammatory Bowel Disease does not exist
                ontology       => 'ncit',
                display_labels => $self->{print_hidden_labels},
                sth            => $sth->{ncit}
            }
        );
        $disease->{familyHistory} = convert2boolean(
            map2rcd(
                {
                    rcd         => $rcd,
                    participant => $participant,
                    field       => 'family_history'
                }
            )
        ) if $participant->{family_history} ne '';
        $disease->{notes}    = undef;
        $disease->{severity} = undef;
        $disease->{stage}    = undef;
        push @{ $individual->{diseases} }, $disease;
    }

    # =========
    # ethnicity
    # =========

    $individual->{ethnicity} = map_ethnicity(
        map2rcd(
            { rcd => $rcd, participant => $participant, field => 'ethnicity' }
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

        $exposure->{ageAtExposure} = undef;
        $exposure->{date}          = undef;          #'2010-07-10';
        $exposure->{duration}      = undef;          # 'P32Y6M1D';
        $exposure->{exposureCode}  = map_ontology(
            {
                label          => $field,
                ontology       => 'ncit',
                display_labels => $self->{print_hidden_labels},
                sth            => $sth->{ncit}
            }
        );

        # We first extract 'unit' that supposedly will be used in <measurementValue> and <referenceRange>??
        my $unit = map_ontology(
            {
                label => ( $field eq 'alcohol' || $field eq 'smoking' )
                ? map_exposures(
                    {
                        key => $field,
                        str => map2rcd(
                            {
                                rcd         => $rcd,
                                participant => $participant,
                                field       => $field
                            }
                        )
                    }
                  )
                : $field,
                ontology       => 'ncit',
                display_labels => $self->{print_hidden_labels},
                sth            => $sth->{ncit}
            }
        );
        $exposure->{measurementValue} = [
            {
                Quantity => {
                    unit  => $unit,
                    value => dotify_and_coerce_number( $participant->{$field} ),
                    _note =>
'In many cases the <value> field shows the REDCap selection not the actual #items',
                    referenceRange =>
                      map_unit_range( { rcd => $rcd, field => $field } )
                }
            }
        ];
        push @{ $individual->{exposures} }, $exposure;
    }

    # ================
    # geographicOrigin
    # ================

    $individual->{geographicOrigin} = undef;

    # ==
    # id
    # ==

    $individual->{id} = $participant->{ids_complete}
      if $participant->{ids_complete} ne '';

    # ====
    # info
    # ====

    my @fields =
      qw(study_id dob diet redcap_event_name age first_name last_name consent consent_date consent_noneu consent_devices consent_recontact consent_week2_endo education zipcode consents_and_demographics_complete);
    for my $field (@fields) {
        $individual->{info}{$field} =
            $field eq 'age' ? 'P'
          . $participant->{$field}
          . 'Y'
          : ( any { /^$field$/ } qw(education diet) ) ? map2rcd(
            { rcd => $rcd, participant => $participant, field => $field } )
          : $field =~ m/^consent/ ? {
            value => dotify_and_coerce_number( $participant->{$field} ),
            map { $_ => $rcd->{$field}{$_} }
              ( "Field Label", "Field Note", "Field Type" )
          }
          : $participant->{$field}
          if $participant->{$field} ne '';
    }
    $individual->{info}{meta_data} = get_meta_data();

    # =========================
    # interventionsOrProcedures
    # =========================

    $individual->{interventionsOrProcedures} = [];

    #my @surgeries = map { $_ = 'surgery_details___' . $_ } ( 1 .. 8, 99 );
    my %surgery = ();
    for ( 1 .. 8, 99 ) {
        $surgery{ 'surgery_details___' . $_ } =
          $rcd->{surgery_details}{_labels}{$_};
    }
    for my $field (
        qw(endoscopy_performed intestinal_surgery partial_mayo complete_mayo prev_endosc_dilatation),
        keys %surgery
      )
    {
        if ( $participant->{$field} ) {
            my $intervention;
            $intervention->{ageAtProcedure} = undef;
            $intervention->{bodySite} =
              { id => 'NCIT:C12736', label => 'intestine' };
            $intervention->{dateOfProcedure} =
                $field eq 'endoscopy_performed'
              ? $participant->{endoscopy_date}
              : undef;
            $intervention->{procedureCode} = map_ontology(
                {
                    label          => $surgery{$field},
                    ontology       => 'ncit',
                    display_labels => $self->{print_hidden_labels},
                    sth            => $sth->{ncit}
                }
            ) if $surgery{$field};
            push @{ $individual->{interventionsOrProcedures} }, $intervention;
        }
    }

    # =============
    # karyotypicSex
    # =============

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
                label          => $field,
                ontology       => 'ncit',
                display_labels => $self->{print_hidden_labels},
                sth            => $sth->{ncit}
            }
        );
        $measure->{date} = undef;    # iso8601_time();

        # We first extract 'unit' and %range' for <measurementValue>
        my $unit = map_ontology(
            {
                label          => map_quantity( $rcd->{$field}{'Field Note'} ),
                ontology       => 'ncit',
                display_labels => $self->{print_hidden_labels},
                sth            => $sth->{ncit}
            }
        );
        $measure->{measurementValue} = [
            {
                Quantity => {
                    unit  => $unit,
                    value => dotify_and_coerce_number( $participant->{$field} ),
                    referenceRange =>
                      map_unit_range( { rcd => $rcd, field => $field } )
                }
            }
        ];
        $measure->{notes} = "$field, Field Label=$rcd->{$field}{'Field Label'}";
        $measure->{observationMoment} = undef;          # Age
        $measure->{procedure}         = map_ontology(
            {
                  label => $field eq 'calprotectin' ? 'Feces'
                : $field =~ m/^nancy/ ? 'Histologic'
                : 'Blood Test Result',
                ontology       => 'ncit',
                display_labels => $self->{print_hidden_labels},
                sth            => $sth->{ncit}
            }
        );

        # Add to array
        push @{ $individual->{measures} }, $measure;    # SWITCHED OFF on 072622
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
            #  { Quantity => { unit => { id => '', label => '' }, value => undef } };
            $phenotypicFeature->{featureType} = map_ontology(
                {
                    label    => $field =~ m/comorb/ ? 'Comorbidity' : $field,
                    ontology => 'ncit',
                    display_labels => $self->{print_hidden_labels},
                    sth            => $sth->{ncit}

                }
            );

            #$phenotypicFeature->{modifiers}   = { id => '', label => '' };
            $phenotypicFeature->{notes} =
              "$field, Field Label=$rcd->{$field}{'Field Label'}";

            #$phenotypicFeature->{onset}       = { id => '', label => '' };
            #$phenotypicFeature->{resolution}  = { id => '', label => '' };
            #$phenotypicFeature->{severity}    = { id => '', label => '' };

            # Add to array
            push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature;
        }
    }

    # ===
    # sex
    # ===

    $individual->{sex} = map_ontology(
        {
            label => map2rcd(
                { rcd => $rcd, participant => $participant, field => 'sex' }
            ),
            ontology       => 'ncit',
            display_labels => $self->{print_hidden_labels},
            sth            => $sth->{ncit}

        }
    ) if $participant->{sex} ne '';

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
                status    => map2rcd(
                    {
                        rcd         => $rcd,
                        participant => $participant,
                        field       => $tmp_var
                    }
                ),
                route => $route,
                value => $participant->{$tmp_var},
                map { $_ => $participant->{ $drug . $_ } }
                  qw(start dose duration)
            };    # ***** INTERNAL FIELD
            $treatment->{ageAtOnset} = undef;    # P32Y6M1D
            $treatment->{cumulativeDose} =
              { Quantity =>
                  { unit => { id => '', label => '' }, value => undef } };
            $treatment->{doseIntervals}         = [];
            $treatment->{routeOfAdministration} = map_ontology(
                {
                    label    => ucfirst($route) . ' Route of Administration',  # Oral Route of Administration
                    ontology => 'ncit',
                    display_labels => $self->{print_hidden_labels},
                    sth            => $sth->{ncit}

                }
            );

            $treatment->{treatmentCode} = map_ontology(
                {
                    label          => $drug_name,
                    ontology       => 'ncit',
                    display_labels => $self->{print_hidden_labels},
                    sth            => $sth->{ncit}

                }
            );
            push @{ $individual->{treatments} }, $treatment;
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

    # First we need to know if we have SQL dump or *csv
    # Read and load data from OMOP-CDM export
    my $data;
    my @exts = qw(.csv .tsv .txt .sql);
    for my $file ( @{ $self->{in_files} } ) {
        my ( $table_name, undef, $ext ) = fileparse( $file, @exts );
        if ( $ext eq '.sql' ) {
            $data = read_sqldump( $file, $self );
            sqldump2csv( $data, $self->{out_dir} ) if $self->{sql2csv};
            last;
        }
        else {
            warn "<$table_name> is not a valid table in OMOP-CDM"
              unless any { /^$table_name$/ } @{ $omop_table->{$omop_version} };
            $data->{$table_name} =
              read_csv_export( { in => $file, sep => $self->{sep} } );
        }
    }

    # Now we need to perform a tranformation of the data where 'person_id' is one row of data
    $self->{data} = transpose_omop_data_structure($data);    # Dynamically adding attributes (setter)

    # array_dispatcher will deal with JSON arrays
    return array_dispatcher($self);
}

sub do_omop2bff {

    my ( $self, $participant ) = @_;
    my $rcd = $self->{data_rcd};
    my $sth = $self->{sth};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################
    my $individual;

    # Get cursors for 1D terms
    #my $diagnoses = $participant->{ADMISSIONS};

    # ========
    # diseases
    # ========

    #$individual->{diseases} = [];

    my @diseases = qw(a b);
    for my $field (@diseases) {
        my $disease;

        #disease->{ageOfOnset} = map_age_range(
        #    map2rcd(
        #        {
        #            rcd         => $rcd,
        #            participant => $participant,
        #            field       => 'age_first_diagnosis'
        #        }
        #    )
        #) if $participant->{age_first_diagnosis} ne '';
        #$disease->{diseaseCode} = map_ontology(
        #    {
        #        label => $field,
        #
        #                #    ontology       => 'icd10',                        # ICD:10 Inflammatory Bowel Disease does not exist
        #                ontology       => 'ncit',
        #                display_labels => $self->{print_hidden_labels},
        #                sth            => $sth->{ncit}
        #        ) if @diseases ;
        #$disease->{familyHistory} = convert2boolean(
        #    map2rcd(
        #        {
        #            rcd         => $rcd,
        #            participant => $participant,
        #            field       => 'family_history'
        #        }
        #    )
        #) if $participant->{family_history} ne '';
        #    $disease->{notes}    = undef;
        #    $disease->{severity} = undef;
        #    $disease->{stage}    = undef;
        #push @{ $individual->{diseases} }, $disease;
    }

    # =========
    # ethnicity
    # =========

    $individual->{ethnicity} = $participant->{PERSON}{race_source_value}
      if exists $participant->{PERSON}{race_source_value};

    # =========
    # exposures
    # =========

    # ================
    # geographicOrigin
    # ================

    $individual->{geographicOrigin} =
      $participant->{PERSON}{ethnicity_source_value}
      if exists $participant->{PERSON}{ethnicity_source_value};

    # ==
    # id
    # ==

    $individual->{id} = $participant->{PERSON}{person_id}
      if exists $participant->{PERSON}{person_id};

    # ====
    # info
    # ====

    # =========================
    # interventionsOrProcedures
    # =========================

    # =============
    # karyotypicSex
    # =============

    # ========
    # measures
    # ========
    if ( exists $participant->{MEASUREMENT} ) {

        for my $measure ( @{ $participant->{MEASUREMENT} } ) {
            push @{ $individual->{measures} },
              { id => $measure->{measurement_concept_id} };
        }
    }

    # =========
    # pedigrees
    # =========

    # ==================
    # phenotypicFeatures
    # ==================

    # ===
    # sex
    # ===

    # ==========
    # treatments
    # ==========

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
    $self->{method}      = 'bff2pxf';    # setter
    $self->{data}        = $bff;         # setter
    $self->{in_textfile} = 0;            # setter

    # Run second iteration
    return array_dispatcher($self);
}

#########################
#########################
#  SUBROUTINES FOR CSV  #
#########################
#########################

sub read_csv_export {

    my $arg     = shift;
    my $in_file = $arg->{in};
    my $sep     = $arg->{sep};

    # Define split record separator
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    open my $fh, '<:encoding(utf8)', $in_file;

    # We'll read the header to assess separators in <txt> files
    chomp( my $tmp_header = <$fh> );

    # Defining separator character
    my $separator =
        $sep
      ? $sep
      : $ext eq '.csv' ? ';'    # Note we don't use comma but semicolon
      : $ext eq '.tsv' ? "\t"
      :                  ' ';

    # Defining variables
    my $data = [];                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Loading header fields into $header
    $csv->parse($tmp_header);
    my $header = [ $csv->fields() ];

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh) ) {

        # We store the data as an AoH $data
        my $tmp_hash;
        for my $i ( 0 .. $#{$header} ) {
            $tmp_hash->{ $header->[$i] } = $row->[$i];
        }
        push @$data, $tmp_hash;
    }

    close $fh;

    #########################################
    #     END READING CSV|TSV|TXT FILE      #
    #########################################

    return $data;
}

sub read_redcap_dictionary {

    my $in_file = shift;

    # Define split record separator
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    open my $fh, '<:encoding(utf8)', $in_file;

    # We'll read the header to assess separators in <txt> files
    chomp( my $tmp_header = <$fh> );

    # Defining separator
    my $separator =
        $ext eq '.csv' ? ';'
      : $ext eq '.tsv' ? "\t"
      :                  ' ';

    # Defining variables
    my $data = {};                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Loading header fields into $header
    $csv->parse($tmp_header);
    my $header = [ $csv->fields() ];

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh) ) {

        # We store the data as an AoH $data
        my $tmp_hash;

        for my $i ( 0 .. $#{$header} ) {

            # We keep key>/value as they are
            $tmp_hash->{ $header->[$i] } = $row->[$i];

            # For the key having labels, we create a new ad hoc key '_labels'
            # 'Choices, Calculations, OR Slider Labels' => '1, Female|2, Male|3, Other|4, not available',
            if ( $header->[$i] eq 'Choices, Calculations, OR Slider Labels' ) {
                my @tmp =
                  map { s/^\s//; s/\s+$//; $_; } ( split /\||,/, $row->[$i] );
                $tmp_hash->{_labels} = {@tmp} if @tmp % 2 == 0;
            }
        }

        # Now we create the 1D of the hash with 'Variable / Field Name'
        my $key = $tmp_hash->{'Variable / Field Name'};

        # And we nest the hash inside
        $data->{$key} = $tmp_hash;
    }

    close $fh;

    #######################################
    #     END READING CSV|TSV|TXT FILE    #
    #######################################

    return $data;
}

sub read_sqldump {

    my $file = shift;

    # Before resorting to writting this subroutine I performed an exhaustive search on CPAN
    # I tested MySQL::Dump::Parser::XS  but I could not make it work and other modules did not seem to do what I wanted...
    # .. so I ended up writting the parser myself...
    # The parser is based in reading COPY paragraphs from sql dump by using Perl's paragraph mode  $/ = "";
    # The sub can be seen as "ugly" but it does the job :-)

    my $limit = 1000;    #We have a counter to make things faste
    local $/ = "";       # set record separator to paragraph

    #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, attribute_description, attribute_type_concept_id, attribute_syntax) FROM stdin;
    # ......
    # \.

    # Start reading the SQL dump
    open my $fh, '<:encoding(utf-8)', $file;

    # We'll store the data in the hashref $data
    my $data = {};

    # Process paragraphs
    while ( my $paragraph = <$fh> ) {

        # Discarding paragraphs not having  m/^COPY/
        next unless $paragraph =~ m/^COPY/;

        # Discarding empty /^COPY/ paragraphs
        my @lines = split /\n/, $paragraph;
        next unless scalar @lines > 2;
        pop @lines;    # last line eq '\.'

        # Ad hoc for testing
        my $count = 0;

        # First line contain the headers
        #COPY "OMOP_cdm_eunomia".attribute_definition (attribute_definition_id, attribute_name, ..., attribute_syntax) FROM stdin;
        $lines[0] =~ s/[\(\),]//g;                                # getting rid of (),
        my @headers    = split /\s+/, $lines[0];
        my $table_name = uc( ( split /\./, $headers[1] )[1] );    # ATTRIBUTE_DEFINITION
        shift @lines;                                             # discarding first line

        # Discarding headers which are not terms/variables
        @headers = @headers[ 2 .. $#headers - 2 ];

        # Initializing $data>key as empty arrayref
        $data->{$table_name} = [];

        # Processing line by line
        for my $line (@lines) {
            $count++;
            last if $count == $limit;

            # Columns are separated by \t
            my @values = split /\t/, $line;

            # Loading the values like this:
            #
            #  $VAR1 = {
            #  'PERSON' => [
            #             {
            #              'person_id' => 123,
            #               'test' => 'abc'
            #             },
            #             {
            #               'person_id' => 456,
            #               'test' => 'def'
            #             }
            #           ]
            #         };

            push @{ $data->{$table_name} },
              { map { $headers[$_] => $values[$_] } ( 0 .. $#headers ) };
        }
    }
    return $data;
}

sub sqldump2csv {

    my ( $data, $dir ) = @_;

    # CSV sep character
    my $sep = "\t";

    # The idea is to save a CSV table for each $data->key
    for my $table ( keys %{$data} ) {

        # Name for CSV file
        my $filename = catdir( $dir, "$table.csv" );

        # Start printing
        open my $fh, ">:encoding(utf8)", $filename;
        my $csv =
          Text::CSV_XS->new( { sep_char => $sep, eol => "\n", binary => 1 } );

        # Print headers (got them from row[0]
        my @headers = sort keys %{ $data->{$table}[0] };
        say $fh join $sep, @headers;

        # Print rows
        foreach my $row ( 0 .. $#{ $data->{$table} } ) {

            # Transposing it to typical CSV format
            $csv->print( $fh, [ map { $data->{$table}[$row]{$_} } @headers ] );
        }
        close $fh;
    }
    return 1;
}

sub transpose_omop_data_structure {

    my $data     = shift;
    my $omop_ids = {};
    for my $table ( @{ $omop_table->{$omop_version} } ) {
        for my $item ( @{ $data->{$table} } ) {
            if ( exists $item->{person_id} && $item->{person_id} ne '' ) {
                my $person_id = $item->{person_id};

                # {person_id} can have multiple measures in a given table
                if ( $table eq 'MEASUREMENT' || $table eq 'OBSERVATION' ) {
                    push @{ $omop_ids->{$person_id}{$table} }, $item; # array
                }
                # {person_id} only has one value in a given TABLE
                else {
                    $omop_ids->{$person_id}{$table} = $item; # scalar
                }
            }
        }
    }
    return [ map { $omop_ids->{$_} } keys %{$omop_ids} ];
}

#########################
#########################
#  SUBROUTINES FOR I/O  #
#########################
#########################

sub read_json {

    my $json_file = shift;
    my $str       = path($json_file)->slurp_utf8;
    my $json      = decode_json($str);              # Decode to Perl data structure
    return $json;
}

sub write_json {

    my $arg        = shift;
    my $file       = $arg->{filename};
    my $json_array = $arg->{data};
    my $json = JSON::XS->new->utf8->canonical->pretty->encode($json_array);
    path($file)->spew_utf8($json);
    return 1;
}

sub write_yaml {

    my $arg        = shift;
    my $file       = $arg->{filename};
    my $json_array = $arg->{data};
    DumpFile( $file, $json_array );
    return 1;
}

#############################
#############################
#  SUBROUTINES FOR MAPPING  #
#############################
#############################

sub map_ethnicity {

    my $str       = shift;
    my %ethnicity = ( map { $_ => 'NCIT:C41261' } ( 'caucasian', 'white' ) );

    # 1, Caucasian | 2, Hispanic | 3, Asian | 4, African/African-American | 5, Indigenous American | 6, Mixed | 9, Other";
    return { id => $ethnicity{ lc($str) }, label => $str };
}

sub map_ontology {

    # Most of the execution time goes to this subroutine
    # We will adopt two estragies to gain speed:
    #  1 - Prepare once, excute often (almost no gain in speed :/ )
    #  2 - Create a global hash with "seen" queries (+++huge gain)

    #return { id => 'dummy', label => 'dummy' };    # test speed
    # Not a big fan of global stuff and premature return, but it works here...
    #  ¯\_(ツ)_/¯

    # Labels come in many forms, before checking existance we map to NCIT ones
    # Ad hoc modifications for 3TR
    my $tmp_label = map_3tr( $_[0]->{label} );

    # return if terms has already been searched and exists
    return $seen->{$tmp_label} if exists $seen->{$tmp_label};

    # return if we know 'a priori' that the label won't exist
    return { id => 'NCIT:NA', label => $tmp_label } if $tmp_label =~ m/xx/;

    # Ok, now it's time to start the subroutine
    my $arg                 = shift;
    my $ontology            = $arg->{ontology};
    my $print_hidden_labels = $arg->{display_labels};
    my $sth                 = $arg->{sth};

    # Perform query
    my ( $id, $label ) = execute_query_SQLite( $sth, $tmp_label, $ontology );

    # Add result to global $seen
    $seen->{$label} = { id => $id, label => $label };

    # id and label come from <db> _label is the original string (can change on partial matches)
    return $print_hidden_labels
      ? { id => $id, label => $label, _label => $tmp_label }
      : { id => $id, label => $label };
}

sub map_exposures {

    #alcohol;anamnesis;;radio;Alcohol drinking habits";"0, Non-drinker | 1, Ex-drinker | 2, occasional drinking | 3, regular drinking | 4, unknown";;;;;;;y;;;;;
    #smoking;anamnesis;;radio;"Smoking habits";"0, Never smoked | 1, Ex-smoker | 2, Current smoker";;;;;;;y;;;;;

    my $arg      = shift;
    my $key      = $arg->{key};
    my $str      = $arg->{str};
    my $exposure = {
        smoking => {
            'Never smoked'   => 'Never Smoker',
            'Ex-smoker'      => 'Former Smoker',
            'Current smoker' => 'Current Smoker'
        },
        alcohol => {
            'Non-drinker' => 'Non-Drinker',
            'Ex-drinker' => 'Current non-drinker with Past Alcohol Consumption',
            'occasional drinking' =>
'Alcohol Consumption Equal to or Less than 2 Drinks per Day for Men and 1 Drink or Less per Day for Women',
            'regular drinking' =>
'Alcohol Consumption More than 2 Drinks per Day for Men and More than 1 Drink per Day for Women',
            unknown => 'Unknown'
        }
    };
    return exists $exposure->{$key} ? $exposure->{$key}{$str} : $str;
}

sub map_quantity {

    # https://phenopacket-schema.readthedocs.io/en/latest/quantity.html
    # https://www.ebi.ac.uk/ols/ontologies/ncit/terms?iri=http%3A%2F%2Fpurl.obolibrary.org%2Fobo%2FNCIT_C25709
    # Some SI units are in ncit but others aren't.
    # what do we do?
    #  - Hard coded in Hash? ==> Fast
    #  - Search every time on DB? ==> Slow
    my $str = shift;

    # SI UNITS (10^9/L)
    # hemoglobin;routine_lab_values;;text;Hemoglobin;;"xx.x g/dl";number;0;20;;;y;;;;;
    #leucocytes;routine_lab_values;;text;Leucocytes;;"xx.xx /10^-9 l";number;0;200;;;y;;;;;
    #hematokrit;routine_lab_values;;text;Hematokrit;;"xx.x %";number;0;100;;;y;;;;;
    #mcv;routine_lab_values;;text;"Mean red cell volume (MCV)";;"xx.x fl";number;0;200;;;y;;;;;
    #mhc;routine_lab_values;;text;"Mean red cell haemoglobin (MCH)";;"xx.x pg";number;0;100;;;y;;;;;
    #thrombocytes;routine_lab_values;;text;Thrombocytes;;"xxxx /10^-9 l";number;0;2000;;;y;;;;;
    #neutrophils;routine_lab_values;;text;Neutrophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
    #lymphocytes;routine_lab_values;;text;Lymphocytes;;"x.xx /10^-9 l";number;0;100;;;;;;;;
    #eosinophils;routine_lab_values;;text;Eosinophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
    #creatinine;routine_lab_values;;text;Creatinine;;"xxx µmol/l";number;0;10000;;;y;;;;;
    #gfr;routine_lab_values;;text;"GFR CKD-Epi";;"xxx ml/min/1.73";number;0;200;;;y;;;;;
    #bilirubin;routine_lab_values;;text;Bilirubin;;"xxx.x µmol/l";number;0;10000;;;y;;;;;
    #gpt;routine_lab_values;;text;GPT;;"xx.x U/l";number;0;10000;;;y;;;;;
    #ggt;routine_lab_values;;text;gammaGT;;"xx.x U/l";number;0;10000;;;y;;;;;
    #lipase;routine_lab_values;;text;Lipase;;"xx.x U/l";number;0;10000;;;;;;;;
    #crp;routine_lab_values;;text;CRP;;"xxx.x mg/l";number;0;1000;;;y;;;;;
    #iron;routine_lab_values;;text;Iron;;"xx.x µmol/l";number;0;1000;;;;;;;;
    #il6;routine_lab_values;;text;IL-6;;"xxxx.x ng/l";number;0;10000;;;;;;;;
    #calprotectin;routine_lab_values;;text;Calprotectin;;"mg/kg stool";integer;;;;;;;;;;

    # http://purl.obolibrary.org/obo/NCIT_C64783
    my %unit = (
        'xx.xx /10^-9 l' => 'Cells per Microliter',       # '10^9/L',
        'xx.x g/dl'      => 'Gram per Deciliter',         # 'g/dL',
        'xx.x fl'        => 'Femtoliter',                 # 'fL'
        'xx.x'           => 'Picogram',                   # 'pg',         #picograms
        'xx.x pg'        => 'Picogram',
        'xx.x µmol/l'    => 'Micromole per Liter',
        'xxx.x µmol/l'   => 'Micromole per Liter',
        'xxx µmol/l'     => 'Micromole per Liter',        # 'µmol/l',
        'ml/min/1.73'    => 'mL/min/1.73',
        'xx.x U/l'       => 'Units per Liter',
        'pg/dl'          => 'Picogram per Deciliter',     #'pg/dL',
        'mg/dl'          => 'Milligram per Deciliter',    #'mg/L',
        'µg/dl'          => 'Microgram per Deciliter',    #'µg/dL',
        'ng/dl'          => 'Nanogram per Deciliter',     #'ng/L'
        'mg/kg stool'    => 'Miligram per Kilogram',
        'xx.x %'         => 'Percentage'
    );

    #say "#{$str}# ====>  $unit{$str}" if  exists $unit{$str};
    return exists $unit{$str} ? $unit{$str} : $str;
}

sub dotify_and_coerce_number {

    my $val = shift;
    ( my $tr_val = $val ) =~ tr/,/./;

    # looks_like_number does not work with commas so we must tr first
    #say "$val === ",  looks_like_number($val);
    # coercing to number $tr_val and avoiding value = ""
    return
        looks_like_number($tr_val) ? 0 + $tr_val
      : $val eq ''                 ? undef
      :                              $val;
}

sub iso8601_time {

    my ( $s, $f ) = split( /\./, gettimeofday );
    return strftime( '%Y-%m-%dT%H:%M:%S.' . $f . '%z', localtime($s) );
}

sub map_3tr {

    my $str  = shift;
    my %term = (

        #hemoglobin;routine_lab_values;;text;Hemoglobin;;"xx.x g/dl";number;0;20;;;y;;;;;
        #leucocytes;routine_lab_values;;text;Leucocytes;;"xx.xx /10^-9 l";number;0;200;;;y;;;;;
        #hematokrit;routine_lab_values;;text;Hematokrit;;"xx.x %";number;0;100;;;y;;;;;
        #mcv;routine_lab_values;;text;"Mean red cell volume (MCV)";;"xx.x fl";number;0;200;;;y;;;;;
        #mhc;routine_lab_values;;text;"Mean red cell haemoglobin (MCH)";;"xx.x pg";number;0;100;;;y;;;;;
        #thrombocytes;routine_lab_values;;text;Thrombocytes;;"xxxx /10^-9 l";number;0;2000;;;y;;;;;
        #neutrophils;routine_lab_values;;text;Neutrophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
        #lymphocytes;routine_lab_values;;text;Lymphocytes;;"x.xx /10^-9 l";number;0;100;;;;;;;;
        #eosinophils;routine_lab_values;;text;Eosinophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
        #creatinine;routine_lab_values;;text;Creatinine;;"xxx µmol/l";number;0;10000;;;y;;;;;
        #gfr;routine_lab_values;;text;"GFR CKD-Epi";;"xxx ml/min/1.73";number;0;200;;;y;;;;;
        #bilirubin;routine_lab_values;;text;Bilirubin;;"xxx.x µmol/l";number;0;10000;;;y;;;;;
        #gpt;routine_lab_values;;text;GPT;;"xx.x U/l";number;0;10000;;;y;;;;;
        #ggt;routine_lab_values;;text;gammaGT;;"xx.x U/l";number;0;10000;;;y;;;;;
        #lipase;routine_lab_values;;text;Lipase;;"xx.x U/l";number;0;10000;;;;;;;;
        #crp;routine_lab_values;;text;CRP;;"xxx.x mg/l";number;0;1000;;;y;;;;;
        #iron;routine_lab_values;;text;Iron;;"xx.x µmol/l";number;0;1000;;;;;;;;
        #il6;routine_lab_values;;text;IL-6;;"xxxx.x ng/l";number;0;10000;;;;;;;;
        #calprotectin;routine_lab_values;;text;Calprotectin;;"mg/kg stool";integer;;;;;;;;;;

        # Field => NCIT Term
        hemoglobin   => 'Hemoglobin Measurement',
        leucocytes   => 'Leukocyte Count',
        hematokrit   => 'Hematocrit Measurement',
        mcv          => 'Erythrocyte Mean Corpuscular Volume',
        mhc          => 'Erythrocyte Mean Corpuscular Hemoglobin',
        thrombocytes => 'Platelet Count',
        neutrophils  => 'Neutrophil Count',
        lymphocytes  => 'Lymphocyte Count',
        eosinophils  => 'Eosinophil Count',
        creatinine   => 'Creatinine Measurement',
        gfr          => 'Glomerular Filtration Rate',
        bilirubin    => 'Total Bilirubin Measurement',
        gpt          => 'Serum Glutamic Pyruvic Transaminase, CTCAE',
        ggt          => 'Serum Gamma Glutamyl Transpeptidase Measurement',
        lipase       => 'Lipase Measurement',
        crp          => 'C-Reactive Protein Measurement',
        iron         => 'Iron Measurement',
        il6          => 'Interleukin-6',
        calprotectin => 'Calprotectin Measurement',

        #cigarettes_days;anamnesis;;text;"On average, how many cigarettes do/did you smoke per day?";;;integer;0;300;;"[smoking] = '2' or [smoking] = '1'";;;;;;
        #cigarettes_years;anamnesis;;text;"For how many years have you been smoking/did you smoke?";;;integer;0;100;;"[smoking] = '2' or [smoking] = '1'";;;;;;
        #packyears;anamnesis;;text;"Pack Years";;;integer;0;300;;"[smoking] = '2' or [smoking] = '1'";;;;;;
        #smoking_quit;anamnesis;;text;"When did you quit smoking?";;year;integer;1980;2030;;"[smoking] = '2'";;;;;;
        cigarettes_days  => 'Average Number Cigarettes Smoked a Day',
        cigarettes_years => 'Total Years Have Smoked Cigarettes',
        packyears        => 'Pack Year',
        smoking_quit     => 'Smoking Cessation Year',

        #nancy_index_ulceration;endoscopy;;radio;"Nancy histology index: Ulceration";"0, 0 - none|2, 2 - yes";;;;;;"[endoscopy_performed] = '1' AND [week_0_arm_1][diagnosis] = '2'";y;;;;;
        #nancy_index_acute;endoscopy;;radio;"Nancy histology index: Acute inflammatory cell infiltrate";"0, 0 - none|2, 2 - mild|3, 3 - moderate|4, 4 - severe";;;;;;"[endoscopy_performed] = '1' AND [week_0_arm_1][diagnosis] = '2'";y;;;;;
        # nancy_index_chronic;endoscopy;;radio;"Nancy histology index: Chronic inflammatory infiltrates";"0, 0 - none|1, 1 - mild|3, 3 - moderate or marked increase";;;;;;"[endoscopy_performed] = '1' AND [week_0_arm_1][diagnosis] = '2'";y;;;;;
        nancy_index_ulceration => 'Nancy Index Ulceration',
        nancy_index_acute      =>
          'Nancy histology index: Acute inflammatory cell infiltrate',
        nancy_index_chronic =>
          'Nancy histology index: Chronic inflammatory infiltrates'
    );
    return exists $term{$str} ? $term{$str} : $str;
}

sub map_unit_range {

    my $arg   = shift;
    my $field = $arg->{field};
    my $rcd   = $arg->{rcd};
    my %hash  = ( low => 'Text Validation Min', high => 'Text Validation Max' );
    my $hashref = { map { $_ => undef } qw(low high) };    # Initialize to undef
    for my $range (qw (low high)) {
        $hashref->{$range} =
          dotify_and_coerce_number( $rcd->{$field}{ $hash{$range} } );
    }
    return $hashref;
}

sub map_age_range {

    my $str = shift;
    $str =~ s/\+/-9999/;                                   #60+#
    my ( $start, $end ) = split /\-/, $str;
    return {
        AgeRange => {
            start => dotify_and_coerce_number($start),
            end   => dotify_and_coerce_number($end)
        }
    };
}

sub map2rcd {

    my $arg = shift;
    my ( $rcd, $participant, $field ) =
      ( $arg->{rcd}, $arg->{participant}, $arg->{field} );
    return $rcd->{$field}{_labels}{ $participant->{$field} };
}

sub convert2boolean {

    my $val = lc(shift);
    return
        ( $val eq 'true'  || $val eq 'yes' ) ? JSON::XS::true
      : ( $val eq 'false' || $val eq 'no' )  ? JSON::XS::false
      :                                        undef;            # unknown = undef

}

########################
########################
#  SUBROUTINES FOR DB  #
########################
########################

sub open_connections_SQLite {

    my $self = shift;

    # Opening the DB once (instead that on each call) improves speed ~15%
    my $dbh;
    $dbh->{$_} = open_db_SQLite($_) for (@sqlites);    # global

    # Add $dbh HANDLE to $self
    $self->{dbh} = $dbh;                               # Need constructor for this

    # Prepare the query once
    prepare_query_SQLite($self);

    return 1;
}

sub close_connections_SQLite {

    my $self = shift;
    my $dbh  = $self->{dbh};
    close_db_SQLite( $dbh->{$_} ) for (@sqlites);      #global
    return 1;
}

sub open_db_SQLite {

    my $ontology = shift;
    my $dbfile   = catfile( $Bin, '../db', "$ontology.db" );
    my $user     = '';
    my $passwd   = '';
    my $dsn      = "dbi:SQLite:dbname=$dbfile";
    my $dbh      = DBI->connect(
        $dsn, $user, $passwd,
        {
            PrintError       => 0,
            RaiseError       => 1,
            AutoCommit       => 1,
            FetchHashKeyName => 'NAME_lc',
        }
    );

    return $dbh;
}

sub close_db_SQLite {

    my $dbh = shift;
    $dbh->disconnect();
    return 1;
}

sub prepare_query_SQLite {

    my $self  = shift;
    my $field = 'exact_match';

    # dbh = "Database Handle"
    # sth = "Statement Handle"
    for my $ontology (@sqlites) {    #global
        my $db         = uc($ontology) . '_table';
        my $dbh        = $self->{dbh}{$ontology};
        my %query_type = (
            contains =>
qq(SELECT * FROM $db WHERE label LIKE '%' || ? || '%' COLLATE NOCASE),
            contains_word =>
qq(SELECT * FROM $db WHERE label LIKE '% ' || ? || ' %' COLLATE NOCASE),
            exact_match => qq(SELECT * FROM $db WHERE label = ? COLLATE NOCASE),
            begins_with =>
              qq(SELECT * FROM $db WHERE label LIKE ? || '%' COLLATE NOCASE)
        );
        my $sth = $dbh->prepare(<<SQL);
$query_type{$field}
SQL
        $self->{sth}{$ontology} = $sth;    # Dynamically adding nested attributes (setter)
    }
    return 1;
}

sub execute_query_SQLite {

    my ( $sth, $query, $ontology ) = @_;
    my $field = 'exact_match';

    # Excute query
    $sth->execute($query);

    # Parse query
    $ontology = uc($ontology);
    my $id    = $ontology . ':NA';
    my $label = 'NA';
    while ( my $row = $sth->fetchrow_arrayref ) {
        $id    = $ontology . ':' . $row->[1];
        $label = $row->[0];
        last if $field eq 'exact_match';    # Note that sometimes we get more than one
    }
    $sth->finish();

    return ( $id, $label );
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
        for ( @{$in_data} ) {
            say "ARRAY ELEMENT" if $self->{debug};

            # In $self->{data} we have all participants data, but,
            # WE DELIBERATELY SEPARATE ARRAY ELEMENTS FROM $self->{data}
            push @{$out_data}, $func{ $self->{method} }->( $self, $_ );    # Method
        }
    }
    else {
        say "$self->{method}: NOT ARRAY" if $self->{debug};
        $out_data = $func{ $self->{method} }->( $self, $in_data );         # Method
    }

    # Close connections ONCE
    close_connections_SQLite($self) unless $self->{method} eq 'bff2pxf';

    return $out_data;
}

sub get_meta_data {

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
            namespacePrefix => "ICD-10"

              #iriPrefix => "http://purl.obolibrary.org/obo/HP_"
        },
        {
            id              => "NCIT",
            name            => "NCI Thesaurus",
            url             => " http://purl.obolibrary.org/obo/ncit.owl",
            version         => "22.03d",
            namespacePrefix => "NCIT"
        }
    ];
    return {
        _info     => $info,
        resources => $resources,
        created   => iso8601_time()
    };
}

1;

=head1 NAME

Convert::Pheno -  Interconvert phenotypic data between different CDM formats
  
=head1 SYNOPSIS

 use Convert::Pheno;

 # Create a new object
 
 my $convert = Convert::Pheno->new($input);
 
 # Apply a method 
 
 my $data = $convert->redcap2bff;

=head1 DESCRIPTION

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
