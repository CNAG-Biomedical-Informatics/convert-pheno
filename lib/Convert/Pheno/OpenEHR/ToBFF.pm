package Convert::Pheno::OpenEHR::ToBFF;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use JSON::PP ();

use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(
  do_openehr2bff
  run_openehr_to_bundle
  extract_openehr_compositions
  resolve_openehr_embedded_patient_id
  resolve_openehr_patient_id
);
my $DEFAULT = get_defaults();

sub do_openehr2bff {
    my ( $self, $data ) = @_;
    my $bundle = run_openehr_to_bundle( $self, $data, $self->{conversion_context} );
    return $bundle->primary_entity('individuals');
}

sub run_openehr_to_bundle {
    my ( $self, $data, $context ) = @_;

    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => 'openehr',
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

    my $compositions = extract_openehr_compositions($data);
    _validate_compositions($compositions);

    my $id  = resolve_openehr_patient_id( $self, $data, $compositions );
    my $sex = _resolve_sex($compositions);
    my $mapped = _map_first_class_arrays($compositions);

    die "The input <openEHR> data could not be resolved to a patient id; please provide one composition set with a stable patient identifier in the payload or envelope\n"
      unless defined $id && length $id;
    die "The input <openEHR> data could not be resolved to <sex>; please include a demographic composition carrying administrative gender\n"
      unless defined $sex;

    my $individual = {
        id   => $id,
        sex  => $sex,
        info => {
            openehr => {
                compositions => $compositions,
            },
        },
    };

    for my $field ( qw(diseases measures phenotypicFeatures interventionsOrProcedures treatments) ) {
        next unless exists $mapped->{$field} && @{ $mapped->{$field} };
        $individual->{$field} = $mapped->{$field};
    }

    unless ( $self->{test} ) {
        $individual->{info}{convertPheno} = $self->{convertPheno}
          if defined $self->{convertPheno};
    }

    $bundle->add_entity( individuals => $individual );
    return $bundle;
}

sub extract_openehr_compositions {
    my ($data) = @_;

    return [] unless defined $data;

    if ( ref($data) eq 'HASH' && exists $data->{compositions} ) {
        return $data->{compositions} if ref( $data->{compositions} ) eq 'ARRAY';
        return [ $data->{compositions} ];
    }

    return $data if ref($data) eq 'ARRAY';
    return [$data];
}

sub _validate_compositions {
    my ($compositions) = @_;
    die "The input <openEHR> payload does not contain any compositions\n"
      unless defined $compositions && ref($compositions) eq 'ARRAY' && @{$compositions};

    for my $composition ( @{$compositions} ) {
        die "Each openEHR input item must be a JSON object\n"
          unless ref($composition) eq 'HASH';
        die "Each openEHR input item must be a canonical <COMPOSITION> JSON document\n"
          unless defined $composition->{_type} && $composition->{_type} eq 'COMPOSITION';
    }

    return 1;
}

sub resolve_openehr_patient_id {
    my ( $self, $data, $compositions ) = @_;

    $compositions ||= extract_openehr_compositions($data);

    if ( ref($data) eq 'HASH' ) {
        return $data->{patient}{id}
          if exists $data->{patient}
          && ref( $data->{patient} ) eq 'HASH'
          && defined $data->{patient}{id}
          && length $data->{patient}{id};

        return $data->{id}
          if defined $data->{id} && !ref( $data->{id} ) && length $data->{id};

        my $ehr_status_subject_id = _extract_party_proxy_external_ref_id( $data->{ehr_status}{subject} )
          if exists $data->{ehr_status} && ref( $data->{ehr_status} ) eq 'HASH';
        return $ehr_status_subject_id
          if defined $ehr_status_subject_id && length $ehr_status_subject_id;

        my $ehr_id = _extract_identifier_value( $data->{ehr_id} );
        return $ehr_id if defined $ehr_id && length $ehr_id;
    }

    if ( ref($compositions) eq 'ARRAY' ) {
        for my $composition ( @{$compositions} ) {
            my $subject_id = _find_party_self_external_ref_id($composition);
            return $subject_id if defined $subject_id && length $subject_id;
        }
    }

    return;
}

