package Convert::Pheno::REDCap;

use strict;
use warnings;
use autodie;
use feature                        qw(say);
use List::Util                     qw(any);
use Convert::Pheno::Utils::Default qw(get_defaults);
use Convert::Pheno::Utils::Mapping;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use Hash::Util   qw(lock_keys);
use Exporter 'import';

# Symbols to export by default
our @EXPORT = qw(do_redcap2bff);

# Symbols to export on demand
our @EXPORT_OK =
  qw(get_required_terms propagate_fields map_fields_to_redcap_dict map_diseases map_ethnicity map_exposures map_info map_interventionsOrProcedures map_measures map_pedigrees map_phenotypicFeatures map_sex map_treatments);

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

    # Data structure (hashref) for each individual
    my $individual = {};

    # Intialize parameters for most subs
    my $param_sub = {
        source              => $data_mapping_file->{project}{source},
        project_id          => $data_mapping_file->{project}{id},
        project_ontology    => $data_mapping_file->{project}{ontology},
        redcap_dict         => $redcap_dict,
        data_mapping_file   => $data_mapping_file,
        participant         => $participant,
        self                => $self,
        individual          => $individual,
        term_mapping_cursor => undef,

    };

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type
    my ( $sex_field, $id_field ) = get_required_terms($param_sub);

    # Now propagate fields according to user selection
    propagate_fields( $id_field, $param_sub );

    # Premature return (undef) if fields are not defined or present
    return
      unless ( defined $participant->{$id_field}
        && $participant->{$sex_field} );

    my $pid_field = $id_field;
    my $pid       = join ':',
      map { $participant->{$_} // 'NA' } @{ $data_mapping_file->{id}{fields} };

    # stash it in your param_sub
    $param_sub->{participant_id_field} = $pid_field;
    $param_sub->{participant_id}       = $pid;

    $param_sub->{lock_keys} = [ 'lock_keys', keys %$param_sub ];
    lock_keys %$param_sub, @{ $param_sub->{lock_keys} };

    # NB: We don't need to initialize terms (unless required)
    # e.g.,
    # $individual->{diseases} = undef;
    #  or
    # $individual->{diseases} = []
    # Otherwise the validator may complain about being empty

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Loading in bulk fields to be mapped to redcap_dict
    # e.g., $redcap_dict->{$_}{_labels}
    map_fields_to_redcap_dict( $redcap_dict, $participant );

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
    $individual->{id} = $pid;

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

    map_measures($param_sub);

    # =========
    # pedigrees
    # =========

    #map_pedigrees($param_sub);

    # ==================
    # phenotypicFeatures
    # ==================

    map_phenotypicFeatures($param_sub);

    # ===
    # sex
    # ===

    map_sex($param_sub);

    # ==========
    # treatments
    # ==========

    map_treatments($param_sub);

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individual;
}

#----------------------------------------------------------------------
# Helper subs
#----------------------------------------------------------------------

