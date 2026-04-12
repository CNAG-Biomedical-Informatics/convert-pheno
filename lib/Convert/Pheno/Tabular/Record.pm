package Convert::Pheno::Tabular::Record;

use strict;
use warnings;
use autodie;
use Convert::Pheno::Mapping::Shared qw(dotify_and_coerce_number);

sub new {
    my ( $class, $arg ) = @_;
    my $self = {
        source      => $arg->{source},
        raw         => $arg->{raw}         || {},
        redcap_dict => $arg->{redcap_dict} || {},
    };
    return bless $self, $class;
}

sub raw_value {
    my ( $self, $field ) = @_;
    return $self->{raw}{$field};
}

sub value {
    my ( $self, $field ) = @_;
    my $raw = $self->raw_value($field);
    return undef unless defined $raw;

    return $raw unless lc( $self->{source} // q{} ) eq 'redcap';
    return $raw unless $self->has_choice_labels($field);

    my $mapped = $self->{redcap_dict}->choice_label( $field, $raw );

    return defined $mapped ? dotify_and_coerce_number($mapped) : $raw;
}

sub has_choice_labels {
    my ( $self, $field ) = @_;
    return $self->{redcap_dict}->has_choice_labels($field);
}

sub field_meta {
    my ( $self, $field ) = @_;
    return $self->{redcap_dict}->field_meta($field);
}

sub field_note {
    my ( $self, $field ) = @_;
    return $self->{redcap_dict}->field_note($field);
}

sub columns_snapshot {
    my ($self) = @_;
    return { %{ $self->{raw} } };
}

1;
