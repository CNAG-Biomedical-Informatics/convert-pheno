package Convert::Pheno::Tabular::ToBFF;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use JSON::XS;
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);

use Convert::Pheno::Context;
use Convert::Pheno::Mapping::Shared;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Tabular::Record;
use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(map_tabular_individual run_tabular_to_bundle);

my $DEFAULT = get_defaults();
my @REDCAP_META_FIELDS = ( 'Field Label', 'Field Note', 'Field Type' );

sub run_tabular_to_bundle {
    my ( $self, $participant, $context ) = @_;
    my $mapping = _mapping($self);

    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => $mapping->{_compiled}{sourceProfile},
            target_format => 'beacon',
            entities      => $self->{entities} || ['individuals'],
        }
    );

    my $bundle = Convert::Pheno::Model::Bundle->new(
        {
            context  => $context,
            entities => $context->entities,
        }
    );

    my ( $individual, $record ) = _map_individual( $self, $participant, $mapping );
    return $bundle unless defined $individual;

    $bundle->add_entity( individuals => $individual );

    if ( _context_requests_entity( $context, 'biosamples' ) ) {
        for my $biosample (
            @{ _map_biosamples( $self, $record, $mapping, $individual->{id} ) }
          )
        {
            $bundle->add_entity( biosamples => $biosample );
        }
    }

    return $bundle;
}

sub map_tabular_individual {
    my ( $self, $participant ) = @_;
    my ( $individual ) = _map_individual( $self, $participant, _mapping($self) );
    return $individual;
}

sub _map_individual {
    my ( $self, $participant, $mapping ) = @_;
    my $individual_mapping = $mapping->{beacon}{individuals};
    my $record = Convert::Pheno::Tabular::Record->new(
        {
            source      => $mapping->{_compiled}{recordProfile},
            raw         => $participant,
            redcap_dict => $self->{data_redcap_dict},
        }
    );

    _apply_baseline( $self, $record, $mapping );

    my $id_mapping = $individual_mapping->{id};
    my $primary_key = $id_mapping->{source}{primaryKey};
    my $sex_field   = $individual_mapping->{sex}{source}{field};
    return unless _has_value( $record->value($primary_key) );
    return unless _has_value( $record->value($sex_field) );

    my $individual_id = _join_id( $record, $id_mapping );
    my $ctx = {
        self          => $self,
        mapping       => $mapping,
        record        => $record,
        individual_id => $individual_id,
    };

    my $individual = { id => $individual_id };

    _map_diseases( $individual, $individual_mapping->{diseases}, $ctx );
    _map_scalar_term( $individual, 'ethnicity', $individual_mapping->{ethnicity}, $ctx );
    _map_exposures( $individual, $individual_mapping->{exposures}, $ctx );
    _map_scalar_term( $individual, 'geographicOrigin', $individual_mapping->{geographicOrigin}, $ctx );
    _map_info( $individual, $individual_mapping->{info}, $ctx );
    _map_procedures( $individual, $individual_mapping->{interventionsOrProcedures}, $ctx );
    _map_scalar_value( $individual, 'karyotypicSex', $individual_mapping->{karyotypicSex}, $ctx );
    _map_measures( $individual, $individual_mapping->{measures}, $ctx );
    _map_phenotypic_features( $individual, $individual_mapping->{phenotypicFeatures}, $ctx );
    _map_scalar_term( $individual, 'sex', $individual_mapping->{sex}, $ctx );
    _map_treatments( $individual, $individual_mapping->{treatments}, $ctx );

    return ( $individual, $record );
}

sub _mapping {
    my ($self) = @_;
    my $mapping = $self->{data_mapping_file};
    die "The tabular mapping was not compiled\n"
      unless ref($mapping) eq 'HASH'
      && ref( $mapping->{_compiled} ) eq 'HASH';
    return $mapping;
}