sub map_fields_to_redcap_dict {
    my ( $redcap_dict, $participant ) = @_;

    # Get the fields to map
    my @fields2map =
      grep { defined $redcap_dict->{$_}{_labels} } sort keys %{$redcap_dict};

    # Perform map2redcap_dict for the participant's fields2map
    for my $field (@fields2map) {
        next unless defined $participant->{$field};

        # Keep track of the original value (in case need it)
        # as $field . '_ori'
        $participant->{ $field . '_ori' } = $participant->{$field};

        # Overwrite the original value with the dictionary one
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
    return 1;
}

sub remap_mapping_hash_term {
    my ( $mapping_file_data, $term ) = @_;
    my %hash_out = map {
            $_ => exists $mapping_file_data->{$term}{$_}
          ? $mapping_file_data->{$term}{$_}
          : undef
    } (
        qw/fields assignTermIdFromHeader assignTermIdFromHeader_hash dictionary mapping selector terminology unit age drugDose drugUnit duration durationUnit dateOfProcedure bodySite ageOfOnset familyHistory visitId/
    );

    $hash_out{ontology} =
      exists $mapping_file_data->{$term}{ontology}
      ? $mapping_file_data->{$term}{ontology}
      : $mapping_file_data->{project}{ontology};

    $hash_out{routeOfAdministration} =
      $mapping_file_data->{$term}{routeOfAdministration}
      if $term eq 'treatments';

    return \%hash_out;
}

sub check_and_replace_field_with_terminology_or_dictionary_if_exist {
    my ( $term_mapping_cursor, $field, $participant_field, $switch ) = @_;
    $switch //= 0;

    # Check if $field is Boolean
    my $value =
      ( $switch
          || defined $term_mapping_cursor->{assignTermIdFromHeader_hash}{$field}
      )
      ? $field
      : $participant_field;

    # Precedence
    # "terminology" > "dictionary"
    return
      exists $term_mapping_cursor->{terminology}{$value}
      ? $term_mapping_cursor->{terminology}{$value}
      : exists $term_mapping_cursor->{dictionary}{$value}
      ? $term_mapping_cursor->{dictionary}{$value}
      : $value;
}

sub get_required_terms {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    return ( $data_mapping_file->{sex}{fields},
        $data_mapping_file->{id}{mapping}{primary_key} );
}

sub propagate_fields {
    my ( $id_field, $arg ) = @_;
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $data_mapping_file = $arg->{data_mapping_file};
    my @propagate_fields =
      @{ $data_mapping_file->{project}{baselineFieldsToPropagate} };

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Some measures are only taken at the baseline.
    # We need to propagate this information to other records
    # for the same participant.
    # It is mandatory that the row containing baseline data comes
    # before the rows with empty fields.
    # Therefore, we are storing in $self->{baselineFieldsToPropagate}
    # NB1: Modifying source data from $arg
    # NB2: Depending on the size of the data this step can take some RAM
    for my $field (@propagate_fields) {

        # Load $self for Baseline
        $self->{baselineFieldsToPropagate}{ $participant->{$id_field} }{$field}
          = $participant->{$field}
          if defined $participant->{$field};    # Dynamically adding attributes (setter)

        # Load field for all
        $participant->{$field} =
          $self->{baselineFieldsToPropagate}{ $participant->{$id_field} }
          {$field};
    }
    return 1;
}

sub map_diseases {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};

    #$individual->{diseases} = [];

    # NB: Inflamatory Bowel Disease --- Note the 2 mm in infla-mm-atory

    # Load hashref with cursors for mapping
    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'diseases' );
    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    # Start looping over them
    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};

        my $disease;

        # Load a few more variables from mapping file
        # Start mapping
        $disease->{ageOfOnset} =
          exists $term_mapping_cursor->{ageOfOnset}{$field}
          ? map_age_range(
            $participant->{ $term_mapping_cursor->{ageOfOnset}{$field} } )
          : $DEFAULT->{age};

        # Load corrected field to search
        my $disease_query =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field} );

        # Discard empty values
        next unless defined $disease_query;

        $disease->{diseaseCode} = map_ontology_term(
            {
                query    => $disease_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );

        if ( exists $term_mapping_cursor->{familyHistory}{$field}
            && defined
            $participant->{ $term_mapping_cursor->{familyHistory}{$field} } )
        {
            $disease->{familyHistory} = convert2boolean(
                $participant->{ $term_mapping_cursor->{familyHistory}{$field} }
            );
        }

        _add_visit( $disease, $arg );

        #$disease->{notes}    = undef;
        $disease->{severity} = $DEFAULT->{ontology_term};
        $disease->{stage}    = $DEFAULT->{ontology_term};

        push @{ $individual->{diseases} }, $disease;
    }

    return 1;
}