sub resolve_openehr_embedded_patient_id {
    my ( $data, $compositions ) = @_;

    $compositions ||= extract_openehr_compositions($data);

    if ( ref($data) eq 'HASH' ) {
        my $ehr_status_subject_id = _extract_party_proxy_external_ref_id( $data->{ehr_status}{subject} )
          if exists $data->{ehr_status} && ref( $data->{ehr_status} ) eq 'HASH';
        return $ehr_status_subject_id
          if defined $ehr_status_subject_id && length $ehr_status_subject_id;
    }

    if ( ref($compositions) eq 'ARRAY' ) {
        for my $composition ( @{$compositions} ) {
            my $subject_id = _find_party_self_external_ref_id($composition);
            return $subject_id if defined $subject_id && length $subject_id;
        }
    }

    return;
}

sub _extract_identifier_value {
    my ($value) = @_;
    return unless defined $value;

    return $value
      if !ref($value) && length $value;

    return $value->{value}
      if ref($value) eq 'HASH'
      && defined $value->{value}
      && !ref( $value->{value} )
      && length $value->{value};

    return;
}

sub _extract_party_proxy_external_ref_id {
    my ($party) = @_;
    return unless ref($party) eq 'HASH';
    return unless exists $party->{external_ref} && ref( $party->{external_ref} ) eq 'HASH';
    return _extract_identifier_value( $party->{external_ref}{id} );
}

sub _find_party_self_external_ref_id {
    my ($node) = @_;
    return unless defined $node;

    if ( ref($node) eq 'HASH' ) {
        if ( ( $node->{_type} || '' ) eq 'PARTY_SELF' ) {
            my $id = _extract_party_proxy_external_ref_id($node);
            return $id if defined $id && length $id;
        }

        for my $value ( values %{$node} ) {
            my $id = _find_party_self_external_ref_id($value);
            return $id if defined $id;
        }

        return;
    }

    if ( ref($node) eq 'ARRAY' ) {
        for my $entry ( @{$node} ) {
            my $id = _find_party_self_external_ref_id($entry);
            return $id if defined $id;
        }
    }

    return;
}

sub _resolve_sex {
    my ($compositions) = @_;

    for my $composition ( @{$compositions} ) {
        my $code = _find_gender_code($composition);
        next unless defined $code;
        return _map_gender_code($code);
    }

    return;
}

sub _find_gender_code {
    my ($node) = @_;
    return unless defined $node;

    if ( ref($node) eq 'HASH' ) {
        if ( exists $node->{name}
            && ref( $node->{name} ) eq 'HASH'
            && defined $node->{name}{value}
            && $node->{name}{value} =~ /Administratives Geschlecht/i
            && exists $node->{value}
            && ref( $node->{value} ) eq 'HASH'
            && exists $node->{value}{defining_code}
            && ref( $node->{value}{defining_code} ) eq 'HASH'
            && defined $node->{value}{defining_code}{code_string} )
        {
            return lc $node->{value}{defining_code}{code_string};
        }

        for my $value ( values %{$node} ) {
            my $code = _find_gender_code($value);
            return $code if defined $code;
        }

        return;
    }

    if ( ref($node) eq 'ARRAY' ) {
        for my $entry ( @{$node} ) {
            my $code = _find_gender_code($entry);
            return $code if defined $code;
        }
    }

    return;
}

sub _map_gender_code {
    my ($code) = @_;
    return unless defined $code;

    return { %{ $DEFAULT->{sex}{male} } } if $code eq 'male';
    return { %{ $DEFAULT->{sex}{female} } } if $code eq 'female';

    return;
}