sub _apply_baseline {
    my ( $self, $record, $mapping ) = @_;
    my $baseline = $mapping->{records}{baseline} or return 1;
    my $id_field = $mapping->{beacon}{individuals}{id}{source}{primaryKey};
    my $id = $record->value($id_field);
    return 1 unless _has_value($id);

    my $cache = $self->{_mapping_baseline}{ $mapping->{project}{id} }{$id} ||= {};
    for my $field ( @{ $baseline->{sourceFields} } ) {
        my $value = $record->value($field);
        $cache->{$field} = $value
          if _has_value($value) && !exists $cache->{$field};
        $record->set_value( $field, $cache->{$field} )
          if !_has_value($value) && exists $cache->{$field};
    }

    return 1;
}

sub _join_id {
    my ( $record, $mapping ) = @_;
    my $separator = exists $mapping->{separator} ? $mapping->{separator} : ':';
    my $missing = exists $mapping->{missingValue} ? $mapping->{missingValue} : 'NA';
    return join $separator,
      map {
        my $value = $record->value($_);
        _has_value($value) ? $value : $missing;
      } @{ $mapping->{source}{fields} };
}

sub _map_scalar_term {
    my ( $individual, $property, $rule, $ctx ) = @_;
    return 1 unless ref($rule) eq 'HASH';
    return 1 unless _source_matches( $rule->{source}, $ctx->{record} );

    my $term = _map_term( $rule->{target}, $rule->{source}{field}, $ctx );
    $individual->{$property} = $term if defined $term;
    return 1;
}

sub _map_scalar_value {
    my ( $individual, $property, $rule, $ctx ) = @_;
    return 1 unless ref($rule) eq 'HASH';
    return 1 unless _source_matches( $rule->{source}, $ctx->{record} );

    my $value = _resolve_value( $rule->{target}, $rule->{source}{field}, $ctx );
    $individual->{$property} = $value if defined $value;
    return 1;
}

sub _map_diseases {
    my ( $individual, $rules, $ctx ) = @_;
    for my $rule ( @{ $rules || [] } ) {
        next unless _source_matches( $rule->{source}, $ctx->{record} );
        my $field  = $rule->{source}{field};
        my $target = $rule->{target};
        my $code   = _map_term( $target->{diseaseCode}, $field, $ctx );
        next unless defined $code;

        my $disease = {
            diseaseCode => $code,
            ageOfOnset  => exists $target->{ageOfOnset}
            ? _map_age( _resolve_value( $target->{ageOfOnset}, $field, $ctx ) )
            : _clone( $DEFAULT->{age} ),
            severity => _clone( $DEFAULT->{ontology_term} ),
            stage    => _clone( $DEFAULT->{ontology_term} ),
        };

        if ( exists $target->{familyHistory} ) {
            my $value = _resolve_value( $target->{familyHistory}, $field, $ctx );
            $disease->{familyHistory} = convert2boolean($value)
              if defined $value;
        }

        _add_visit( $disease, $ctx );
        push @{ $individual->{diseases} }, $disease;
    }
    return 1;
}

sub _map_exposures {
    my ( $individual, $rules, $ctx ) = @_;
    for my $rule ( @{ $rules || [] } ) {
        next unless _source_matches( $rule->{source}, $ctx->{record} );
        my $field  = $rule->{source}{field};
        my $target = $rule->{target};
        my $code   = _map_term( $target->{exposureCode}, $field, $ctx );
        next unless defined $code;

        my $source_value = $ctx->{record}->value($field);
        my $value = exists $target->{value}
          ? _resolve_value( $target->{value}, $field, $ctx )
          : $source_value;

        my $exposure = {
            exposureCode => $code,
            ageAtExposure => exists $target->{ageAtExposure}
            ? _map_age( _resolve_value( $target->{ageAtExposure}, $field, $ctx ) )
            : _clone( $DEFAULT->{age} ),
            unit => _map_term( $target->{unit}, $field, $ctx ),
            value => defined $value && looks_like_number($value)
            ? dotify_and_coerce_number($value)
            : -1,
            date => exists $target->{date}
            ? _resolve_value( $target->{date}, $field, $ctx )
            : $DEFAULT->{date},
            duration => exists $target->{duration}
            ? _resolve_value( $target->{duration}, $field, $ctx )
            : $DEFAULT->{duration},
        };
        $exposure->{_info} = $field if _source_info_enabled( $ctx->{self} );
        _add_visit( $exposure, $ctx );
        push @{ $individual->{exposures} }, $exposure;
    }
    return 1;
}

