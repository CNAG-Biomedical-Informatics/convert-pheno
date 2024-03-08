package Convert::Pheno::RDF;

use strict;
use warnings;
use autodie;
use feature qw(say);
use JSONLD;
use Data::Dumper;
use Exporter 'import';
our @EXPORT_OK = qw(do_bff2jsonld);

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

1;
