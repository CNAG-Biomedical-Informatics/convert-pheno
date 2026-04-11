package Convert::Pheno::Mapping::BFF::Individuals::Tabular;

use strict;
use warnings;
use autodie;
use Convert::Pheno::Utils::Default qw(get_defaults);
use Convert::Pheno::Mapping::Shared;
use Scalar::Util qw(looks_like_number);
use Exporter 'import';

our @EXPORT_OK = qw(
  get_required_terms
  propagate_fields
  map_fields_to_redcap_dict
  map_diseases
  map_ethnicity
  map_exposures
  map_info
  map_interventionsOrProcedures
  map_measures
  map_pedigrees
  map_phenotypicFeatures
  map_sex
  map_treatments
);

my $DEFAULT = get_defaults();

my @redcap_field_types = ( 'Field Label', 'Field Note', 'Field Type' );

sub map_fields_to_redcap_dict {
    my ( $redcap_dict, $participant ) = @_;

    my @fields2map =
      grep { defined $redcap_dict->{$_}{_labels} } sort keys %{$redcap_dict};

    for my $field (@fields2map) {
        next unless defined $participant->{$field};

        $participant->{ $field . '_ori' } = $participant->{$field};

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

    my $value =
      ( $switch
          || defined $term_mapping_cursor->{assignTermIdFromHeader_hash}{$field}
      )
      ? $field
      : $participant_field;

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

    for my $field (@propagate_fields) {
        $self->{baselineFieldsToPropagate}{ $participant->{$id_field} }{$field}
          = $participant->{$field}
          if defined $participant->{$field};

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

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'diseases' );
    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};

        my $disease;
        $disease->{ageOfOnset} =
          exists $term_mapping_cursor->{ageOfOnset}{$field}
          ? map_age_range(
            $participant->{ $term_mapping_cursor->{ageOfOnset}{$field} } )
          : $DEFAULT->{age};

        my $disease_query =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field} );

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

    my $ethnicity_field = $data_mapping_file->{ethnicity}{fields};
    if ( defined $participant->{$ethnicity_field} ) {
        my $term_mapping_cursor =
          remap_mapping_hash_term( $data_mapping_file, 'ethnicity' );
        $arg->{term_mapping_cursor} = $term_mapping_cursor;

        my $ethnicity_query =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $ethnicity_field,
            $participant->{$ethnicity_field} );

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

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'exposures' );
    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};
        next
          if ( $participant->{$field} eq 'No'
            || $participant->{$field} eq 'False' );

        my $exposure;

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

        # Exposure codes come from the field/header concept (for example
        # smoking -> Smoking), while selector logic below maps the recorded
        # value (for example Never smoked -> Never Smoker).
        my $exposure_query =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field}, 1 );

        $exposure->{exposureCode} = map_ontology_term(
            {
                query    => $exposure_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );

        $exposure->{_info} = $field;

        my $subkey =
          ( lc( $data_mapping_file->{project}{source} ) eq 'redcap'
              && exists $term_mapping_cursor->{selector}{$field} )
          ? $field
          : undef;

        my $unit_query = defined $subkey
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
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'info' );

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};

        $individual->{info}{$field} = $participant->{$field};

        if ( exists $redcap_dict->{$field}{'Field Label'} ) {
            $individual->{info}{objects}{ $field . '_obj' } = {
                value => dotify_and_coerce_number( $participant->{$field} ),
                map { $_ => $redcap_dict->{$field}{$_} } @redcap_field_types
            };
        }
    }

    if ( exists $term_mapping_cursor->{mapping}{age} ) {
        my $age_range = map_age_range(
            $participant->{ $term_mapping_cursor->{mapping}{age} } );
        $individual->{info}{ageRange} = $age_range->{ageRange};
    }

    unless ( $self->{test} ) {
        $individual->{info}{metaData}     = $self->{metaData};
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }

    $individual->{info}{project}{$_} = $data_mapping_file->{project}{$_}
      for (qw/id source ontology version description/);

    my $output  = $source eq 'redcap' ? 'REDCap' : 'CSV';
    my $tmp_str = $output . '_columns';
    $individual->{info}{$tmp_str} = $participant;
    return 1;
}

