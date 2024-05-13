package Convert::Pheno::CSV;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Convert::Pheno::Mapping;
use Data::Dumper;
use Hash::Fold fold => { array_delimiter => ':' };
use Exporter 'import';
our @EXPORT_OK = qw(do_bff2csv do_pxf2csv do_csv2bff);

#$Data::Dumper::Sortkeys = 1;

###############
###############
#  BFF2CSV    #
###############
###############

sub do_bff2csv {

    my ( $self, $bff ) = @_;

    # Premature return
    return unless defined($bff);

    # Flatten the hash to 1D
    my $csv = fold($bff);

    # Return the flattened hash
    return $csv;
}

###############
###############
#  PXF2CSV    #
###############
###############

sub do_pxf2csv {

    my ( $self, $pxf ) = @_;

    # Premature return
    return unless defined($pxf);

    # Flatten the hash to 1D
    my $csv = fold($pxf);

    # Return the flattened hash
    return $csv;
}

###############
###############
#  CSV2BFF    #
###############
###############

sub do_csv2bff {

    my ( $self, $participant ) = @_;
    my $data_mapping_file = $self->{data_mapping_file};
    my $sth               = $self->{sth};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # $participant =
    #       {
    #         'abdominal_mass' => 'No',
    #         'abdominal_pain' => 'Yes',
    #         'age' => 25,
    #         'age_first_diagnosis' => 24
    #          ...
    #        }
    print Dumper $participant
      if ( defined $self->{debug} && $self->{debug} > 4 );

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type

    # Getting the field name from mapping file (note that we add _field suffix)
    my $sex_field     = $data_mapping_file->{sex}{fields};
    my $id_field      = $data_mapping_file->{id}{fields};

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # We need to pass 'sex' info to external array elements from $participant
    # Thus, we are storing $participant->{sex} in $self !!!
    if ( defined $participant->{$sex_field} ) {
        $self->{_info}{ $participant->{$id_field} }{$sex_field} =
          $participant->{$sex_field};    # Dynamically adding attributes (setter)
    }
    $participant->{$sex_field} =
      $self->{_info}{ $participant->{$id_field} }{$sex_field};

    # Premature return if fields don't exist
    return
      unless ( defined $participant->{$id_field}
        && $participant->{$sex_field} );

    # Default values to be used accross the module
    my %default = (
        ontology => { id => 'NCIT:NA0000', label => 'NA' },
        date     => '1900-01-01',
        duration => 'P999Y',
        age      => { age => { iso8601duration => 'P999Y' } }
    );

    # Variable that will allow to perform ad hoc changes for specific projects
    my $project_id = $data_mapping_file->{project}{id};

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Load the main ontology for the project
    # <sex> and <ethnicity> project_ontology are fixed,
    #  (can't be changed granulary)

    my $project_ontology = $data_mapping_file->{project}{ontology};

    # Data structure (hashref) for each individual
    my $individual;

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
        $disease->{severity} = $default{ontology};
        $disease->{stage}    = $default{ontology};

        push @{ $individual->{diseases} }, $disease
          if defined $disease->{diseaseCode};
    }

    # =========
    # ethnicity
    # =========

    # Load field name from mapping file (string, as opossed to array)
    my $ethnicity_field = $data_mapping_file->{ethnicity}{fields};

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash_term( $data_mapping_file, 'ethnicity' );

    # Load corrected field to search
    my $field = $mapping->{dictionary}{ $participant->{$ethnicity_field} };

    # Search
    $individual->{ethnicity} = map_ontology(
        {
            query    => $field,
            column   => 'label',
            ontology => $mapping->{ontology},
            self     => $self
        }
    ) if defined $participant->{$ethnicity_field};

    # =========
    # exposures
    # =========

    #$individual->{exposures} = undef;

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash_term( $data_mapping_file, 'exposures' );

    for my $field ( @{ $mapping->{fields} } ) {
        next unless defined $participant->{$field};

        my $exposure;
        $exposure->{ageAtExposure} =
          ( exists $mapping->{mapping}{ageAtExposure}
              && defined $participant->{ $mapping->{mapping}{ageAtExposure} } )
          ? map_age_range(
            $participant->{ $mapping->{mapping}{ageAtExposure} } )
          : $default{age};

        for my $item (qw/date duration/) {
            $exposure->{$item} =
              exists $mapping->{mapping}{$item}
              ? $participant->{ $mapping->{mapping}{$item} }
              : $default{$item};
        }

        # Query related
        my $exposure_query =
          exists_mapping_dictionary_field( $mapping, $field );

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

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash_term( $data_mapping_file, 'info' );

    for my $field ( @{ $mapping->{fields} } ) {
        if ( defined $participant->{$field} ) {
            $individual->{info}{$field} = $participant->{$field};
        }
    }

    # When we use --test we do not serialize changing (metaData) information
    unless ( $self->{test} ) {
        $individual->{info}{metaData}     = $self->{metaData};
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }

    # Add version (from mapping file)
    $individual->{info}{version} = $data_mapping_file->{project}{version};

    # We finally add all CSV columns
    # NB: _ori are values before adding _labels
    $individual->{info}{CSV_columns} = $participant;

    # =========================
    # interventionsOrProcedures
    # =========================

    #$individual->{interventionsOrProcedures} = [];

    # Load hashref with cursors for mapping
    $mapping =
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
              : $default{age};

            $intervention->{bodySite} =
              $project_id eq '3tr_ibd'
              ? { "id" => "NCIT:C12736", "label" => "intestine" }
              : $default{ontology};
            $intervention->{dateOfProcedure} =
              ( exists $mapping->{mapping}{dateOfProcedure}
                  && defined $mapping->{mapping}{dateOfProcedure} )
              ? dot_date2iso(
                $participant->{ $mapping->{mapping}{dateOfProcedure} } )
              : $default{date};

            # Ad hoc term to check $field
            $intervention->{_info} = $field;

            # Load selector fields
            my $subkey = exists $mapping->{selector}{$field} ? $field : undef;

            $intervention->{procedureCode} = map_ontology(
                {
                    query => defined $subkey
                    ? $mapping->{selector}{$subkey}{ $participant->{$field} }
                    : exists_mapping_dictionary_field( $mapping, $field ),
                    column   => 'label',
                    ontology => $mapping->{ontology},
                    self     => $self
                }
            );
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

    # Load hashref with cursors for mapping
    $mapping = remap_mapping_hash_term( $data_mapping_file, 'measures' );

    for my $field ( @{ $mapping->{fields} } ) {
        next unless defined $participant->{$field};
        my $measure;

        $measure->{assayCode} = map_ontology(
            {
                query    => exists_mapping_dictionary_field( $mapping, $field ),
                column   => 'label',
                ontology => $mapping->{ontology},
                self     => $self,
            }
        );
        $measure->{date} = $default{date};

        # We first extract 'unit' and %range' for <measurementValue>
        my $tmp_str = map2redcap_dict(
            {
                #     redcap_dict => $redcap_dict,
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
                query  => exists_mapping_dictionary_field( $mapping, $tmp_str ),
                column => 'label',
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
                        unit => $unit,

                        #redcap_dict => $redcap_dict,
                        field => $field
                    }
                )
            }
        };

        #$measure->{notes} = join ' /// ', $field,
        #  ( map { qq/$_=$redcap_dict->{$field}{$_}/ } @redcap_field_types );

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
            #if ( $project_id eq '3tr_ibd' && $field =~ m/comorb/i ) {
            #    $tmp_var = $redcap_dict->{$field}{'Field Label'};
            #    ( undef, $tmp_var ) = split / \- /, $tmp_var
            #      if $tmp_var =~ m/\-/;
            #}

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
                    : exists_mapping_dictionary_field( $mapping, $tmp_var ),
                    column   => 'label',
                    ontology => $mapping->{ontology},
                    self     => $self
                }
            );

            #$phenotypicFeature->{modifiers}   = { id => '', label => '' };

            # Prune ___\d+
            $field =~ s/___\w+$// if $field =~ m/___\w+$/;

            #$phenotypicFeature->{notes} = join ' /// ',
            #  (
            #    $field,
            #    map { qq/$_=$redcap_dict->{$field}{$_}/ } @redcap_field_types
            #  );

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

    $mapping = remap_mapping_hash_term( $data_mapping_file, 'treatments' );

    for my $field ( @{ $mapping->{fields} } ) {

        # Getting the right name for the drug (if any)
        my $treatment_name =
          exists_mapping_dictionary_field( $mapping, $field );

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
            $treatment->{ageAtOnset} = $default{age};
            $treatment->{cumulativeDose} =
              { unit => $default{ontology}, value => -1 };
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

sub exists_mapping_dictionary_field {

    my ( $mapping, $field ) = @_;
    return ( defined $field && exists $mapping->{dictionary}{$field} )
      ? $mapping->{dictionary}{$field}
      : $field;
}

1;
