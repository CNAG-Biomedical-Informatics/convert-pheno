package Convert::Pheno::Source::Result;

use strict;
use warnings;

sub new {
    my ( $class, $arg ) = @_;
    $arg ||= {};
    die "Source result requires data\n" unless exists $arg->{data};

    return bless {
        data      => $arg->{data},
        owned     => $arg->{owned} ? 1 : 0,
        artifacts => $arg->{artifacts} || {},
    }, $class;
}

sub data  { return $_[0]->{data} }
sub owned { return $_[0]->{owned} }

sub artifact {
    my ( $self, $name ) = @_;
    return $self->{artifacts}{$name};
}

1;