sub map_ethnicity {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};

    # Load field name from mapping file (string, as opossed to array)
    my $ethnicity_field = $data_mapping_file->{ethnicity}{fields};
    if ( defined $participant->{$ethnicity_field} ) {

        # Load hashref with cursors for mapping
        my $term_mapping_cursor =
          remap_mapping_hash_term( $data_mapping_file, 'ethnicity' );
        $arg->{term_mapping_cursor} = $term_mapping_cursor;

        # Load corrected field to search
        my $ethnicity_query =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $ethnicity_field,
            $participant->{$ethnicity_field} );

        # Search
        $individual->{ethnicity} = map_ontology_term(
            {
                query    => $ethnicity_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );
    }
    return 1;
}

sub map_exposures {
    my $arg = shift;

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $project_id        = $arg->{project_id};

    # Load hashref with cursors for mapping

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'exposures' );
    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};
        next
          if ( $participant->{$field} eq 'No'
            || $participant->{$field} eq 'False' );

        my $exposure;

        # Load selector for ageAtExposure
        my $subkey_ageAtExposure =
          ( exists $term_mapping_cursor->{selector}{$field}
              && defined $term_mapping_cursor->{selector}{$field} )
          ? $term_mapping_cursor->{selector}{$field}{ageAtExposure}
          : undef;

        $exposure->{ageAtExposure} =
          defined $subkey_ageAtExposure
          ? map_age_range( $participant->{$subkey_ageAtExposure} )
          : $DEFAULT->{age};

        for my $item (qw/date duration/) {
            $exposure->{$item} =
              exists $term_mapping_cursor->{mapping}{$item}
              ? $participant->{ $term_mapping_cursor->{mapping}{$item} }
              : $DEFAULT->{$item};
        }

        # Query related
        my $exposure_query =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field} );

        $exposure->{exposureCode} = map_ontology_term(
            {
                query    => $exposure_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );

        # Ad hoc term to check $field
        $exposure->{_info} = $field;

        # We first extract 'unit' that supposedly will be used in in
        # <measurementValue> and <referenceRange>??
        # Load selector fields
        my $subkey =
          ( lc( $data_mapping_file->{project}{source} ) eq 'redcap'
              && exists $term_mapping_cursor->{selector}{$field} )
          ? $field
          : undef;

        my $unit_query = defined $subkey

          # order on the ternary operator matters
          # 1 - Check for subkey
          # 2 - Check for field
          #  selector.alcohol.Never smoked =>  Never Smoker
          ? $term_mapping_cursor->{selector}{$field}{ $participant->{$subkey} }
          : $participant->{$field};

        my $unit = map_ontology_term(
            {
                query    => $unit_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );
        $exposure->{unit} = $unit;
        $exposure->{value} =
          looks_like_number( $participant->{$field} )
          ? $participant->{$field}
          : -1;

        _add_visit( $exposure, $arg );
        push @{ $individual->{exposures} }, $exposure
          if defined $exposure->{exposureCode};
    }
    return 1;
}

sub map_info {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};
    my $project_id        = $arg->{project_id};
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

    # Load hashref with cursors for mapping
    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'info' );

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};

        $individual->{info}{$field} = $participant->{$field};

        # Serialize dictionary fields to {info}{objects}
        if ( exists $redcap_dict->{$field}{'Field Label'} ) {
            $individual->{info}{objects}{ $field . '_obj' } = {
                value => dotify_and_coerce_number( $participant->{$field} ),
                map { $_ => $redcap_dict->{$field}{$_} } @redcap_field_types
            };
        }
    }

    # Map ageRange if exists
    if ( exists $term_mapping_cursor->{mapping}{age} ) {
        my $age_range = map_age_range(
            $participant->{ $term_mapping_cursor->{mapping}{age} } );
        $individual->{info}{ageRange} =
          $age_range->{ageRange};    #It comes nested from map_age_range()
    }

    # When we use --test we do not serialize changing (metaData) information
    unless ( $self->{test} ) {
        $individual->{info}{metaData}     = $self->{metaData};
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }

    # Add project properties from mapping file
    $individual->{info}{project}{$_} = $data_mapping_file->{project}{$_}
      for (qw/id source ontology version description/);

    # We finally add all original columns
    # NB: _ori are values before adding _labels
    my $output  = $source eq 'redcap' ? 'REDCap' : 'CSV';
    my $tmp_str = $output . '_columns';
    $individual->{info}{$tmp_str} = $participant;
    return 1;
}

