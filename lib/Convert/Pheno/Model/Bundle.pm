package Convert::Pheno::Model::Bundle;

use strict;
use warnings;
use autodie;

sub new {
    my ( $class, $args ) = @_;
    $args ||= {};

    my $self = {
        context => $args->{context},
    };

    if ( $args->{entities} ) {
        for my $entity ( @{ $args->{entities} } ) {
            $self->{$entity} = [];
        }
    }

    return bless $self, $class;
}

sub context {
    my ($self) = @_;
    return $self->{context};
}

sub add_entity {
    my ( $self, $entity_type, $entity ) = @_;
    return unless defined $entity;
    my $context = $self->{context};
    if ($context && ($context->target_format || '') eq 'beacon'
        && ($entity_type eq 'individuals' || $entity_type eq 'biosamples')) {
        my $id = $context->options->{datasetId};
        # Some Beacon backends require this non-standard top-level property.
        # Opt in explicitly; copy the record so caller-owned data stays intact.
        $entity = { %{$entity}, datasetId => $id } if defined $id;
    }
    $self->{$entity_type} ||= [];
    push @{ $self->{$entity_type} }, $entity;
    return 1;
}

sub entities {
    my ( $self, $entity_type ) = @_;
    $self->{$entity_type} ||= [];
    return $self->{$entity_type};
}

sub primary_entity {
    my ( $self, $entity_type ) = @_;
    my $entities = $self->entities($entity_type);
    return unless @$entities;
    return $entities->[0];
}

1;
