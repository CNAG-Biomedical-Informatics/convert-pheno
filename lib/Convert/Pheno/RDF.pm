package Convert::Pheno::RDF;

use strict;
use warnings;
use autodie;
use feature qw(say);
use JSONLD;
use Data::Dumper;
use Exporter 'import';
our @EXPORT_OK = qw(do_bff2jsonld do_pxf2jsonld);

#$Data::Dumper::Sortkeys = 1;

###############
###############
#  BFF2JSONLD #
###############
###############

sub do_bff2jsonld {

    my ( $self, $bff ) = @_;

    # Premature return
    return unless defined($bff);

    # Create new JSONLD object
    my $jld = JSONLD->new();

    # Add key for @contect
    $bff->{'@context'} = { '@vocab' => 'http://example.org/' };

    # Expand the data
    my $expanded = $jld->expand($bff);

    # Return the expanded data
    return $expanded;
}

###############
###############
#  PXF2JSONLD #
###############
###############

sub do_pxf2jsonld {

    my ( $self, $pxf ) = @_;

    # Premature return
    return unless defined($pxf);

    # Create new JSONLD object
    my $jld = JSONLD->new();

    # Add key for @contect
    $pxf->{'@context'} = { '@vocab' => 'http://example.org/' };

    # Expand the data
    my $expanded = $jld->expand($pxf);

    # Return the expanded data
    return $expanded;
}

1;