sub map_interventionsOrProcedures {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};

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

        $intervention->{_info} = $field;

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
        _add_visit( $intervention, $arg );
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
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

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

        if ( lc($source) eq 'redcap' ) {
            $tmp_unit = map2redcap_dict(
                {
                    redcap_dict => $redcap_dict,
                    participant => $participant,
                    field       => $field,
                    labels      => 0
                }
            );

            if ( $participant->{$field} =~ m/ \- / ) {
                my ( $tmp_val, $tmp_scale ) = split / \- /,
                  $participant->{$field};
                $participant->{$field} = $tmp_val;
                $tmp_unit              = $tmp_scale;
            }
        }
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
        _add_visit( $measure, $arg );

        push @{ $individual->{measures} }, $measure
          if defined $measure->{assayCode};
    }
    return 1;
}

sub map_pedigrees {
    return 1;
}

sub map_phenotypicFeatures {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    my $participant       = $arg->{participant};
    my $self              = $arg->{self};
    my $individual        = $arg->{individual};
    my $source            = $arg->{source};
    my $redcap_dict = lc($source) eq 'redcap' ? $arg->{redcap_dict} : undef;

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'phenotypicFeatures' );
    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        my $phenotypicFeature;

        next
          unless ( defined $participant->{$field}
            && $participant->{$field} ne '' );

        $phenotypicFeature->{excluded_ori} =
          dotify_and_coerce_number( $participant->{$field} );

        my $is_boolean = 0;
        if ( looks_like_number( $participant->{$field} ) ) {
            $phenotypicFeature->{excluded} =
              $participant->{$field} ? JSON::XS::false : JSON::XS::true;
            $is_boolean++;
        }
        else {
            $phenotypicFeature->{excluded} = JSON::XS::false;
        }

        my $subkey =
          exists $term_mapping_cursor->{selector}{$field} ? $field : undef;

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

        $field =~ s/___\w+$// if $field =~ m/___\w+$/;
        $phenotypicFeature->{notes} = join ' /// ',
          (
            $field,
            map { qq/$_=$redcap_dict->{$field}{$_}/ } @redcap_field_types
          ) if lc($source) eq 'redcap';

        _add_visit( $phenotypicFeature, $arg );

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
    my $project_ontology  = $arg->{project_ontology};

    my $sex_field = $data_mapping_file->{sex}{fields};

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'sex' );

    my $sex_query =
      check_and_replace_field_with_terminology_or_dictionary_if_exist(
        $term_mapping_cursor, $sex_field, $participant->{$sex_field} );

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

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'treatments' );

    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined $participant->{$field};

        my $treatment;

        my $treatment_name =
          check_and_replace_field_with_terminology_or_dictionary_if_exist(
            $term_mapping_cursor, $field, $participant->{$field} );

        $treatment->{ageAtOnset} = $DEFAULT->{age};

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

            $dose_interval->{quantity}{value} = $participant->{$duration};
            $dose_interval->{quantity}{unit}  = $drug_unit;
            $dose_interval->{quantity}{referenceRange} =
              $DEFAULT->{referenceRange};

            $dose_interval->{scheduleFrequency} = $DEFAULT->{ontology_term};
            push @{ $treatment->{doseIntervals} }, $dose_interval;
        }

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
    }
    return 1;
}

sub _add_visit {
    my ( $item, $p ) = @_;
    my $cursor = $p->{term_mapping_cursor}
      or return;
    my $vf = $cursor->{visitId}
      or return;
    my $visit_val = $p->{participant}{$vf};
    $item->{_visit}{id} = $visit_val;

    my $pid       = $p->{participant_id} // q{};
    my $composite = join '.', grep { length } $pid, $visit_val;
    my $self      = $p->{self};
    $item->{_visit}{composite}     = $composite;
    # Tabular imports synthesize visit ids from source labels. A cached
    # surrogate integer is enough for referential integrity and much cheaper
    # than reversible BigInt encoding.
    $item->{_visit}{occurrence_id} = allocate_surrogate_integer(
        $self,
        'bff_visit_occurrence_id',
        $composite
    );
}

1;
