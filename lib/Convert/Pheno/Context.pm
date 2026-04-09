package Convert::Pheno::Context;

use strict;
use warnings;
use autodie;

sub new {
    my ( $class, $args ) = @_;
    $args ||= {};

    my $self = {
        source_format => $args->{source_format},
        target_format => $args->{target_format},
        entities      => $args->{entities} ? [ @{ $args->{entities} } ] : [],
        options       => $args->{options} ? { %{ $args->{options} } } : {},
        resources     => $args->{resources} ? { %{ $args->{resources} } } : {},
    };

    return bless $self, $class;
}

sub from_self {
    my ( $class, $self, $args ) = @_;
    $args ||= {};

    return $class->new(
        {
            source_format => $args->{source_format},
            target_format => $args->{target_format},
            entities      => $args->{entities},
            options       => {
                method     => $self->{method},
                method_ori => $self->{method_ori},
                stream     => $self->{stream},
                test       => $self->{test},
                verbose    => $self->{verbose},
                debug      => $self->{debug},
            },
            resources => {
                metaData        => $self->{metaData},
                convertPheno    => $self->{convertPheno},
                data_ohdsi_dict => $self->{data_ohdsi_dict},
                exposures       => $self->{exposures},
                visit_occurrence => $self->{visit_occurrence},
            },
        }
    );
}

sub source_format { return $_[0]->{source_format} }
sub target_format { return $_[0]->{target_format} }
sub entities      { return $_[0]->{entities} }
sub options       { return $_[0]->{options} }
sub resources     { return $_[0]->{resources} }

1;