#$individual->{interventionsOrProcedures} = [];

sub map_interventionsOrProcedures {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};
    my $project_id        = $arg->{project_id};
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

    # Load hashref with cursors for mapping
    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file,
        'interventionsOrProcedures' );

    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};

        my $intervention;

        $intervention->{ageAtProcedure} =
          exists $term_mapping_cursor->{ageAtProcedure}{$field}
          ? map_age_range(
            $participant->{ $term_mapping_cursor->{ageAtProcedure}{$field} } )
          : $DEFAULT->{age};

        $intervention->{bodySite} =
          exists $term_mapping_cursor->{bodySite}{$field}
          ? map_ontology_term(
            {
                query    => $term_mapping_cursor->{bodySite}{$field},
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
          )

          : $DEFAULT->{ontology_term};

        $intervention->{dateOfProcedure} =
          exists $term_mapping_cursor->{dateOfProcedure}{$field}
          ? convert_date_to_iso8601(
            $participant->{ $term_mapping_cursor->{dateOfProcedure}{$field} } )
          : $DEFAULT->{date};

        # Ad hoc term to check $field
        $intervention->{_info} = $field;

        # Load selector fields
        my $subkey =
          exists $term_mapping_cursor->{selector}{$field} ? $field : undef;

        my $intervention_query =
          defined $subkey
          ? $term_mapping_cursor->{selector}{$subkey}{ $participant->{$field} }
          : check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field} );

        $intervention->{procedureCode} = map_ontology_term(
            {
                query    => $intervention_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );
        _add_visit(
            $intervention, $arg

        );
        push @{ $individual->{interventionsOrProcedures} }, $intervention
          if defined $intervention->{procedureCode};
    }
    return 1;
}

sub map_measures {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};
    my $project_id        = $arg->{project_id};
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

    # Load hashref with cursors for mapping
    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'measures' );

    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {

        next unless defined $participant->{$field};
        my $measure;

        $measure->{assayCode} = map_ontology_term(
            {
                query =>
                  check_and_replace_field_with_terminology_or_dictionary_if_exist(
                    $term_mapping_cursor, $field, $participant->{$field}, 1
                  ),
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self,
            }
        );

        $measure->{date} = $DEFAULT->{date};

        my ( $tmp_unit, $unit_cursor );

        ##########
        # REDCap #
        ##########

        if ( lc($source) eq 'redcap' ) {

            # We first extract 'unit' and %range' for <measurementValue>
            $tmp_unit = map2redcap_dict(
                {
                    redcap_dict => $redcap_dict,
                    participant => $participant,
                    field       => $field,
                    labels      => 0               # will get 'Field Note'

                }
            );

            # We can have  $participant->{$field} eq '2 - Mild'
            if ( $participant->{$field} =~ m/ \- / ) {
                my ( $tmp_val, $tmp_scale ) = split / \- /,
                  $participant->{$field};
                $participant->{$field} = $tmp_val;     # should be equal to $participant->{$field.'_ori'}
                $tmp_unit = $tmp_scale;
            }
        }

        ########
        # CSV #
        #######
        else {

            $unit_cursor = $term_mapping_cursor->{unit}{$field};
            $tmp_unit =
              exists $unit_cursor->{label} ? $unit_cursor->{label} : undef;

        }

        my $unit = map_ontology_term(
            {
                query =>

                  check_and_replace_field_with_terminology_or_dictionary_if_exist(
                    $term_mapping_cursor,   $tmp_unit,
                    $participant->{$field}, 1
                  ),
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );
        my $reference_range =
          lc($source) eq 'csv' && exists $unit_cursor->{referenceRange}
          ? map_reference_range_csv( $unit, $unit_cursor->{referenceRange} )
          : map_reference_range(
            {
                unit        => $unit,
                redcap_dict => $redcap_dict,
                field       => $field,
                source      => $source
            }
          );

        $measure->{measurementValue} = {
            quantity => {
                unit  => $unit,
                value => dotify_and_coerce_number( $participant->{$field} ),
                referenceRange => $reference_range
            }
        };
        $measure->{notes} = join ' /// ', $field,
          ( map { qq/$_=$redcap_dict->{$field}{$_}/ } @redcap_field_types )
          if lc($source) eq 'redcap';

        #$measure->{observationMoment} = undef;          # Age
        $measure->{procedure} = {
            procedureCode => map_ontology_term(
                {
                    query => exists $unit_cursor->{procedureCodeLabel}
                    ? $unit_cursor->{procedureCodeLabel}
                    : $field eq 'calprotectin' ? 'Feces'
                    : $field =~ m/^nancy/      ? 'Histologic'
                    : 'Blood Test Result',
                    column   => 'label',
                    ontology => $term_mapping_cursor->{ontology},
                    self     => $self
                }
            )
        };
        _add_visit(
            $measure, $arg

        );

        # Add to array
        push @{ $individual->{measures} }, $measure
          if defined $measure->{assayCode};
    }
    return 1;
}

