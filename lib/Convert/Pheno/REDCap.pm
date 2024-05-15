package Convert::Pheno::REDCap;

use strict;
use warnings;
use autodie;
use feature qw(say);
use List::Util qw(any);
use Convert::Pheno::Default qw(get_defaults);
use Convert::Pheno::Mapping;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use Hash::Util qw(lock_keys);
use Exporter 'import';

# Symbols to export by default
our @EXPORT = qw(do_redcap2bff);

# Symbols to export on demand
our @EXPORT_OK =
  qw(get_required_terms map_diseases map_ethnicity map_exposures);

my $DEFAULT = get_defaults();

###############
# Field Types #
###############

#'calc'
#'checkbox'
#'descriptive'
#'dropdown'
#'notes'
#'radio'
#'slider'
#'text'
#'yesno'

my @redcap_field_types = ( 'Field Label', 'Field Note', 'Field Type' );

################
################
#  REDCAP2BFF  #
################
################

sub do_redcap2bff {

    my ( $self, $participant ) = @_;
    my $redcap_dict       = $self->{data_redcap_dict};
    my $data_mapping_file = $self->{data_mapping_file};

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
    #          ...
    #        }
    print Dumper $redcap_dict
      if ( defined $self->{debug} && $self->{debug} > 4 );
    print Dumper $participant
      if ( defined $self->{debug} && $self->{debug} > 4 );

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type

    # Data structure (hashref) for each individual
    my $individual = {};

    # Intialize parameters for most subs
    my $param_sub = {
        type              => 'REDCap',
        project_id        => $data_mapping_file->{project}{id},
        ontology          => $data_mapping_file->{project}{ontology},
        redcap_dict       => $redcap_dict,
        data_mapping_file => $data_mapping_file,
        participant       => $participant,
        self              => $self,
        individual        => $individual
    };
    $param_sub->{lock_keys} = [ 'lock_keys', keys %$param_sub ];
    my ( $sex_field, $id_field ) = get_required_terms($param_sub);

    # Premature return (undef) if fields are not defined or present
    return
      unless ( defined $participant->{$id_field}
        && $participant->{$sex_field} );

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Load the main ontology for the project
    # <sex> and <ethnicity> project_ontology are fixed,
    #  (can't be changed granulary)

    my $project_id       = $data_mapping_file->{project}{id};
    my $project_ontology = $data_mapping_file->{project}{ontology};

    # NB: We don't need to initialize terms (unless required)
    # e.g.,
    # $individual->{diseases} = undef;
    #  or
    # $individual->{diseases} = []
    # Otherwise the validator may complain about being empty

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Loading in bulk fields that must to be mapped to redcap_dict
    # i.e., with defined $redcap_dict->{$_}{_labels}
    my @fields2map =
      grep { defined $redcap_dict->{$_}{_labels} } sort keys %{$redcap_dict};

    # Perform map2redcap_dict for this participant's fields2map
    for my $field (@fields2map) {

        # *** IMPORTANT ***
        # First we keep track of the original value (in case need it)
        # as $field . '_ori'
        # NB: If the file is not defined it will still appear as null at @info

        if ( defined $participant->{$field} ) {
            $participant->{ $field . '_ori' } = $participant->{$field};

            # Now we overwrite the original value with the dictionary one
            $participant->{$field} = dotify_and_coerce_number(
                map2redcap_dict(
                    {
                        redcap_dict => $redcap_dict,
                        participant => $participant,
                        field       => $field,
                        labels      => 1
                    }
                )
            );
        }
    }

    # ========
    # diseases
    # ========
    map_diseases($param_sub);

    # =========
    # ethnicity
    # =========

    map_ethnicity($param_sub);

    # =========
    # exposures
    # =========

    map_exposures($param_sub);

    # ================
    # geographicOrigin
    # ================

    #$individual->{geographicOrigin} = {};

    # ==
    # id
    # ==

    # Concatenation of the values in @id_fields (mapping file)
    $individual->{id} = join ':',
      map { $participant->{$_} // 'NA' } @{ $data_mapping_file->{id}{fields} };

    # ====
    # info
    # ====
    map_info($param_sub);

    # =========================
    # interventionsOrProcedures
    # =========================

    map_interventionsOrProcedures($param_sub);

    # =============
    # karyotypicSex
    # =============

    # $individual->{karyotypicSex} = undef;

    # ========
    # measures
    # ========

    $individual->{measures} = [];

    # Load hashref with cursors for mapping
    my $mapping = remap_mapping_hash_term( $data_mapping_file, 'measures' );

    for my $field ( @{ $mapping->{fields} } ) {
        next unless defined $participant->{$field};
        my $measure;

        $measure->{assayCode} = map_ontology(
            {
                query =>
                  replace_field_with_dictionary_if_exists( $mapping, $field ),
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self,
            }
        );
        $measure->{date} = $DEFAULT->{date};

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
            $participant->{$field} = $tmp_val;     # should be equal to $participant->{$field.'_ori'}
            $tmp_str = $tmp_scale;
        }

        my $unit = map_ontology(
            {
                query =>
                  replace_field_with_dictionary_if_exists( $mapping, $tmp_str ),
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
    #my @pedigrees = @{ $data_mapping_file->{pedigrees}{fields} };
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
    $mapping =
      remap_mapping_hash_term( $data_mapping_file, 'phenotypicFeatures' );

    for my $field ( @{ $mapping->{fields} } ) {
        my $phenotypicFeature;

        if ( defined $participant->{$field} && $participant->{$field} ne '' ) {

            #$phenotypicFeature->{evidence} = undef;    # P32Y6M1D

            my $tmp_var = $field;

            # *** IMPORTANT ***
            # Ad hoc change for 3TR
            if ( $project_id eq '3tr_ibd' && $field =~ m/comorb/i ) {
                $tmp_var = $redcap_dict->{$field}{'Field Label'};
                ( undef, $tmp_var ) = split / \- /, $tmp_var
                  if $tmp_var =~ m/\-/;
            }

            # Excluded (or Included) properties
            # 1 => included ( == not excluded )
            $phenotypicFeature->{excluded_ori} =
              dotify_and_coerce_number( $participant->{$field} );
            $phenotypicFeature->{excluded} =
              $participant->{$field} ? JSON::XS::false : JSON::XS::true
              if looks_like_number( $participant->{$field} );

            # print "#$field#$participant->{$field}#$tmp_var#\n";
            # Load selector fields
            my $subkey =
              exists $mapping->{selector}{$tmp_var} ? $tmp_var : undef;
            $phenotypicFeature->{featureType} = map_ontology(
                {
                    query => defined $subkey
                    ? $mapping->{selector}{$subkey}{ $participant->{$tmp_var} }
                    : replace_field_with_dictionary_if_exists(
                        $mapping, $tmp_var
                    ),
                    column   => 'label',
                    ontology => $mapping->{ontology},
                    self     => $self
                }
            );

            #$phenotypicFeature->{modifiers}   = { id => '', label => '' };

            # Prune ___\d+
            $field =~ s/___\w+$// if $field =~ m/___\w+$/;
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

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash_term( $data_mapping_file, 'sex' );

    # Load corrected field to search
    my $sex_query =
      replace_field_with_dictionary_if_exists( $mapping,
        $participant->{$sex_field} );

    # Search
    $individual->{sex} = map_ontology(
        {
            query    => $sex_query,
            column   => 'label',
            ontology => $project_ontology,
            self     => $self
        }
    );

    # ==========
    # treatments
    # ==========

    #$individual->{treatments} = undef;

    $mapping = remap_mapping_hash_term( $data_mapping_file, 'treatments' );

    for my $field ( @{ $mapping->{fields} } ) {

        # Getting the right name for the drug (if any)
        my $treatment_name =
          replace_field_with_dictionary_if_exists( $mapping, $field );

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
            $treatment->{ageAtOnset} = $DEFAULT->{age};
            $treatment->{cumulativeDose} =
              { unit => $DEFAULT->{ontology}, value => -1 };
            $treatment->{doseIntervals}         = [];
            $treatment->{routeOfAdministration} = map_ontology(
                {
                    query    => ucfirst($route) . ' Route of Administration',  # Oral Route of Administration
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

sub replace_field_with_dictionary_if_exists {

    my ( $mapping, $field ) = @_;
    return ( defined $field && exists $mapping->{dictionary}{$field} )
      ? $mapping->{dictionary}{$field}
      : $field;
}

sub get_required_terms {

    my $arg = shift;
    lock_keys( %$arg, @{ $arg->{lock_keys} } );

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};

    # Getting the field name from mapping file (note that we add _field suffix)
    my $sex_field = $data_mapping_file->{sex}{fields};
    my $id_field  = $data_mapping_file->{id}{mapping}{primary_key};

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # We need to pass 'sex' info to other array elements from $participant
    # where sex field is empty. Th ereason being that demographisc is compiled only at baseline
    # It's is mandatory that the row that contains demographics comes before the empty
    # Thus, we are storing $participant->{sex} in $self !!!
    # NB: Modifying source data from $arg
    if ( defined $participant->{$sex_field} ) {
        $self->{_info}{ $participant->{$id_field} }{$sex_field} =
          $participant->{$sex_field};    # Dynamically adding attributes (setter)
    }
    $participant->{$sex_field} =
      $self->{_info}{ $participant->{$id_field} }{$sex_field};

    return ( $sex_field, $id_field );
}

sub map_diseases {

    my $arg = shift;
    lock_keys( %$arg, @{ $arg->{lock_keys} } );

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};

    # Getting the field name from mapping file (note that we add _field suffix)
    #my $sex_field = $data_mapping_file->{sex}{fields};
    #my $id_field  = $data_mapping_file->{id}{mapping}{primary_key};

    #$individual->{diseases} = [];
    # NB: Inflamatory Bowel Disease --- Note the 2 mm in infla-mm-atory

    # Load hashref with cursors for mapping
    my $mapping = remap_mapping_hash_term( $data_mapping_file, 'diseases' );

    # Start looping over them
    for my $field ( @{ $mapping->{fields} } ) {
        my $disease;

        # Load a few more variables from mapping file
        # Start mapping
        $disease->{ageOfOnset} =
          map_age_range( $participant->{ $mapping->{mapping}{ageOfOnset} } )
          if ( exists $mapping->{mapping}{ageOfOnset}
            && defined $participant->{ $mapping->{mapping}{ageOfOnset} } );
        $disease->{diseaseCode} = map_ontology(
            {
                query    => $field,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );
        if ( exists $mapping->{mapping}{familyHistory}
            && defined $participant->{ $mapping->{mapping}{familyHistory} } )
        {
            my $family_history = convert2boolean(
                $participant->{ $mapping->{mapping}{familyHistory} } );
            $disease->{familyHistory} = $family_history
              if defined $family_history;
        }

        #$disease->{notes}    = undef;
        $disease->{severity} = $DEFAULT->{ontology};
        $disease->{stage}    = $DEFAULT->{ontology};

        push @{ $individual->{diseases} }, $disease
          if defined $disease->{diseaseCode};
    }

    return 1;
}

sub map_ethnicity {

    my $arg = shift;
    lock_keys( %$arg, @{ $arg->{lock_keys} } );

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};

    # Load field name from mapping file (string, as opossed to array)
    my $ethnicity_field = $data_mapping_file->{ethnicity}{fields};
    if ( defined $participant->{$ethnicity_field} ) {

        # Load hashref with cursors for mapping
        my $mapping =
          remap_mapping_hash_term( $data_mapping_file, 'ethnicity' );

        # Load corrected field to search
        my $ethnicity_query =
          replace_field_with_dictionary_if_exists( $mapping,
            $participant->{$ethnicity_field} );

        # Search
        $individual->{ethnicity} = map_ontology(
            {
                query    => $ethnicity_query,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );
    }
    return 1;
}

sub map_exposures {

    my $arg = shift;
    lock_keys( %$arg, @{ $arg->{lock_keys} } );

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};

    # Load hashref with cursors for mapping

    my $mapping = remap_mapping_hash_term( $data_mapping_file, 'exposures' );

    for my $field ( @{ $mapping->{fields} } ) {
        next unless defined $participant->{$field};

        my $exposure;
        $exposure->{ageAtExposure} =
          ( exists $mapping->{mapping}{ageAtExposure}
              && defined $participant->{ $mapping->{mapping}{ageAtExposure} } )
          ? map_age_range(
            $participant->{ $mapping->{mapping}{ageAtExposure} } )
          : $DEFAULT->{age};

        for my $item (qw/date duration/) {
            $exposure->{$item} =
              exists $mapping->{mapping}{$item}
              ? $participant->{ $mapping->{mapping}{$item} }
              : $DEFAULT->{$item};
        }

        # Query related
        my $exposure_query =
          replace_field_with_dictionary_if_exists( $mapping, $field );

        $exposure->{exposureCode} = map_ontology(
            {
                query    => $exposure_query,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );

        # Ad hoc term to check $field
        $exposure->{_info} = $field;

        # We first extract 'unit' that supposedly will be used in in
        # <measurementValue> and <referenceRange>??
        # Load selector fields
        my $subkey = exists $mapping->{selector}{$field} ? $field : undef;
        my $unit   = map_ontology(
            {
                # order on the ternary operator matters
                # 1 - Check for subkey
                # 2 - Check for field
                query => defined $subkey

                  #  selector.alcohol.Never smoked =>  Never Smoker
                ? $mapping->{selector}{$field}{ $participant->{$subkey} }
                : $exposure_query,
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self
            }
        );
        $exposure->{unit} = $unit;
        $exposure->{value} =
          looks_like_number( $participant->{$field} )
          ? $participant->{$field}
          : -1;
        push @{ $individual->{exposures} }, $exposure
          if defined $exposure->{exposureCode};
    }
    return 1;
}

sub map_info {

    my $arg = shift;
    lock_keys( %$arg, @{ $arg->{lock_keys} } );

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $type              = $arg->{type};
    my $project_id        = $arg->{project_id};
    my $redcap_dict       = $type eq 'REDCap' ? $arg->{redcap_dict} : undef;

    # Load hashref with cursors for mapping
    my $mapping = remap_mapping_hash_term( $data_mapping_file, 'info' );

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
    unless ( $self->{test} ) {
        $individual->{info}{metaData}     = $self->{metaData};
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }

    # Add version (from mapping file)
    $individual->{info}{version} = $data_mapping_file->{project}{version};

    # We finally add all origonal columns
    # NB: _ori are values before adding _labels
    my $tmp_str = $type . '_columns';
    $individual->{info}{$tmp_str} = $participant;
    return 1;
}

#$individual->{interventionsOrProcedures} = [];

sub map_interventionsOrProcedures {

    my $arg = shift;
    lock_keys( %$arg, @{ $arg->{lock_keys} } );

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $type              = $arg->{type};
    my $project_id        = $arg->{project_id};
    my $redcap_dict       = $type eq 'REDCap' ? $arg->{redcap_dict} : undef;

    # Load hashref with cursors for mapping
    my $mapping =
      remap_mapping_hash_term( $data_mapping_file,
        'interventionsOrProcedures' );

    for my $field ( @{ $mapping->{fields} } ) {
        if ( defined $participant->{$field} ) {

            my $intervention;

            $intervention->{ageAtProcedure} =
              ( exists $mapping->{mapping}{ageAtProcedure}
                  && defined $mapping->{mapping}{ageAtProcedure} )
              ? map_age_range(
                $participant->{ $mapping->{mapping}{ageAtProcedure} } )
              : $DEFAULT->{age};

            $intervention->{bodySite} =
              $project_id eq '3tr_ibd'
              ? { "id" => "NCIT:C12736", "label" => "intestine" }
              : $DEFAULT->{ontology};
            $intervention->{dateOfProcedure} =
              ( exists $mapping->{mapping}{dateOfProcedure}
                  && defined $mapping->{mapping}{dateOfProcedure} )
              ? dot_date2iso(
                $participant->{ $mapping->{mapping}{dateOfProcedure} } )
              : $DEFAULT->{date};

            # Ad hoc term to check $field
            $intervention->{_info} = $field;

            # Load selector fields
            my $subkey = exists $mapping->{selector}{$field} ? $field : undef;

            $intervention->{procedureCode} = map_ontology(
                {
                    query => defined $subkey
                    ? $mapping->{selector}{$subkey}{ $participant->{$field} }
                    : replace_field_with_dictionary_if_exists(
                        $mapping, $field
                    ),
                    column   => 'label',
                    ontology => $mapping->{ontology},
                    self     => $self
                }
            );
            push @{ $individual->{interventionsOrProcedures} }, $intervention
              if defined $intervention->{procedureCode};
        }
    }
    return 1;
}

1;