sub _map_first_class_arrays {
    my ($compositions) = @_;

    my %mapped = (
        diseases                  => [],
        measures                  => [],
        phenotypicFeatures        => [],
        interventionsOrProcedures => [],
        treatments                => [],
    );

    for my $composition ( @{$compositions} ) {
        _walk_nodes(
            $composition,
            sub {
                my ($node) = @_;
                return unless ref($node) eq 'HASH';
                return unless defined $node->{archetype_node_id};

                if ( $node->{archetype_node_id} eq 'openEHR-EHR-OBSERVATION.lab_test-result.v1'
                    || $node->{archetype_node_id} eq 'openEHR-EHR-OBSERVATION.laboratory_test_result.v1' )
                {
                    my $measure = _map_lab_measure($node);
                    push @{ $mapped{measures} }, $measure if defined $measure;
                    return;
                }

                if ( $node->{archetype_node_id} eq 'openEHR-EHR-OBSERVATION.body_temperature.v2' ) {
                    my $measure = _map_temperature_measure($node);
                    push @{ $mapped{measures} }, $measure if defined $measure;
                    return;
                }

                if ( $node->{archetype_node_id} eq 'openEHR-EHR-OBSERVATION.symptom_sign_screening.v0' ) {
                    my $feature = _map_phenotypic_feature($node);
                    push @{ $mapped{phenotypicFeatures} }, $feature if defined $feature;
                    return;
                }

                if ( $node->{archetype_node_id} eq 'openEHR-EHR-EVALUATION.problem_diagnosis.v1' ) {
                    my $disease = _map_disease($node);
                    push @{ $mapped{diseases} }, $disease if defined $disease;
                    return;
                }

                if ( $node->{archetype_node_id} eq 'openEHR-EHR-ACTION.procedure.v1' ) {
                    my $procedure = _map_procedure($node);
                    push @{ $mapped{interventionsOrProcedures} }, $procedure
                      if defined $procedure;
                    return;
                }

                if ( $node->{archetype_node_id} eq 'openEHR-EHR-ACTION.medication.v1' ) {
                    my $treatment = _map_treatment($node);
                    push @{ $mapped{treatments} }, $treatment if defined $treatment;
                    return;
                }
            }
        );
    }

    return \%mapped;
}

sub _walk_nodes {
    my ( $node, $callback ) = @_;
    return unless defined $node;

    if ( ref($node) eq 'HASH' ) {
        $callback->($node);
        _walk_nodes( $_, $callback ) for values %{$node};
        return;
    }

    if ( ref($node) eq 'ARRAY' ) {
        _walk_nodes( $_, $callback ) for @{$node};
    }

    return;
}

sub _map_lab_measure {
    my ($node) = @_;

    my $assay =
         _find_first_element_value( $node, 'Test result name', 'Test name', 'Analyte name' )
      || _find_first_named_cluster_code( $node, 'Result group' )
      || _term_from_text( _node_name($node), $node );

    my $quantity = _find_first_quantity_value( $node, 'Result value', 'Temperatur' );
    my $time     = _find_first_datetime_value($node);

    return unless defined $assay && defined $quantity;

    my $measure = {
        _info => {
            openEHR => $node,
        },
    };

    $measure->{assayCode} = $assay if defined $assay;
    if ( defined $quantity ) {
        $measure->{measurementValue} = {
            quantity => $quantity,
        };
    }
    $measure->{timeObserved} = { timestamp => $time } if defined $time;

    return $measure;
}

sub _map_temperature_measure {
    my ($node) = @_;
    my $quantity = _find_first_quantity_value( $node, 'Temperatur' );
    my $time     = _find_first_datetime_value($node);

    return unless defined $quantity;

    my $measure = {
        assayCode => _term_from_text( _node_name($node), $node ),
        measurementValue => {
            quantity => $quantity,
        },
        _info => {
            openEHR => $node,
        },
    };

    $measure->{timeObserved} = { timestamp => $time } if defined $time;
    return $measure;
}

sub _map_phenotypic_feature {
    my ($node) = @_;

    my $feature_name =
         _find_first_text_value( $node, 'Bezeichnung des Symptoms oder Anzeichens.' )
      || _node_name($node);
    return unless defined $feature_name;

    my $presence = _find_first_element_value( $node, 'Vorhanden?' );
    my $excluded = _excluded_from_presence($presence);

    my $feature = {
        featureType => _term_from_text( $feature_name, $node ),
        _info       => {
            openEHR => $node,
        },
    };

    $feature->{excluded} = $excluded if defined $excluded;

    return $feature;
}

sub _map_disease {
    my ($node) = @_;
    my $code = _find_first_element_value( $node, 'Problem/Diagnosis name' );
    return unless defined $code;

    return {
        diseaseCode => $code,
        _info       => {
            openEHR => $node,
        },
    };
}

sub _map_procedure {
    my ($node) = @_;
    my $code = _find_first_element_value( $node, 'Procedure name' );
    return unless defined $code;

    my $procedure = {
        procedureCode => $code,
        _info         => {
            openEHR => $node,
        },
    };

    my $body_site = _find_first_element_value( $node, 'Body site' );
    $procedure->{bodySite} = $body_site if defined $body_site;

    my $date = _extract_date( $node->{time}{value} );
    $procedure->{dateOfProcedure} = $date if defined $date;

    return $procedure;
}

