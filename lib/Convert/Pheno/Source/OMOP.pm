package Convert::Pheno::Source::OMOP;

use strict;
use warnings;

use Convert::Pheno::OMOP::Source qw(collect_omop_input);
use Convert::Pheno::Source::Result;

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $collected = collect_omop_input( $self->{converter} );

    return Convert::Pheno::Source::Result->new(
        {
            data      => $collected->{data},
            owned     => $collected->{owned},
            artifacts => {
                kind          => $collected->{kind},
                filepath_sql  => $collected->{filepath_sql},
                filepaths_csv => $collected->{filepaths_csv},
            },
        }
    );
}

1;
