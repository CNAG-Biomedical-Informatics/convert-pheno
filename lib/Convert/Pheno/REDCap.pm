package Convert::Pheno::REDCap;

use strict;
use warnings;
use autodie;
use Convert::Pheno::Tabular::ToBFF qw(map_tabular_individual);
use Exporter 'import';

our @EXPORT = qw(do_redcap2bff);

sub do_redcap2bff {
    my ( $self, $participant ) = @_;
    return map_tabular_individual( $self, $participant );
}

1;