sub _map_treatment {
    my ($node) = @_;

    my $code =
         _find_first_element_value( $node, 'Name' )
      || _find_first_element_value( $node, 'Medication item', 'Immunisation item' );
    return unless defined $code;

    my $treatment = {
        treatmentCode => $code,
        _info         => {
            openEHR => $node,
        },
    };

    my $route = _find_first_element_value( $node, 'Route' );
    $treatment->{routeOfAdministration} = $route if defined $route;

    return $treatment;
}

sub _find_first_element_value {
    my ( $node, @names ) = @_;
    my %wanted = map { $_ => 1 } @names;
    my $found;

    _walk_nodes(
        $node,
        sub {
            my ($cursor) = @_;
            return if defined $found;
            return unless ref($cursor) eq 'HASH';
            return unless ( $cursor->{_type} || '' ) eq 'ELEMENT';

            my $name = _node_name($cursor);
            return unless defined $name && $wanted{$name};

            $found = _term_from_value( $cursor->{value}, $cursor );
        }
    );

    return $found;
}

sub _find_first_text_value {
    my ( $node, @names ) = @_;
    my %wanted = map { $_ => 1 } @names;
    my $found;

    _walk_nodes(
        $node,
        sub {
            my ($cursor) = @_;
            return if defined $found;
            return unless ref($cursor) eq 'HASH';
            return unless ( $cursor->{_type} || '' ) eq 'ELEMENT';

            my $name = _node_name($cursor);
            return unless defined $name && $wanted{$name};
            return unless ref( $cursor->{value} ) eq 'HASH';
            return unless defined $cursor->{value}{value};

            $found = $cursor->{value}{value};
        }
    );

    return $found;
}

sub _find_first_quantity_value {
    my ( $node, @names ) = @_;
    my %wanted = map { $_ => 1 } @names;
    my $found;

    _walk_nodes(
        $node,
        sub {
            my ($cursor) = @_;
            return if defined $found;
            return unless ref($cursor) eq 'HASH';
            return unless ( $cursor->{_type} || '' ) eq 'ELEMENT';

            my $name = _node_name($cursor);
            return unless defined $name && $wanted{$name};
            return unless ref( $cursor->{value} ) eq 'HASH';
            return unless ( $cursor->{value}{_type} || '' ) eq 'DV_QUANTITY';

            $found = _quantity_from_dv_quantity( $cursor->{value} );
        }
    );

    return $found;
}

sub _find_first_named_cluster_code {
    my ( $node, $cluster_name ) = @_;
    my $found;

    _walk_nodes(
        $node,
        sub {
            my ($cursor) = @_;
            return if defined $found;
            return unless ref($cursor) eq 'HASH';
            return unless ( $cursor->{_type} || '' ) eq 'CLUSTER';
            return unless defined _node_name($cursor) && _node_name($cursor) eq $cluster_name;

            if ( ref( $cursor->{items} ) eq 'ARRAY' ) {
                for my $item ( @{ $cursor->{items} } ) {
                    next unless ref($item) eq 'HASH';
                    my $name = $item->{name};
                    next unless ref($name) eq 'HASH';
                    next unless ( $name->{_type} || '' ) eq 'DV_CODED_TEXT';
                    $found = _term_from_value( $name, $item );
                    last if defined $found;
                }
            }
        }
    );

    return $found;
}

sub _find_first_datetime_value {
    my ($node) = @_;
    my $found;

    _walk_nodes(
        $node,
        sub {
            my ($cursor) = @_;
            return if defined $found;
            return unless ref($cursor) eq 'HASH';

            if ( exists $cursor->{time}
                && ref( $cursor->{time} ) eq 'HASH'
                && defined $cursor->{time}{value} )
            {
                $found = $cursor->{time}{value};
                return;
            }

            if ( exists $cursor->{origin}
                && ref( $cursor->{origin} ) eq 'HASH'
                && defined $cursor->{origin}{value} )
            {
                $found = $cursor->{origin}{value};
                return;
            }
        }
    );

    return $found;
}

