package Convert::Pheno::CSV;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Data::Dumper;
use Hash::Fold fold => { array_delimiter => ':' };
use Exporter 'import';
our @EXPORT_OK = qw(do_bff2csv do_pxf2csv);

#$Data::Dumper::Sortkeys = 1;

###############
###############
#  BFF2CSV    #
###############
###############

sub do_bff2csv {

    my ( $self, $bff ) = @_;

    # Premature return
    return unless defined($bff);

    # Flatten the hash to 1D
    my $csv = fold($bff);

    # Return the flattened hash
    return $csv;
}

###############
###############
#  PXF2CSV    #
###############
###############

sub do_pxf2csv {

    my ( $self, $pxf ) = @_;

    # Premature return
    return unless defined($pxf);

    # Flatten the hash to 1D
    my $csv = fold($pxf);

    # Return the flattened hash
    return $csv;
}

1;
