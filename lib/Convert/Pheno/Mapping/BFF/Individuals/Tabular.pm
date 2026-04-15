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

sub source_value {
    my ( $arg, $field ) = @_;
    return exists $arg->{record}
      ? $arg->{record}->value($field)
      : $arg->{participant}{$field};
}

sub raw_value {
    my ( $arg, $field ) = @_;
    return exists $arg->{record}
      ? $arg->{record}->raw_value($field)
      : $arg->{participant}{$field};
}

sub field_note {
    my ( $arg, $field ) = @_;
    return exists $arg->{record}
      ? $arg->{record}->field_note($field)
      : undef;
}

sub field_meta {
    my ( $arg, $field ) = @_;
    return exists $arg->{record}
      ? $arg->{record}->field_meta($field)
      : undef;
}

sub source_columns_snapshot {
    my ($arg) = @_;
    return exists $arg->{record}
      ? $arg->{record}->columns_snapshot
      : { %{ $arg->{participant} } };
}

sub remap_mapping_hash_term {
    my ( $mapping_file_data, $term ) = @_;

    my %hash_out = map {
            $_ => exists $mapping_file_data->{$term}{$_}
          ? $mapping_file_data->{$term}{$_}
          : undef
    } (
        qw/fields useHeaderAsTermLabel useHeaderAsTermLabel_hash fieldTermLabels valueTermLabels targetFields fieldRules terminology unit age drugDose drugUnit duration durationUnit dateOfProcedure bodySite ageOfOnset ageAtProcedure familyHistory visitId/
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

sub resolve_field_query {
    my ( $term_mapping_cursor, $field ) = @_;

    return
      exists $term_mapping_cursor->{terminology}{$field}
      ? $term_mapping_cursor->{terminology}{$field}
      : exists $term_mapping_cursor->{fieldTermLabels}{$field}
      ? $term_mapping_cursor->{fieldTermLabels}{$field}
      : $field;
}

sub resolve_value_query {
    my ( $term_mapping_cursor, $value ) = @_;

    return
      exists $term_mapping_cursor->{terminology}{$value}
      ? $term_mapping_cursor->{terminology}{$value}
      : exists $term_mapping_cursor->{valueTermLabels}{$value}
      ? $term_mapping_cursor->{valueTermLabels}{$value}
      : $value;
}

sub resolve_term_query {
    my ( $term_mapping_cursor, $field, $participant_field ) = @_;

    return defined $term_mapping_cursor->{useHeaderAsTermLabel_hash}{$field}
      ? resolve_field_query( $term_mapping_cursor, $field )
      : resolve_value_query( $term_mapping_cursor, $participant_field );
}

sub get_required_terms {
    my $arg               = shift;
    my $data_mapping_file = $arg->{data_mapping_file};
    return ( $data_mapping_file->{sex}{fields},
        $data_mapping_file->{id}{targetFields}{primaryKey} );
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
        next unless defined raw_value( $arg, $field );

        my $disease;
        $disease->{ageOfOnset} =
          exists $term_mapping_cursor->{ageOfOnset}{$field}
          ? map_age_range(
            source_value( $arg, $term_mapping_cursor->{ageOfOnset}{$field} ) )
          : $DEFAULT->{age};

        my $disease_query =
          resolve_term_query( $term_mapping_cursor, $field,
            source_value( $arg, $field ) );

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
            raw_value( $arg, $term_mapping_cursor->{familyHistory}{$field} ) )
        {
            $disease->{familyHistory} = convert2boolean(
                source_value( $arg, $term_mapping_cursor->{familyHistory}{$field} )
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
    if ( defined raw_value( $arg, $ethnicity_field ) ) {
        my $term_mapping_cursor =
          remap_mapping_hash_term( $data_mapping_file, 'ethnicity' );
        $arg->{term_mapping_cursor} = $term_mapping_cursor;

        my $ethnicity_query =
          resolve_term_query( $term_mapping_cursor, $ethnicity_field,
            source_value( $arg, $ethnicity_field ) );

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
        next unless defined raw_value( $arg, $field );
        next
          if ( source_value( $arg, $field ) eq 'No'
            || source_value( $arg, $field ) eq 'False' );

        my $exposure;

        my $subkey_ageAtExposure =
          ( exists $term_mapping_cursor->{fieldRules}{$field}
              && defined $term_mapping_cursor->{fieldRules}{$field} )
          ? $term_mapping_cursor->{fieldRules}{$field}{ageAtExposure}
          : undef;

        $exposure->{ageAtExposure} =
          defined $subkey_ageAtExposure
          ? map_age_range( source_value( $arg, $subkey_ageAtExposure ) )
          : $DEFAULT->{age};

        for my $item (qw/date duration/) {
            $exposure->{$item} =
              exists $term_mapping_cursor->{targetFields}{$item}
              ? source_value( $arg, $term_mapping_cursor->{targetFields}{$item} )
              : $DEFAULT->{$item};
        }

        # Exposure codes come from the field/header concept (for example
        # smoking -> Smoking), while fieldRules below map the recorded value
        # (for example Never smoked -> Never Smoker).
        my $exposure_query =
          resolve_field_query( $term_mapping_cursor, $field );

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
              && exists $term_mapping_cursor->{fieldRules}{$field} )
          ? $field
          : undef;

        my $unit_query = defined $subkey
          ? $term_mapping_cursor->{fieldRules}{$field}{ source_value( $arg, $subkey ) }
          : source_value( $arg, $field );

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
          looks_like_number( source_value( $arg, $field ) )
          ? source_value( $arg, $field )
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

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'info' );

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined raw_value( $arg, $field );

        $individual->{info}{$field} = source_value( $arg, $field );

        my $meta = field_meta( $arg, $field );
        if ( defined $meta && exists $meta->{'Field Label'} ) {
            $individual->{info}{objects}{ $field . '_obj' } = {
                value => dotify_and_coerce_number( source_value( $arg, $field ) ),
                map { $_ => $meta->{$_} } @redcap_field_types
            };
        }
    }

    if ( exists $term_mapping_cursor->{targetFields}{age} ) {
        my $age_range = map_age_range(
            source_value( $arg, $term_mapping_cursor->{targetFields}{age} ) );
        $individual->{info}{ageRange} = $age_range->{ageRange};
    }

    unless ( $self->{test} ) {
        $individual->{info}{convertPheno} = $self->{convertPheno};
    }

    $individual->{info}{project}{$_} = $data_mapping_file->{project}{$_}
      for (qw/id source ontology version description/);

    my $output  = $source eq 'redcap' ? 'REDCap' : 'CSV';
    my $tmp_str = $output . '_columns';
    $individual->{info}{$tmp_str} = source_columns_snapshot($arg);
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
        next unless defined raw_value( $arg, $field );

        my $intervention;

        $intervention->{ageAtProcedure} =
          exists $term_mapping_cursor->{ageAtProcedure}{$field}
          ? map_age_range(
            source_value( $arg, $term_mapping_cursor->{ageAtProcedure}{$field} ) )
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
            source_value( $arg, $term_mapping_cursor->{dateOfProcedure}{$field} ) )
          : $DEFAULT->{date};

        $intervention->{_info} = $field;

        my $subkey =
          exists $term_mapping_cursor->{fieldRules}{$field} ? $field : undef;

        my $intervention_query =
          defined $subkey
          ? $term_mapping_cursor->{fieldRules}{$subkey}{ source_value( $arg, $field ) }
          : resolve_term_query(
            $term_mapping_cursor, $field, source_value( $arg, $field ) );

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

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'measures' );

    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        next unless defined raw_value( $arg, $field );
        my $measure;

        $measure->{assayCode} = map_ontology_term(
            {
                query =>
                  resolve_field_query( $term_mapping_cursor, $field ),
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self,
            }
        );

        $measure->{date} = $DEFAULT->{date};

        my ( $tmp_unit, $unit_cursor );
        my $measure_value = raw_value( $arg, $field );

        if ( lc($source) eq 'redcap' ) {
            $tmp_unit = field_note( $arg, $field );

            if ( $measure_value =~ m/ \- / ) {
                my ( $tmp_val, $tmp_scale ) = split / \- /,
                  $measure_value;
                $measure_value = $tmp_val;
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
                  resolve_value_query( $term_mapping_cursor, $tmp_unit ),
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
                redcap_dict => $arg->{redcap_dict},
                field       => $field,
                source      => $source
            }
          );

        $measure->{measurementValue} = {
            quantity => {
                unit  => $unit,
                value => dotify_and_coerce_number($measure_value),
                referenceRange => $reference_range
            }
        };
        if ( lc($source) eq 'redcap' ) {
            my $meta = field_meta( $arg, $field ) || {};
            $measure->{notes} = join ' /// ', $field,
              ( map { qq/$_=$meta->{$_}/ } @redcap_field_types );
        }

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

    my $term_mapping_cursor =
      remap_mapping_hash_term( $data_mapping_file, 'phenotypicFeatures' );
    $arg->{term_mapping_cursor} = $term_mapping_cursor;

    for my $field ( @{ $term_mapping_cursor->{fields} } ) {
        my $phenotypicFeature;

        next
          unless ( defined raw_value( $arg, $field )
            && raw_value( $arg, $field ) ne '' );

        $phenotypicFeature->{excluded_ori} =
          dotify_and_coerce_number( raw_value( $arg, $field ) );

        my $is_boolean = 0;
        if ( looks_like_number( raw_value( $arg, $field ) ) ) {
            $phenotypicFeature->{excluded} =
              raw_value( $arg, $field ) ? JSON::XS::false : JSON::XS::true;
            $is_boolean++;
        }
        else {
            $phenotypicFeature->{excluded} = JSON::XS::false;
        }

        my $subkey =
          exists $term_mapping_cursor->{fieldRules}{$field} ? $field : undef;

        my $participant_field = $is_boolean ? $field : source_value( $arg, $field );

        my $phenotypicFeature_query =
          defined $subkey
          ? $term_mapping_cursor->{fieldRules}{$subkey}{$participant_field}
          : resolve_term_query(
            $term_mapping_cursor, $field, source_value( $arg, $field ) );

        $phenotypicFeature->{featureType} = map_ontology_term(
            {
                query    => $phenotypicFeature_query,
                column   => 'label',
                ontology => $term_mapping_cursor->{ontology},
                self     => $self
            }
        );

        $field =~ s/___\w+$// if $field =~ m/___\w+$/;
        if ( lc($source) eq 'redcap' ) {
            my $meta = field_meta( $arg, $field ) || {};
            $phenotypicFeature->{notes} = join ' /// ',
              ( $field, map { qq/$_=$meta->{$_}/ } @redcap_field_types );
        }

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
      resolve_term_query(
        $term_mapping_cursor, $sex_field, source_value( $arg, $sex_field ) );

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
        next unless defined raw_value( $arg, $field );

        my $treatment;

        my $treatment_name =
          resolve_term_query(
            $term_mapping_cursor, $field, source_value( $arg, $field ) );

        $treatment->{ageAtOnset} = $DEFAULT->{age};

        $treatment->{doseIntervals} = [];
        my $dose_interval;
        my $duration =
          exists $term_mapping_cursor->{duration}{$field}
          ? $term_mapping_cursor->{duration}{$field}
          : undef;
        my $drug_dose =
          exists $term_mapping_cursor->{drugDose}{$field}
          ? $term_mapping_cursor->{drugDose}{$field}
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
            my $duration_value =
              defined source_value( $arg, $duration )
              ? dotify_and_coerce_number( source_value( $arg, $duration ) )
              : -1;
            my $drug_dose_value =
              defined $drug_dose && defined source_value( $arg, $drug_dose )
              ? dotify_and_coerce_number( source_value( $arg, $drug_dose ) )
              : -1;

            $treatment->{cumulativeDose} = {
                unit  => $duration_unit,
                value => $duration_value
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

            # Duration and amount are modeled separately. Keep the duration in
            # cumulativeDose, and emit the actual administered amount from the
            # dedicated dose field when the mapping provides one.
            $dose_interval->{quantity}{value} = $drug_dose_value;
            $dose_interval->{quantity}{unit}  = $drug_unit;
            $dose_interval->{quantity}{referenceRange} =
              $DEFAULT->{referenceRange};

            $dose_interval->{scheduleFrequency} = $DEFAULT->{ontology_term};
            push @{ $treatment->{doseIntervals} }, $dose_interval;
        }

        my $route =
          exists $term_mapping_cursor->{routeOfAdministration}
          { source_value( $arg, $field ) }
          ? $term_mapping_cursor->{routeOfAdministration}
          { source_value( $arg, $field ) }
          : 'oral';
        my $route_query = ucfirst($route) . ' Route of Administration';
        $treatment->{_info} = {
            field     => $field,
            value     => source_value( $arg, $field ),
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
    $item->{_visit}{id} = dotify_and_coerce_number($visit_val);

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
