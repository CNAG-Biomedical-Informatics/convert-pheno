package Convert::Pheno::REDCap3TR;

use strict;
use warnings;
use autodie;
use feature    qw(say);
use List::Util qw(any);
use Convert::Pheno::Mapping;
use Convert::Pheno::PXF;
use Data::Dumper;
use Exporter 'import';
our @EXPORT = qw(do_redcap2bff);

################
################
#  REDCAP2BFF  #
################
################

sub do_redcap2bff {

    my ( $self, $participant ) = @_;
    my $redcap_dic   = $self->{data_redcap_dic};
    my $mapping_file = $self->{data_mapping_file};
    my $sth          = $self->{sth};

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

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type

    # Getting the field name from mapping file (note that we add _field suffix)
    my $sex_field     = $mapping_file->{sex};
    my $studyId_field = $mapping_file->{info}{dict}{studyId};

    # *** IMPORTANT STEP ***
    # We need to pass 'sex' info to external array elements from $participant
    # Thus, we are storing $participant->{sex} in $self !!!
    if ( exists $participant->{$sex_field} && $participant->{$sex_field} ne '' )
    {
        $self->{_info}{ $participant->{study_id} }{$sex_field} =
          $participant->{$sex_field};    # Dynamically adding attributes (setter)
    }
    $participant->{$sex_field} =
      $self->{_info}{ $participant->{$studyId_field} }{$sex_field};

    # Premature return if they don't exist
    return
      unless (
        (
            exists $participant->{$studyId_field}
            && $participant->{$studyId_field} ne ''
        )
        && $participant->{$sex_field} ne ''
      );

    # Data structure (hashref) for each individual
    my $individual;

    # Default ontology for a bunch of required terms
    my $default_ontology = { id => 'NCIT:NA0000', label => 'NA' };

    # NB: We don't need to initialize (unless required)
    # e.g.,
    # $individual->{diseases} = undef;
    #  or
    # $individual->{diseases} = []
    # Otherwise the validator may complain about being empty

    # ========
    # diseases
    # ========

    #$individual->{diseases} = [];

    # Inflamatory Bowel Disease --- Note the 2 mm in infla-mm-atory
    #my %disease = ( 'Inflammatory Bowel Disease' => 'ICD10:K51.90' ); # it does not exist as it is at ICD10
    #my @diseases = ('Unspecified asthma, uncomplicated', 'Inflamatory Bowel Disease', "Crohn's disease, unspecified, without complications");

    # Loading @diseases from mapping file
    my @diseases = @{ $mapping_file->{diseases}{fields} };

    # Start looping over them
    for my $field (@diseases) {
        my $disease;

        # Load a few more variables from mapping file
        my $ageOfOnset_field = $mapping_file->{diseases}{dict}{ageOfOnset};
        my $familyHistory_field =
          $mapping_file->{diseases}{dict}{familyHistory};

        # Start mapping
        $disease->{ageOfOnset} = map_age_range(
            map2redcap_dic(
                {
                    redcap_dic  => $redcap_dic,
                    participant => $participant,
                    field       => $ageOfOnset_field
                }
            )
          )
          if ( exists $participant->{$ageOfOnset_field}
            && $participant->{$ageOfOnset_field} ne '' );
        $disease->{diseaseCode} = map_ontology(
            {
                query    => $field,
                column   => 'label',
                ontology => 'ncit',
                self     => $self
            }
        );
        $disease->{familyHistory} = convert2boolean(
            map2redcap_dic(
                {
                    redcap_dic  => $redcap_dic,
                    participant => $participant,
                    field       => $familyHistory_field
                }
            )
          )
          if ( exists $participant->{$familyHistory_field}
            && $participant->{$familyHistory_field} ne '' );

        #$disease->{notes}    = undef;
        $disease->{severity} = $default_ontology;
        $disease->{stage}    = $default_ontology;

        push @{ $individual->{diseases} }, $disease
          if defined $disease->{diseaseCode};
    }

    # =========
    # ethnicity
    # =========

    # Load field name from mapping file
    my $ethnicity_field = $mapping_file->{ethnicity};

    $individual->{ethnicity} = map_ethnicity(
        map2redcap_dic(
            {
                redcap_dic  => $redcap_dic,
                participant => $participant,
                field       => $ethnicity_field
            }
        )
      )
      if ( exists $participant->{$ethnicity_field}
        && $participant->{$ethnicity_field} ne '' );

    # =========
    # exposures
    # =========

    #$individual->{exposures} = undef;
    my @exposures_fields = @{ $mapping_file->{exposures}{fields} };
    for my $field (@exposures_fields) {
        next
          unless ( exists $participant->{$field}
            && $participant->{$field} ne '' );
        my $exposure;

        $exposure->{ageAtExposure} = $default_ontology;
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

    my $longitudinal_id =
      $participant->{$studyId_field} . ':' . $participant->{redcap_event_name};
    $individual->{id} = $longitudinal_id;

    # ====
    # info
    # ====

    my @info_fields = @{ $mapping_file->{info}{fields} };
    for my $field (@info_fields) {
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
          if ( exists $participant->{$field} && $participant->{$field} ne '' );
    }
    $individual->{info}{metaData} = $self->{test} ? undef : get_metaData($self);

    # =========================
    # interventionsOrProcedures
    # =========================

    #$individual->{interventionsOrProcedures} = [];

    my @interventions_fields = @{ $mapping_file->{interventionsOrProcedures}{fields} };

    my %surgery = ();
    for ( 1 .. 8, 99 ) {
        $surgery{ 'surgery_details___' . $_ } =
          $redcap_dic->{surgery_details}{_labels}{$_};
    }

    for my $field (@interventions_fields)
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

    $individual->{measures} = undef;

    # lab_remarks was removed
    my @measures_fields = @{ $mapping_file->{measures}{fields} };
    for my $field (@measures_fields) {
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

    #$individual->{pedigrees} = [];

    # disease, id, members, numSubjects
    #my @pedigrees = @{ $mapping_file->{pedigrees}{fields} };
    #for my $field (@pedigrees) {
#
#        my $pedigree;
#        $pedigree->{disease}     = {};      # P32Y6M1D
#        $pedigree->{id}          = undef;
#        $pedigree->{members}     = [];
#        $pedigree->{numSubjects} = 0;
#
        # Add to array
        #push @{ $individual->{pedigrees} }, $pedigree; # SWITCHED OFF on 072622

   # }

    # ==================
    # phenotypicFeatures
    # ==================

    #$individual->{phenotypicFeatures} = [];

    my @phenotypicFeatures_fields =
      @{ $mapping_file->{phenotypicFeatures}{fields} };

    for my $field (@phenotypicFeatures_fields) {
        my $phenotypicFeature;

        if (   exists $participant->{$field}
            && $participant->{$field} ne ''
            && $participant->{$field} == 1 )
        {

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
                    field       => $sex_field
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

    #$individual->{treatments} = undef;

    my %drug = (
        aza => 'azathioprine',
        asa => 'aspirin',
        mtx => 'methotrexate',
        mp  => 'mercaptopurine'
    );

    my @treatments_fields = @{ $mapping_file->{treatments}{fields} };
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
            next
              unless ( exists $participant->{$tmp_var}
                && $participant->{$tmp_var} ne '' );

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
              { unit => $default_ontology, value => -1 };
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

1;
