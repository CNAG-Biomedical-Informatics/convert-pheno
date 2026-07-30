package Convert::Pheno::Source::Structured;

use strict;
use warnings;

use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);
use Convert::Pheno::Source::Result;

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};

    return Convert::Pheno::Source::Result->new(
        {
            data  => $converter->{data},
            owned => 0,
        }
      )
      if exists $converter->{data};

    return Convert::Pheno::Source::Result->new(
        {
            data => io_yaml_or_json(
                {
                    filepath => $converter->{in_file},
                    mode     => 'read',
                }
            ),
            owned => 1,
        }
    );
}

1;