sub _map_info {
    my ( $individual, $rule, $ctx ) = @_;
    $rule ||= { source => { fields => [] } };
    $individual->{info} ||= {};

    for my $field ( @{ $rule->{source}{fields} || [] } ) {
        next unless defined $ctx->{record}->working_value($field);
        $individual->{info}{$field} = $ctx->{record}->value($field);

        my $meta = $ctx->{record}->field_meta($field);
        if ( ref($meta) eq 'HASH' && exists $meta->{'Field Label'} ) {
            $individual->{info}{objects}{ $field . '_obj' } = {
                value => dotify_and_coerce_number( $ctx->{record}->value($field) ),
                map { $_ => $meta->{$_} } @REDCAP_META_FIELDS,
            };
        }
    }

    if ( exists $rule->{target}{ageRange} ) {
        my $value = _resolve_value( $rule->{target}{ageRange}, undef, $ctx );
        my $age = _map_age($value);
        $individual->{info}{ageRange} = $age->{ageRange}
          if ref($age) eq 'HASH' && exists $age->{ageRange};
    }

    $individual->{info}{convertPheno} = $ctx->{self}{convertPheno}
      if !$ctx->{self}{test} && defined $ctx->{self}{convertPheno};

    my $mapping = $ctx->{mapping};
    $individual->{info}{project} = {
        id       => $mapping->{project}{id},
        source   => $mapping->{_compiled}{sourceProfile},
        ontology => $mapping->{defaults}{ontology},
        version  => $mapping->{project}{version},
    };
    $individual->{info}{project}{description} = $mapping->{project}{description}
      if defined $mapping->{project}{description};

    if ( _source_info_enabled( $ctx->{self} ) ) {
        my $key = $mapping->{_compiled}{recordProfile} eq 'redcap'
          ? 'REDCap_columns'
          : 'CSV_columns';
        $individual->{info}{$key} = $ctx->{record}->columns_snapshot;
    }

    return 1;
}

sub _map_procedures {
    my ( $individual, $rules, $ctx ) = @_;
    for my $rule ( @{ $rules || [] } ) {
        next unless _source_matches( $rule->{source}, $ctx->{record} );
        my $field  = $rule->{source}{field};
        my $target = $rule->{target};
        my $code   = _map_term( $target->{procedureCode}, $field, $ctx );
        next unless defined $code;

        my $procedure = {
            procedureCode => $code,
            ageAtProcedure => exists $target->{ageAtProcedure}
            ? _map_age( _resolve_value( $target->{ageAtProcedure}, $field, $ctx ) )
            : _clone( $DEFAULT->{age} ),
            bodySite => exists $target->{bodySite}
            ? _map_term( $target->{bodySite}, $field, $ctx )
            : _clone( $DEFAULT->{ontology_term} ),
            dateOfProcedure => _mapped_date(
                $target->{dateOfProcedure}, $field, $ctx
            ),
        };
        $procedure->{_info} = $field if _source_info_enabled( $ctx->{self} );
        _add_visit( $procedure, $ctx );
        push @{ $individual->{interventionsOrProcedures} }, $procedure;
    }
    return 1;
}

sub _map_measures {
    my ( $individual, $rules, $ctx ) = @_;
    for my $rule ( @{ $rules || [] } ) {
        my $measure = _map_measure_rule( $rule, $ctx );
        push @{ $individual->{measures} }, $measure if defined $measure;
    }
    return 1;
}

