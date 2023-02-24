package Convert::Pheno::REDCap;

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
    print Dumper $redcap_dic
      if ( defined $self->{debug} && $self->{debug} > 4 );
    print Dumper $participant
      if ( defined $self->{debug} && $self->{debug} > 4 );

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type

    my @redcap_field_types = ( "Field Label", "Field Note", "Field Type" );

    # Getting the field name from mapping file (note that we add _field suffix)
    my $sex_field     = $mapping_file->{sex};
    my $studyId_field = $mapping_file->{info}{map}{studyId};

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # We need to pass 'sex' info to external array elements from $participant
    # Thus, we are storing $participant->{sex} in $self !!!
    if ( defined $participant->{$sex_field} ) {
        $self->{_info}{ $participant->{study_id} }{$sex_field} =
          $participant->{$sex_field};   # Dynamically adding attributes (setter)
    }
    $participant->{$sex_field} =
      $self->{_info}{ $participant->{$studyId_field} }{$sex_field};

    # Premature return if fields don't exist
    return
      unless ( defined $participant->{$studyId_field}
        && $participant->{$sex_field} );

    # Data structure (hashref) for each individual
    my $individual;

    # Default ontology for a bunch of required terms
    my $default_ontology = { id => 'NCIT:NA0000', label => 'NA' };

    # Variable that will allows to perform adhoc changes for some projects
    my $project_id = $mapping_file->{project}{id};

 # **********************
 # *** IMPORTANT STEP ***
 # **********************
 # Load the main ontology for the project
 # <sex> and <ethnicity> project_ontology are fixed (can't be changed granulary)

    my $project_ontology = $mapping_file->{project}{ontology};

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
    # Loading @diseases from mapping file
    my @diseases = @{ $mapping_file->{diseases}{fields} };
    my $diseases_ontology =
      exists $mapping_file->{diseases}{ontology}
      ? $mapping_file->{diseases}{ontology}
      : $project_ontology;

    # Start looping over them
    for my $field (@diseases) {
        my $disease;

        # Load a few more variables from mapping file
        my $ageOfOnset_field    = $mapping_file->{diseases}{map}{ageOfOnset};
        my $familyHistory_field = $mapping_file->{diseases}{map}{familyHistory};

        # Start mapping
        $disease->{ageOfOnset} = map_age_range(
            map2redcap_dic(
                {
                    redcap_dic  => $redcap_dic,
                    participant => $participant,
                    field       => $ageOfOnset_field,
                    labels      => 1
                }
            )
        ) if defined $participant->{$ageOfOnset_field};
        $disease->{diseaseCode} = map_ontology(
            {
                query    => $field,
                column   => 'label',
                ontology => $diseases_ontology,
                self     => $self
            }
        );
        $disease->{familyHistory} = convert2boolean(
            map2redcap_dic(
                {
                    redcap_dic  => $redcap_dic,
                    participant => $participant,
                    field       => $familyHistory_field,
                    labels      => 1
                }
            )
        ) if defined $participant->{$familyHistory_field};

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
                field       => $ethnicity_field,
                labels      => 1

            }
        )
    ) if defined $participant->{$ethnicity_field};

    # =========
    # exposures
    # =========

    #$individual->{exposures} = undef;
    my @exposures_fields = @{ $mapping_file->{exposures}{fields} };
    my %exposures_dict   = %{ $mapping_file->{exposures}{dict} };
    my $exposures_radio =
      $mapping_file->{exposures}{radio}; # DELIBERATE -- hashref instead of hash
    my $exposures_ontology =
      exists $mapping_file->{exposures}{ontology}
      ? $mapping_file->{exposures}{ontology}
      : $project_ontology;

    for my $field (@exposures_fields) {
        next
          unless defined $participant->{$field};
        my $exposure;
        $exposure->{ageAtExposure} = $default_ontology;
        $exposure->{date}          = '1900-01-01';
        $exposure->{duration}      = 'P999Y';
        my $exposure_query =
          exists $exposures_dict{$field} ? $exposures_dict{$field} : $field;
        $exposure->{exposureCode} = map_ontology(
            {
                query    => $exposure_query,
                column   => 'label',
                ontology => $exposures_ontology,
                self     => $self
            }
        );

        # We first extract 'unit' that supposedly will be used in in
        # <measurementValue> and <referenceRange>??
        my $subkey = exists $exposures_radio->{$field}
          ? map2redcap_dic(
            {
                redcap_dic  => $redcap_dic,
                participant => $participant,
                field       => $field,
                labels      => 1

            }
          )
          : 'dummy';
        my $unit = map_ontology(
            {
                # order on the ternary operator matters
                # 1 - Check for subkey
                # 2 - Check for field
                query => exists $exposures_radio->{$field}
                ? $exposures_radio->{$field}{$subkey}
                : $exposure_query,
                column   => 'label',
                ontology => $exposures_ontology,
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

    # It will will a concatentaion of the @id_fields from mapping file
    my @id_fields = @{ $mapping_file->{id}{fields} };
    $individual->{id} = join ':', map { $participant->{$_} } @id_fields;

    # ====
    # info
    # ====

    my @info_fields = @{ $mapping_file->{info}{fields} };
    for my $field (@info_fields) {
        if ( defined $participant->{$field} ) {
            if ( $project_id eq '3tr_ibd' ) {
                $individual->{info}{$field} =
                  $field eq 'age'
                  ? { iso8601duration => 'P' . $participant->{$field} . 'Y' }
                  : ( any { /^$field$/ } qw(education diet) ) ? map2redcap_dic(
                    {
                        redcap_dic  => $redcap_dic,
                        participant => $participant,
                        field       => $field,
                        labels      => 1

                    }
                  )
                  : $field =~ m/^consent/ ? {
                    value => dotify_and_coerce_number( $participant->{$field} ),
                    map { $_ => $redcap_dic->{$field}{$_} } @redcap_field_types
                  }
                  : $participant->{$field};
            }
            else {
                $individual->{info}{$field} = $participant->{$field};
            }
        }
    }

    # When we use --test we do not serialize changing (metaData) information
    $individual->{info}{metaData} = $self->{test} ? undef : get_metaData($self);

    # =========================
    # interventionsOrProcedures
    # =========================

    #$individual->{interventionsOrProcedures} = [];

    my @interventions_fields =
      @{ $mapping_file->{interventionsOrProcedures}{fields} };
    my $interventions_ontology =
      exists $mapping_file->{interventionsOrProcedures}{ontology}
      ? $mapping_file->{interventionsOrProcedures}{ontology}
      : $project_ontology;

    my %surgery = ();
    for ( 1 .. 8, 99 ) {
        $surgery{ 'surgery_details___' . $_ } =
          $redcap_dic->{surgery_details}{_labels}{$_};
    }

    for my $field (@interventions_fields) {
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
                    ontology => $interventions_ontology,
                    self     => $self
                }
            ) if defined $surgery{$field};
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
    my %measures_dict   = %{ $mapping_file->{measures}{dict} };
    my $measures_ontology =
      exists $mapping_file->{measures}{ontology}
      ? $mapping_file->{measures}{ontology}
      : $project_ontology;

    for my $field (@measures_fields) {
        next unless defined $participant->{$field};
        my $measure;

        $measure->{assayCode} = map_ontology(
            {
                query => exists $measures_dict{$field}
                ? $measures_dict{$field}
                : $field,
                column   => 'label',
                ontology => $measures_ontology,
                self     => $self,
            }
        );
        $measure->{date} = '1900-01-01';

        # We first extract 'unit' and %range' for <measurementValue>
        my $tmp_str =
          ( any { /^$field$/ }
              qw(nancy_index_acute nancy_index_chronic nancy_index_ulceration endo_mayo)
          )
          ? map2redcap_dic(
            {
                redcap_dic  => $redcap_dic,
                participant => $participant,
                field       => $field,
                labels      => 1

            }
          )
          : map2redcap_dic(
            {
                redcap_dic  => $redcap_dic,
                participant => $participant,
                field       => $field,
                labels      => 0               # will get 'Field Note'

            }
          );

        my $unit = map_ontology(
            {
                query => exists $measures_dict{$tmp_str}
                ? $measures_dict{$tmp_str}
                : $tmp_str,
                column   => 'label',
                ontology => $measures_ontology,
                self     => $self
            }
        );
        $measure->{measurementValue} = {
            quantity => {
                unit  => $unit,
                value => dotify_and_coerce_number( $participant->{$field} ),
                referenceRange => map_reference_range(
                    {
                        unit       => $unit,
                        redcap_dic => $redcap_dic,
                        field      => $field
                    }
                )
            }
        };
        $measure->{notes} = join ' /// ', $field,
          ( map { qq/$_=$redcap_dic->{$field}{$_}/ } @redcap_field_types );

        #$measure->{observationMoment} = undef;          # Age
        $measure->{procedure} = {
            procedureCode => map_ontology(
                {
                      query => $field eq 'calprotectin' ? 'Feces'
                    : $field =~ m/^nancy/ ? 'Histologic'
                    : 'Blood Test Result',
                    column   => 'label',
                    ontology => $measures_ontology,
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
    my $phenotypicFeatures_ontology =
      exists $mapping_file->{phenotypicFeatures}{ontology}
      ? $mapping_file->{phenotypicFeatures}{ontology}
      : $project_ontology;

    for my $field (@phenotypicFeatures_fields) {
        my $phenotypicFeature;

        if (   defined $participant->{$field}
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
                    ontology => $phenotypicFeatures_ontology,
                    self     => $self

                }
            );

            #$phenotypicFeature->{modifiers}   = { id => '', label => '' };
            $phenotypicFeature->{notes} = join ' /// ',
              (
                $field,
                map { qq/$_=$redcap_dic->{$field}{$_}/ } @redcap_field_types
              );

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
                    field       => $sex_field,
                    labels      => 1

                }
            ),
            column   => 'label',
            ontology => $project_ontology,
            self     => $self
        }
    );

    # ==========
    # treatments
    # ==========

    #$individual->{treatments} = undef;

    my @treatments_fields = @{ $mapping_file->{treatments}{fields} };
    my %drug              = %{ $mapping_file->{treatments}{dict} };
    my @routes            = @{ $mapping_file->{treatments}{routes} };
    my $treatments_ontology =
      exists $mapping_file->{treatments}{ontology}
      ? $mapping_file->{treatments}{ontology}
      : $project_ontology;

    for my $field (@treatments_fields) {

        # Getting the right name for the drug (if any)
        my $treatment_name = exists $drug{$field} ? $drug{$field} : $field;

        # FOR ROUTES
        for my $route (@routes) {

            # Rectal route only happens in some drugs (ad hoc)
            next
              if ( $route eq 'rectal' && !any { /^$field$/ }
                qw(budesonide asa) );

            # Discarding if drug_route_status is empty
            my $tmp_var =
              ( $field eq 'budesonide' || $field eq 'asa' )
              ? $field . '_' . $route . '_status'
              : $field . '_status';
            next
              unless defined $participant->{$tmp_var};

            # Initialize field $treatment
            my $treatment;

            $treatment->{_info} = {
                field     => $tmp_var,
                drug      => $field,
                drug_name => $treatment_name,
                status    => map2redcap_dic(
                    {
                        redcap_dic  => $redcap_dic,
                        participant => $participant,
                        field       => $tmp_var,
                        labels      => 1

                    }
                ),
                route => $route,
                value => $participant->{$tmp_var},
                map { $_ => $participant->{ $field . $_ } }
                  qw(start dose duration)
            };    # ***** INTERNAL FIELD
            $treatment->{ageAtOnset} =
              { age => { iso8601duration => "P999Y" } };
            $treatment->{cumulativeDose} =
              { unit => $default_ontology, value => -1 };
            $treatment->{doseIntervals}         = [];
            $treatment->{routeOfAdministration} = map_ontology(
                {
                    query => ucfirst($route)
                      . ' Route of Administration'
                    ,    # Oral Route of Administration
                    column   => 'label',
                    ontology => $treatments_ontology,
                    self     => $self
                }
            );

            $treatment->{treatmentCode} = map_ontology(
                {
                    query    => $treatment_name,
                    column   => 'label',
                    ontology => $treatments_ontology,
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
