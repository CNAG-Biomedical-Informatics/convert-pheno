package Convert::Pheno::Tabular::Record;

use strict;
use warnings;
use autodie;
use Convert::Pheno::Mapping::Shared qw(dotify_and_coerce_number);
use Scalar::Util qw(blessed);

sub new {
    my ( $class, $arg ) = @_;
    my $raw = $arg->{raw} || {};
    my $self = {
        source      => $arg->{source},
        raw         => { %{$raw} },
        values      => { %{$raw} },
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
    my $value = $self->{values}{$field};
    return undef unless defined $value;

    return $value unless lc( $self->{source} // q{} ) eq 'redcap';
    return $value unless $self->has_choice_labels($field);

    my $mapped = $self->{redcap_dict}->choice_label( $field, $value );

    return defined $mapped ? dotify_and_coerce_number($mapped) : $value;
}

sub working_value {
    my ( $self, $field ) = @_;
    return $self->{values}{$field};
}

sub set_value {
    my ( $self, $field, $value ) = @_;
    $self->{values}{$field} = $value;
    return 1;
}

sub has_choice_labels {
    my ( $self, $field ) = @_;
    return 0 unless blessed( $self->{redcap_dict} )
      && $self->{redcap_dict}->can('has_choice_labels');
    return $self->{redcap_dict}->has_choice_labels($field);
}

sub field_meta {
    my ( $self, $field ) = @_;
    return unless blessed( $self->{redcap_dict} )
      && $self->{redcap_dict}->can('field_meta');
    return $self->{redcap_dict}->field_meta($field);
}

sub field_note {
    my ( $self, $field ) = @_;
    return unless blessed( $self->{redcap_dict} )
      && $self->{redcap_dict}->can('field_note');
    return $self->{redcap_dict}->field_note($field);
}

sub columns_snapshot {
    my ($self) = @_;
    return { %{ $self->{raw} } };
}

1;