sub _map_measure_rule {
    my ( $rule, $ctx ) = @_;
    return unless _source_matches( $rule->{source}, $ctx->{record} );
    my $field  = $rule->{source}{field};
    my $target = $rule->{target};
    my $value  = $ctx->{record}->working_value($field);
    my $field_note = $ctx->{record}->field_note($field);

    if ( defined $value && $value =~ / \- / ) {
        ( $value, $field_note ) = split / \- /, $value, 2;
    }

    my $quantity_rule = $target->{measurementValue}{quantity};
    my $unit = _map_term(
        $quantity_rule->{unit},
        $field,
        $ctx,
        field_note => $field_note,
    );
    my $mapped_value = exists $quantity_rule->{value}
      ? _resolve_value( $quantity_rule->{value}, $field, $ctx )
      : $value;

    my $reference_range = _reference_range(
        $quantity_rule->{referenceRange}, $unit, $field, $ctx
    );

    my $measure = {
        assayCode => _map_term( $target->{assayCode}, $field, $ctx ),
        date      => $DEFAULT->{date},
        measurementValue => {
            quantity => {
                unit           => $unit,
                value          => dotify_and_coerce_number($mapped_value),
                referenceRange => $reference_range,
            },
        },
    };
    return unless defined $measure->{assayCode};

    if ( exists $target->{procedure} ) {
        $measure->{procedure} = {
            procedureCode => _map_term(
                $target->{procedure}{procedureCode}, $field, $ctx
            ),
        };
    }

    if ( $ctx->{mapping}{_compiled}{recordProfile} eq 'redcap' ) {
        my $meta = $ctx->{record}->field_meta($field) || {};
        $measure->{notes} = join ' /// ', $field,
          map { qq/$_=$meta->{$_}/ } @REDCAP_META_FIELDS;
    }

    _add_visit( $measure, $ctx );
    return $measure;
}

sub _reference_range {
    my ( $rule, $unit, $field, $ctx ) = @_;
    return _clone( $DEFAULT->{referenceRange} ) unless ref($rule) eq 'HASH';

    if ( ( $rule->{from} || q{} ) eq 'redcapDictionary' ) {
        return map_reference_range(
            {
                unit        => $unit,
                redcap_dict => $ctx->{self}{data_redcap_dict},
                field       => $field,
                source      => 'redcap',
            }
        );
    }

    return map_reference_range_csv(
        $unit,
        { low => $rule->{low}, high => $rule->{high} },
    );
}

sub _map_phenotypic_features {
    my ( $individual, $rules, $ctx ) = @_;
    for my $rule ( @{ $rules || [] } ) {
        next unless _source_matches( $rule->{source}, $ctx->{record} );
        my $field = $rule->{source}{field};
        my $raw   = $ctx->{record}->working_value($field);
        next unless defined $raw && $raw ne q{};

        my $feature = {
            excluded_ori => dotify_and_coerce_number($raw),
            excluded => looks_like_number($raw)
            ? ( $raw ? JSON::XS::false : JSON::XS::true )
            : JSON::XS::false,
            featureType => _map_term( $rule->{target}{featureType}, $field, $ctx ),
        };
        next unless defined $feature->{featureType};

        if ( $ctx->{mapping}{_compiled}{recordProfile} eq 'redcap' ) {
            ( my $dictionary_field = $field ) =~ s/___\w+\z//;
            my $meta = $ctx->{record}->field_meta($dictionary_field) || {};
            $feature->{notes} = join ' /// ', $dictionary_field,
              map { qq/$_=$meta->{$_}/ } @REDCAP_META_FIELDS;
        }

        _add_visit( $feature, $ctx );
        push @{ $individual->{phenotypicFeatures} }, $feature;
    }
    return 1;
}

sub _map_treatments {
    my ( $individual, $rules, $ctx ) = @_;
    for my $rule ( @{ $rules || [] } ) {
        next unless _source_matches( $rule->{source}, $ctx->{record} );
        my $field  = $rule->{source}{field};
        my $target = $rule->{target};
        my $code   = _map_term( $target->{treatmentCode}, $field, $ctx );
        next unless defined $code;

        my $treatment = {
            treatmentCode => $code,
            ageAtOnset => exists $target->{ageAtOnset}
            ? _map_age( _resolve_value( $target->{ageAtOnset}, $field, $ctx ) )
            : _clone( $DEFAULT->{age} ),
        };

        $treatment->{routeOfAdministration} = _map_term(
            $target->{routeOfAdministration}, $field, $ctx
          )
          if exists $target->{routeOfAdministration};

        $treatment->{cumulativeDose} = _map_quantity(
            $target->{cumulativeDose}, $field, $ctx, 0
          )
          if exists $target->{cumulativeDose};

        if ( exists $target->{doseIntervals} ) {
            my $quantity = _map_quantity(
                $target->{doseIntervals}{quantity}, $field, $ctx, 1
            );
            $treatment->{doseIntervals} = [
                {
                    interval          => _clone( $DEFAULT->{interval} ),
                    quantity          => $quantity,
                    scheduleFrequency => _clone( $DEFAULT->{ontology_term} ),
                }
            ];
        }

        if ( _source_info_enabled( $ctx->{self} ) ) {
            $treatment->{_info} = {
                field     => $field,
                value     => $ctx->{record}->value($field),
                drug_name => $code->{label},
                route => exists $treatment->{routeOfAdministration}
                ? $treatment->{routeOfAdministration}{label}
                : undef,
            };
        }

        _add_visit( $treatment, $ctx );
        push @{ $individual->{treatments} }, $treatment;
    }
    return 1;
}

