package Convert::Pheno::ExecutionContext;

use strict;
use warnings;

sub new {
    my ( $class, $arg ) = @_;
    $arg ||= {};
    die "ExecutionContext requires a conversion request\n"
      unless $arg->{request};

    my $self = {
        request       => $arg->{request},
        stages        => $arg->{stages} || $arg->{request}->pipeline,
        stage_index   => -1,
        stage_active  => 0,
        stage_results => [],
        resources     => {},
    };
    return bless $self, $class;
}

sub request       { return $_[0]->{request} }
sub current_stage { return $_[0]->{current_stage} }
sub current_row   { return $_[0]->{current_row} }
sub result        { return $_[0]->{last_result} }

sub has_next_stage {
    my ($self) = @_;
    return $self->{stage_index} + 1 < @{ $self->{stages} };
}

sub begin_next_stage {
    my ($self) = @_;
    die "Cannot begin a pipeline stage before completing the active stage\n"
      if $self->{stage_active};
    die "Conversion pipeline has no remaining stages\n"
      unless $self->has_next_stage;

    $self->{stage_index}++;
    my $stage = $self->{stages}[ $self->{stage_index} ];
    my %input = $self->{stage_index} > 0
      ? ( data => $self->{last_result} )
      : ();

    $self->{current_stage} = $stage;
    $self->{stage_active}  = 1;
    return ( $stage, $self->{request}->stage_arguments( $stage, %input ) );
}

sub complete_stage {
    my ( $self, $result ) = @_;
    die "Cannot complete a pipeline stage when none is active\n"
      unless $self->{stage_active};

    push @{ $self->{stage_results} }, $result;
    $self->{last_result}  = $result;
    $self->{stage_active} = 0;
    return $result;
}

sub set_current_row {
    my ( $self, $row ) = @_;
    $self->{current_row} = $row;
    return $row;
}

sub clear_current_row {
    my ($self) = @_;
    delete $self->{current_row};
    return 1;
}

sub set_resource {
    my ( $self, $name, $value ) = @_;
    $self->{resources}{$name} = $value;
    return $value;
}

sub resource {
    my ( $self, $name ) = @_;
    return $self->{resources}{$name};
}

1;