#sub map_pedigrees {
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
#}

sub map_phenotypicFeatures {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};
    my $project_id        = $arg->{project_id};
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

    # Load hashref with cursors for mapping
    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'phenotypicFeatures' );
    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        my $phenotypicFeature;

        next
          unless ( defined $participant->{$field}
            && $participant->{$field} ne '' );

        #$phenotypicFeature->{evidence} = undef;    # P32Y6M1D

        # Usually phenotypicFeatures come as Boolean
        # Excluded (or Included) properties
        # 1 => included ( == not excluded )
        $phenotypicFeature->{excluded_ori} =
          dotify_and_coerce_number( $participant->{$field} );

        # 0 vs. >= 1
        my $is_boolean = 0;
        if ( looks_like_number( $participant->{$field} ) ) {
            $phenotypicFeature->{excluded} =
              $participant->{$field} ? JSON::XS::false : JSON::XS::true;
            $is_boolean++;
        }

        # ANy other string is excluded = 0 (i.e., included)
        else {
            $phenotypicFeature->{excluded} = JSON::XS::false;
        }

        # Load selector fields
        my $subkey =
          exists $term_mapping_cursor->{selector}{$field} ? $field : undef;

        # Depending on boolean or not we perform query on field or value
        my $participant_field = $is_boolean ? $field : $participant->{$field};

        my $phenotypicFeature_query =
          defined $subkey
          ? $term_mapping_cursor->{selector}{$subkey}{$participant_field}
          : check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field} );

        $phenotypicFeature->{featureType} = map_ontology_term(
            {
                query    => $phenotypicFeature_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
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
          ) if lc($source) eq 'redcap';

        #$phenotypicFeature->{onset}       = { id => '', label => '' };
        #$phenotypicFeature->{resolution}  = { id => '', label => '' };
        #$phenotypicFeature->{severity}    = { id => '', label => '' };

        _add_visit(
            $phenotypicFeature, $arg

        );

        # Add to array
        push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature
          if defined $phenotypicFeature->{featureType};
    }
    return 1;
}