sub _map_quantity {
    my ( $rule, $field, $ctx, $with_range ) = @_;
    my $value = exists $rule->{value}
      ? _resolve_value( $rule->{value}, $field, $ctx )
      : $ctx->{record}->value($field);
    $value = defined $value && looks_like_number($value)
      ? dotify_and_coerce_number($value)
      : -1;

    my $unit = _map_term( $rule->{unit}, $field, $ctx );
    my $quantity = { value => $value, unit => $unit };
    $quantity->{referenceRange} = _clone( $DEFAULT->{referenceRange} )
      if $with_range;
    return $quantity;
}

sub _map_biosamples {
    my ( $self, $record, $mapping, $individual_id ) = @_;
    my $config = $mapping->{beacon}{biosamples};
    return [] unless ref($config) eq 'HASH';

    my $ctx = {
        self          => $self,
        mapping       => $mapping,
        record        => $record,
        individual_id => $individual_id,
    };
    my @biosamples;

    for my $rule ( @{ $config->{mappings} || [] } ) {
        next unless _source_matches( $rule->{source}, $record );
        my $field  = $rule->{source}{field};
        my $target = $rule->{target};
        my $id = _resolve_value( $target->{id}, $field, $ctx );
        next unless _has_value($id);

        my $biosample = {
            id               => "$id",
            biosampleStatus  => _map_term( $target->{biosampleStatus}, $field, $ctx ),
            sampleOriginType => _map_term( $target->{sampleOriginType}, $field, $ctx ),
        };
        $biosample->{individualId} = exists $target->{individualId}
          ? _resolve_value( $target->{individualId}, $field, $ctx )
          : $individual_id;

        for my $property (qw(collectionDate notes)) {
            next unless exists $target->{$property};
            my $value = _resolve_value( $target->{$property}, $field, $ctx );
            next unless defined $value;
            $biosample->{$property} = $property eq 'collectionDate'
              ? convert_date_to_iso8601($value)
              : $value;
        }

        for my $property (qw(sampleOriginDetail)) {
            $biosample->{$property} = _map_term( $target->{$property}, $field, $ctx )
              if exists $target->{$property};
        }

        if ( exists $target->{obtentionProcedure} ) {
            $biosample->{obtentionProcedure} = {
                procedureCode => _map_term(
                    $target->{obtentionProcedure}{procedureCode}, $field, $ctx
                ),
            };
        }

        for my $measure_rule ( @{ $target->{measurements} || [] } ) {
            my $measure = _map_measure_rule( $measure_rule, $ctx );
            push @{ $biosample->{measurements} }, $measure if defined $measure;
        }

        if ( exists $target->{info} ) {
            for my $info_field ( @{ $target->{info}{sourceFields} } ) {
                $biosample->{info}{$info_field} = $record->value($info_field)
                  if defined $record->raw_value($info_field);
            }
        }

        if ( _source_info_enabled($self) ) {
            my $key = $mapping->{_compiled}{recordProfile} eq 'redcap'
              ? 'REDCap_columns'
              : 'CSV_columns';
            $biosample->{info}{$key} = $record->columns_snapshot;
        }
        $biosample->{info}{convertPheno} = $self->{convertPheno}
          if !$self->{test} && defined $self->{convertPheno};

        push @biosamples, $biosample;
    }

    return \@biosamples;
}