sub _term_from_value {
    my ( $value, $source_node ) = @_;
    return unless defined $value;

    if ( ref($value) eq 'HASH' ) {
        if ( defined $value->{value} ) {
            my %term = ( label => $value->{value} );
            my $id = _term_id_from_defining_code( $value->{defining_code} );
            $id ||= _synthetic_term_id( $value->{value}, $source_node );
            $term{id} = $id if defined $id;
            return \%term;
        }
        return;
    }

    return {
        id    => _synthetic_term_id( $value, $source_node ),
        label => $value,
      }
      if !ref($value) && length $value;
    return;
}

sub _term_from_text {
    my ( $text, $source_node ) = @_;
    return unless defined $text && length $text;
    return {
        id    => _synthetic_term_id( $text, $source_node ),
        label => $text,
    };
}

sub _term_id_from_defining_code {
    my ($code) = @_;
    return unless ref($code) eq 'HASH';
    return unless defined $code->{code_string};
    return unless ref( $code->{terminology_id} ) eq 'HASH';
    return unless defined $code->{terminology_id}{value};

    my $terminology = $code->{terminology_id}{value};
    return if $terminology eq 'local' || $terminology eq 'openehr';

    return $terminology . ':' . $code->{code_string};
}

sub _quantity_from_dv_quantity {
    my ($value) = @_;
    return unless ref($value) eq 'HASH';
    return unless defined $value->{magnitude};

    my %quantity = ( value => $value->{magnitude} );
    $quantity{unit} = { label => $value->{units} }
      if defined $value->{units} && length $value->{units};

    if ( ref( $value->{normal_range} ) eq 'HASH' ) {
        my %range;
        if ( ref( $value->{normal_range}{lower} ) eq 'HASH'
            && defined $value->{normal_range}{lower}{magnitude} )
        {
            $range{low} = $value->{normal_range}{lower}{magnitude};
            $range{unit} = { label => $value->{normal_range}{lower}{units} }
              if defined $value->{normal_range}{lower}{units};
        }
        if ( ref( $value->{normal_range}{upper} ) eq 'HASH'
            && defined $value->{normal_range}{upper}{magnitude} )
        {
            $range{high} = $value->{normal_range}{upper}{magnitude};
            $range{unit} = { label => $value->{normal_range}{upper}{units} }
              if defined $value->{normal_range}{upper}{units} && !exists $range{unit};
        }
        $quantity{referenceRange} = \%range if %range;
    }

    return \%quantity;
}

sub _excluded_from_presence {
    my ($presence) = @_;
    return unless defined $presence && ref($presence) eq 'HASH';

    return JSON::PP::true() if defined $presence->{label}
      && $presence->{label} =~ /Nicht vorhanden/i;
    return JSON::PP::false() if defined $presence->{label}
      && ( $presence->{label} =~ /Vorhanden/i || $presence->{label} =~ /Present/i );

    return;
}

sub _synthetic_term_id {
    my ( $text, $source_node ) = @_;
    return unless defined $text && length $text;

    my @parts = ('openEHR');
    if ( ref($source_node) eq 'HASH' ) {
        push @parts, $source_node->{archetype_node_id}
          if defined $source_node->{archetype_node_id} && length $source_node->{archetype_node_id};
        push @parts, $source_node->{_type}
          if defined $source_node->{_type} && length $source_node->{_type};
        if ( ref( $source_node->{name} ) eq 'HASH'
            && defined $source_node->{name}{value}
            && length $source_node->{name}{value} )
        {
            push @parts, _normalize_term_id_component( $source_node->{name}{value} );
        }
    }
    push @parts, _normalize_term_id_component($text);

    return join ':', grep { defined && length } @parts;
}

sub _normalize_term_id_component {
    my ($text) = @_;
    return unless defined $text;

    $text =~ s/^\s+|\s+$//g;
    $text =~ s/\s+/_/g;
    $text =~ s/[^A-Za-z0-9_.:-]+/_/g;
    $text =~ s/_+/_/g;
    $text =~ s/^_+|_+$//g;

    return length $text ? $text : 'term';
}

sub _extract_date {
    my ($datetime) = @_;
    return unless defined $datetime;
    return $1 if $datetime =~ /^(\d{4}-\d{2}-\d{2})/;
    return;
}

sub _node_name {
    my ($node) = @_;
    return unless ref($node) eq 'HASH';
    return unless ref( $node->{name} ) eq 'HASH';
    return $node->{name}{value};
}

1;