sub map_sex {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};
    my $project_id        = $arg->{project_id};
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;
    my $project_ontology = $arg->{project_ontology};

    # Getting the field name from mapping file (note that we add _field suffix)
    my $sex_field = $data_mapping_file->{sex}{fields};

    # Load hashref with cursors for mapping
    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'sex' );

    # Load corrected field to search
    my $sex_query =
      check_and_replace_field_with_terminology_or_dictionary_if_exist(
        $term_mapping_cursor, $sex_field, $participant->{$sex_field} );

    # Search
    $individual->{sex} = map_ontology_term(
        {
            query    => $sex_query,
            column   => 'label',
            ontology => $project_ontology,
            self     => $self
        }
    );
    return 1;
}

sub map_treatments {
    my $arg = shift;

    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};
    my $project_id        = $arg->{project_id};
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

    # Load hashref with cursors for mapping
    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'treatments' );

    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};

        # Initialize field $treatment
        my $treatment;

        # Getting the right name for the drug (if any)
        # *** Important ***
        # It can come from variable name or from the value
        my $treatment_name =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field} );

        $treatment->{ageAtOnset} = $DEFAULT->{age};

        # Define intervals
        $treatment->{doseIntervals} = [];
        my $dose_interval;
        my $duration =
          exists $term_mapping_cursor->{duration}{$field}
          ? $term_mapping_cursor->{duration}{$field}
          : undef;
        my $duration_unit =
          exists $term_mapping_cursor->{durationUnit}{$field}
          ? map_ontology_term(
            {
                query    => $term_mapping_cursor->{durationUnit}{$field},
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
          )
          : $DEFAULT->{ontology_term};
        if ( defined $duration ) {
            $treatment->{cumulativeDose} = {
                unit  => $duration_unit,
                value => $participant->{$duration} // -1
            };
            my $drug_unit =
              exists $term_mapping_cursor->{drugUnit}{$field}
              ? map_ontology_term(
                {
                    query    => $term_mapping_cursor->{drugUnit}{$field},
                    column   => 'label',
                    ontology => $term_mapping_cursor->{ontology},
                    self     => $self
                }
              )
              : $DEFAULT->{ontology_term};
            $dose_interval->{interval} = $DEFAULT->{interval};

            # Autovivification of $dose_interval->{quantity}
            $dose_interval->{quantity}{value} = $participant->{$duration};
            $dose_interval->{quantity}{unit}  = $drug_unit;
            $dose_interval->{quantity}{referenceRange} =
              $DEFAULT->{referenceRange};

            $dose_interval->{scheduleFrequency} = $DEFAULT->{ontology_term};
            push @{ $treatment->{doseIntervals} }, $dose_interval;
        }

        # Define routes (note that we use $participant->{$field} instead of $field)
        my $route =
          exists $term_mapping_cursor->{routeOfAdministration}
          { $participant->{$field} }
          ? $term_mapping_cursor->{routeOfAdministration}
          { $participant->{$field} }
          : 'oral';
        my $route_query = ucfirst($route) . ' Route of Administration';
        $treatment->{_info} = {
            field     => $field,
            value     => $participant->{$field},
            drug_name => $treatment_name,
            route     => $route
        };

        $treatment->{routeOfAdministration} = map_ontology_term(
            {
                query    => $route_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );

        $treatment->{treatmentCode} = map_ontology_term(
            {
                query    => $treatment_name,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );
        _add_visit( $treatment, $arg );
        push @{ $individual->{treatments} }, $treatment
          if defined $treatment->{treatmentCode};

        #}
    }
    return 1;
}

sub _add_visit {
    my ( $item, $p ) = @_;
    my $cursor = $p->{term_mapping_cursor}
      or return;    # no cursor, no visitId
    my $vf = $cursor->{visitId}
      or return;    # no visit field, bail
    my $visit_val = $p->{participant}{$vf};
    $item->{_visit}{id} = $visit_val;

    # build the unique occurrence_id
    my $pid       = $p->{participant_id} // ''; # REDCap only
    my $composite = join '.', grep { length } $pid, $visit_val;
    print Dumper $composite;
    $item->{_visit}{composite}     = $composite;
    $item->{_visit}{occurrence_id} = string2number($composite);
}

1;