sub _map_term {
    my ( $rule, $source_field, $ctx, %arg ) = @_;
    return unless ref($rule) eq 'HASH';
    return _clone( $rule->{term} ) if exists $rule->{term};

    my $query_rule = $rule->{query};
    my $query;
    if ( exists $query_rule->{literal} ) {
        $query = $query_rule->{literal};
    }
    elsif ( $query_rule->{from} eq 'field' ) {
        $query = $source_field;
    }
    elsif ( $query_rule->{from} eq 'fieldNote' ) {
        $query = exists $arg{field_note}
          ? $arg{field_note}
          : $ctx->{record}->field_note($source_field);
    }
    else {
        $query = $ctx->{record}->value($source_field);
    }
    return _clone( $DEFAULT->{ontology_term} )
      unless defined $query && !ref $query;

    return _clone( $rule->{terms}{$query} )
      if exists $rule->{terms} && exists $rule->{terms}{$query};
    $query = $query_rule->{aliases}{$query}
      if exists $query_rule->{aliases}
      && exists $query_rule->{aliases}{$query};

    return map_ontology_term(
        {
            query    => $query,
            column   => 'label',
            ontology => $rule->{ontology} || $ctx->{mapping}{defaults}{ontology},
            self     => $ctx->{self},
        }
    );
}

sub _resolve_value {
    my ( $rule, $source_field, $ctx ) = @_;
    return unless ref($rule) eq 'HASH';
    return $rule->{literal} if exists $rule->{literal};
    return $ctx->{record}->value( $rule->{sourceField} )
      if exists $rule->{sourceField};
    return $ctx->{individual_id}
      if ( $rule->{from} || q{} ) eq 'individualId';
    return $ctx->{record}->value($source_field);
}

sub _source_matches {
    my ( $source, $record ) = @_;
    my $field = $source->{field};
    my $working = $record->working_value($field);
    return 0 unless defined $working;

    my $when = $source->{when};
    return 1 unless ref($when) eq 'HASH';
    my $value = $record->value($field);
    return 0 if $when->{nonEmpty} && !_has_value($value);
    return 0
      if exists $when->{values}
      && !_value_in( $value, $when->{values} );
    return 0
      if exists $when->{notValues}
      && _value_in( $value, $when->{notValues} );
    return 1;
}

sub _value_in {
    my ( $value, $values ) = @_;
    return 0 unless defined $value;
    return scalar grep { defined $_ && "$value" eq "$_" } @{$values};
}

sub _map_age {
    my ($value) = @_;
    return _clone( $DEFAULT->{age} ) unless _has_value($value);
    return map_age_range($value);
}

sub _mapped_date {
    my ( $rule, $field, $ctx ) = @_;
    return $DEFAULT->{date} unless ref($rule) eq 'HASH';
    my $value = _resolve_value( $rule, $field, $ctx );
    return $DEFAULT->{date} unless _has_value($value);
    return convert_date_to_iso8601($value);
}

sub _add_visit {
    my ( $item, $ctx ) = @_;
    my $visit = $ctx->{mapping}{records}{visitId} or return 1;
    my $value = $ctx->{record}->value( $visit->{sourceField} );
    return 1 unless defined $value;

    $item->{_visit}{id} = dotify_and_coerce_number($value);
    my $composite = join '.', grep { length } $ctx->{individual_id}, $value;
    $item->{_visit}{composite} = $composite;
    $item->{_visit}{occurrence_id} = allocate_surrogate_integer(
        $ctx->{self},
        'bff_visit_occurrence_id',
        $composite,
    );
    return 1;
}

sub _context_requests_entity {
    my ( $context, $entity ) = @_;
    return scalar grep { $_ eq $entity } @{ $context->entities };
}

sub _source_info_enabled {
    my ($self) = @_;
    return !exists $self->{source_info} || $self->{source_info};
}

sub _has_value {
    my ($value) = @_;
    return defined $value && !ref($value) && length "$value";
}

sub _clone {
    my ($value) = @_;
    return ref($value) ? dclone($value) : $value;
}

1;
