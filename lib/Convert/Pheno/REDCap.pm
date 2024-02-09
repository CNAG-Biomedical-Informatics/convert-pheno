package Convert::Pheno::REDCap;

use strict;
use warnings;
use autodie;
use feature qw(say);
use List::Util qw(any);
use Convert::Pheno::Mapping;
use Convert::Pheno::PXF;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use Exporter 'import';
our @EXPORT = qw(do_redcap2bff);

################
################
#  REDCAP2BFF  #
################
################

sub do_redcap2bff {

    my ( $self, $participant ) = @_;
    my $redcap_dict  = $self->{data_redcap_dict};
    my $mapping_file = $self->{data_mapping_file};
    my $sth          = $self->{sth};

    ##############################
    # <Variable> names in REDCap #
    ##############################
#
# REDCap does not enforce any particular variable name.
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
# If variable names are not consensuated, then we need to do the mapping manually "a posteriori".
# This is what we are attempting here:

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # $participant =
    #       {
    #         'abdominal_mass' => 0,
    #         'abdominal_pain' => 1,
    #         'age' => 2,
    #         'age_first_diagnosis' => 0,
    #         'alcohol' => 4,
    #        }
    print Dumper $redcap_dict
      if ( defined $self->{debug} && $self->{debug} > 4 );
    print Dumper $participant
      if ( defined $self->{debug} && $self->{debug} > 4 );

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type

    my @redcap_field_types = ( 'Field Label', 'Field Note', 'Field Type' );

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

    # More default values
    my $default_date     = '1900-01-01';
    my $default_duration = 'P999Y';
    my $default_age      = { age => { iso8601duration => 'P999Y' } };

    # Variable that will allow to perform ad hoc changes for specific projects
    my $project_id = $mapping_file->{project}{id};

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Load the main ontology for the project
    # <sex> and <ethnicity> project_ontology are fixed,
    #  (can't be changed granulary)

    my $project_ontology = $mapping_file->{project}{ontology};

    # NB: We don't need to initialize (unless required)
    # e.g.,
    # $individual->{diseases} = undef;
    #  or
    # $individual->{diseases} = []
    # Otherwise the validator may complain about being empty

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Loading fields that must to be mapped to redcap_dict in bulk
    my @fields2map =
      grep { defined $redcap_dict->{$_}{_labels} } sort keys %{$redcap_dict};

    # Perform the mapping for this participant
    for my $field (@fields2map) {

        # *** IMPORTANT ***
        # First we keep track of the original value (in case need it)
        # as $field . '_ori'
        $participant->{ $field . '_ori' } = $participant->{$field};

        # Now iwe overwrite the original value with the ditionary one
        $participant->{$field} = map2redcap_dict(
            {
                redcap_dict => $redcap_dict,
                participant => $participant,
                field       => $field,
                labels      => 1
            }
        ) if defined $participant->{$field};
    }

    # ========
    # diseases
    # ========

    #$individual->{diseases} = [];
    # NB: Inflamatory Bowel Disease --- Note the 2 mm in infla-mm-atory

    # Load hashref with cursors for mapping
    my $mapping = remap_mapping_hash( $mapping_file, 'diseases' );

    # Start looping over them
    for my $field ( @{ $mapping->{fields} } ) {
        my $disease;

        # Load a few more variables from mapping file
        # Start mapping
        $disease->{ageOfOnset} =
          map_age_range( $participant->{ $mapping->{map}{ageOfOnset} } )
          if ( exists $mapping->{map}{ageOfOnset}
            && defined $participant->{ $mapping->{map}{ageOfOnset} } );
        $disease->{diseaseCode} = map_ontology(
            {
                query    => $field,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );
        $disease->{familyHistory} =
          convert2boolean( $participant->{ $mapping->{map}{familyHistory} } )
          if ( exists $mapping->{map}{familyHistory}
            && defined $participant->{ $mapping->{map}{familyHistory} } );

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
    $individual->{ethnicity} = map_ethnicity( $participant->{$ethnicity_field} )
      if defined $participant->{$ethnicity_field};

    # =========
    # exposures
    # =========

    #$individual->{exposures} = undef;

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash( $mapping_file, 'exposures' );

    for my $field ( @{ $mapping->{fields} } ) {
        next unless defined $participant->{$field};

        my $exposure;
        $exposure->{ageAtExposure} =
          ( exists $mapping->{map}{ageAtExposure}
              && defined $participant->{ $mapping->{map}{ageAtExposure} } )
          ? map_age_range( $participant->{ $mapping->{map}{ageAtExposure} } )
          : $default_age;
        $exposure->{date} =
          exists $mapping->{map}{date}
          ? $participant->{ $mapping->{map}{date} }
          : $default_date;
        $exposure->{duration} =
          exists $mapping->{map}{duration}
          ? $participant->{ $mapping->{map}{duration} }
          : $default_duration;

        # Query related
        my $exposure_query =
          exists $mapping->{dict}{$field}
          ? $mapping->{dict}{$field}
          : $field;

        $exposure->{exposureCode} = map_ontology(
            {
                query    => $exposure_query,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );

        # We first extract 'unit' that supposedly will be used in in
        # <measurementValue> and <referenceRange>??
        #  e.g. radio.alcohol ? alcohol
        my $subkey = exists $mapping->{radio}{$field} ? $field : 'dummy';
        my $unit   = map_ontology(
            {
                # order on the ternary operator matters
                # 1 - Check for subkey
                # 2 - Check for field
                query => $subkey ne 'dummy'

                  #  radio.alcohol.Never smoked =>  Never Smoker
                ? $mapping->{radio}{$field}{ $participant->{$subkey} }
                : $exposure_query,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );
        $exposure->{unit}  = $unit;
        $exposure->{value} = $participant->{ $field . '_ori' } // -1;
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

    # Concatenation of the values in @id_fields (mapping file)
    $individual->{id} = join ':',
      map { $participant->{$_} } @{ $mapping_file->{id}{fields} };

    # ====
    # info
    # ====

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash( $mapping_file, 'info' );

    for my $field ( @{ $mapping->{fields} } ) {
        if ( defined $participant->{$field} ) {

            # Ad hoc for 3TR
            if ( $project_id eq '3tr_ibd' ) {
                $individual->{info}{$field} =
                  $field eq 'age' ? map_age_range( $participant->{$field} )
                  : $field =~ m/^consent/ ? {
                    value => dotify_and_coerce_number( $participant->{$field} ),
                    map { $_ => $redcap_dict->{$field}{$_} }
                      @redcap_field_types
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

    # We finally add all REDCap columns
    $individual->{info}{REDCap_columns} = $participant;

    # =========================
    # interventionsOrProcedures
    # =========================

    #$individual->{interventionsOrProcedures} = [];

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash( $mapping_file, 'interventionsOrProcedures' );

    for my $field ( @{ $mapping->{fields} } ) {
        if ( $participant->{$field} ) {

            # Why this
            next
              if ( exists $mapping->{map}{dateOfProcedure}
                && $field eq $mapping->{map}{dateOfProcedure} );
            my $intervention;

            $intervention->{ageAtProcedure} =
              ( exists $mapping->{map}{ageAtProcedure}
                  && defined $mapping->{map}{ageAtProcedure} )
              ? map_age_range(
                $participant->{ $mapping->{map}{ageAtProcedure} } )
              : $default_age;

            $intervention->{bodySite} =
              { "id" => "NCIT:C12736", "label" => "intestine" }
              if ( $project_id eq '3tr_ibd' );

            $intervention->{dateOfProcedure} =
              ( exists $mapping->{map}{dateOfProcedure}
                  && defined $mapping->{map}{dateOfProcedure} )
              ? dot_date2iso(
                $participant->{ $mapping->{map}{dateOfProcedure} } )
              : $default_date;

            $intervention->{procedureCode} = map_ontology(
                {
                    query => exists $mapping->{dict}{$field}
                    ? $mapping->{dict}{$field}
                    : $field,
                    column   => 'label',
                    ontology => $mapping->{ontology},
                    self     => $self
                }
            ) if defined $field;
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

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash( $mapping_file, 'measures' );

    for my $field ( @{ $mapping->{fields} } ) {
        next unless defined $participant->{$field};
        my $measure;

        $measure->{assayCode} = map_ontology(
            {
                query => exists $mapping->{dict}{$field}
                ? $mapping->{dict}{$field}
                : $field,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self,
            }
        );
        $measure->{date} = $default_date;

        # We first extract 'unit' and %range' for <measurementValue>
        my $tmp_str = map2redcap_dict(
            {
                redcap_dict => $redcap_dict,
                participant => $participant,
                field       => $field,
                labels      => 0               # will get 'Field Note'

            }
        );

        # We can have  $participant->{$field} eq '2 - Mild'
        if ( $participant->{$field} =~ m/ \- / ) {
            my ( $tmp_val, $tmp_scale ) = split / \- /, $participant->{$field};
            $participant->{$field} =
              $tmp_val;    # should be equal to $participant->{$field.'_ori'}
            $tmp_str = $tmp_scale;
        }

        my $unit = map_ontology(
            {
                query => exists $mapping->{dict}{$tmp_str}
                ? $mapping->{dict}{$tmp_str}
                : $tmp_str,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );
        $measure->{measurementValue} = {
            quantity => {
                unit  => $unit,
                value => dotify_and_coerce_number( $participant->{$field} ),
                referenceRange => map_reference_range(
                    {
                        unit        => $unit,
                        redcap_dict => $redcap_dict,
                        field       => $field
                    }
                )
            }
        };
        $measure->{notes} = join ' /// ', $field,
          ( map { qq/$_=$redcap_dict->{$field}{$_}/ } @redcap_field_types );

        #$measure->{observationMoment} = undef;          # Age
        $measure->{procedure} = {
            procedureCode => map_ontology(
                {
                      query => $field eq 'calprotectin' ? 'Feces'
                    : $field =~ m/^nancy/ ? 'Histologic'
                    : 'Blood Test Result',
                    column   => 'label',
                    ontology => $mapping->{ontology},
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

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash( $mapping_file, 'phenotypicFeatures' );

    for my $field ( @{ $mapping->{fields} } ) {
        my $phenotypicFeature;

        if ( defined $participant->{$field} && $participant->{$field} ne '' ) {

            #$phenotypicFeature->{evidence} = undef;    # P32Y6M1D
            my $tmp_var = $redcap_dict->{$field}{'Field Label'};

            # *** IMPORTANT ***
            # Ad hoc change for 3TR
            if ( $project_id eq '3tr_ibd' && $field =~ m/comorb/i ) {
                ( undef, $tmp_var ) = split / \- /,
                  $redcap_dict->{$field}{'Field Label'};
            }

            # Excluded (or Included) properties
            # 1 => included ( == not excluded )
            $phenotypicFeature->{excluded} =
              $participant->{$field} ? JSON::XS::false : JSON::XS::true
              if looks_like_number( $participant->{$field} );

            #$phenotypicFeature->{excluded_ori} = $participant->{$field};

            $phenotypicFeature->{featureType} = map_ontology(
                {
                    query => exists $mapping->{dict}{$tmp_var}
                    ? $mapping->{dict}{$tmp_var}
                    : $tmp_var,
                    column   => 'label',
                    ontology => $mapping->{ontology},
                    self     => $self

                }
            );

            #$phenotypicFeature->{modifiers}   = { id => '', label => '' };
            $phenotypicFeature->{notes} = join ' /// ',
              (
                $field,
                map { qq/$_=$redcap_dict->{$field}{$_}/ } @redcap_field_types
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
            query    => $participant->{$sex_field},
            column   => 'label',
            ontology => $project_ontology,
            self     => $self
        }
    );

    # ==========
    # treatments
    # ==========

    #$individual->{treatments} = undef;

    $mapping = remap_mapping_hash( $mapping_file, 'treatments' );

    for my $field ( @{ $mapping->{fields} } ) {

        # Getting the right name for the drug (if any)
        my $treatment_name =
          exists $mapping->{dict}{$field}
          ? $mapping->{dict}{$field}
          : $field;

        # FOR ROUTES
        for my $route ( @{ $mapping->{routesOfAdministration} } ) {

            # Ad hoc for 3TR
            my $tmp_var = $field;
            if ( $project_id eq '3tr_ibd' ) {

                # Rectal route only happens in some drugs (ad hoc)
                next
                  if (
                    $route eq 'rectal' && !any { $_ eq $field }
                    qw(budesonide asa)
                  );

                # Discarding if drug_route_status is empty
                $tmp_var =
                  ( $field eq 'budesonide' || $field eq 'asa' )
                  ? $field . '_' . $route . '_status'
                  : $field . '_status';
                next
                  unless defined $participant->{$tmp_var};
            }

            # Initialize field $treatment
            my $treatment;

            $treatment->{_info} = {
                field     => $tmp_var,
                drug      => $field,
                drug_name => $treatment_name,
                status    => $participant->{$tmp_var},
                route     => $route,
                value     => $participant->{ $tmp_var . '_ori' },
                map { $_ => $participant->{ $field . $_ } }
                  qw(start dose duration)
            };    # ***** INTERNAL FIELD
            $treatment->{ageAtOnset} = $default_age;
            $treatment->{cumulativeDose} =
              { unit => $default_ontology, value => -1 };
            $treatment->{doseIntervals}         = [];
            $treatment->{routeOfAdministration} = map_ontology(
                {
                    query => ucfirst($route)
                      . ' Route of Administration'
                    ,    # Oral Route of Administration
                    column   => 'label',
                    ontology => $mapping->{ontology},
                    self     => $self
                }
            );

            $treatment->{treatmentCode} = map_ontology(
                {
                    query    => $treatment_name,
                    column   => 'label',
                    ontology => $mapping->{ontology},
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
