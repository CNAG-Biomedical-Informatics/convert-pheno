package Convert::Pheno::RDF;

use strict;
use warnings;
use autodie;
use feature qw(say);

#use JSONLD;
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

    # Dynamically load JSONLD
    eval {
        require JSONLD;
        JSONLD->import();    # Call import if JSONLD exports symbols you need
    };
    if ($@) {
        die
"There were errors in installing dependencies on Windows, specifically: 'JSONLD' is not available: $@";
    }

    # Premature return
    return unless defined($bff);

    # Create new JSONLD object
    my $jld = JSONLD->new();

    my $context = {
        '@vocab' => 'https://ncithesaurus.nci.nih.gov/ncitbrowser/',
        'bff'    =>
'https://github.com/ga4gh-beacon/beacon-v2/tree/main/models/src/beacon-v2-default-model/individuals',
        'HP'                 => 'http://purl.obolibrary.org/obo/HP_',
        'OMIM'               => 'http://purl.obolibrary.org/obo/OMIM_',
        'id'                 => 'id',
        'type'               => 'type',
        'subject'            => 'bff:subject',
        'phenotypicFeatures' => 'bff:phenotypicFeatures',
        'description'        => 'bff:description',
        'severity'           => 'bff:severity',
        'diagnosis'          => 'bff:diagnosis',
        'disease'            => 'bff:disease',
        'ageAtCollection'    => 'bff:ageAtCollection',
        'sex'                => 'bff:sex',
        'MALE'               => 'bff:MALE',
    };

    # Add key for @contect
    $bff->{'@context'} = $context;

    # Compact the data
    my $compact = $jld->compact($bff);

    # Expand the data
    #my $expanded = $jld->expand($bff);

    # Return the transformed data
    return $compact;
}

###############
###############
#  PXF2JSONLD #
###############
###############

sub do_pxf2jsonld {

    my ( $self, $pxf ) = @_;

    # Dynamically load JSONLD
    eval {
        require JSONLD;
        JSONLD->import();    # Call import if JSONLD exports symbols you need
    };
    if ($@) {
        die
"There were errors in installing dependencies on Windows, specifically: 'JSONLD' is not available: $@";
    }

    # Premature return
    return unless defined($pxf);

    # Create new JSONLD object
    my $jld = JSONLD->new();

    my $context = {
        '@vocab' => 'https://ncithesaurus.nci.nih.gov/ncitbrowser/',
        'pxf'    =>
'https://phenopacket-schema.readthedocs.io/en/latest/schema.html#version-2-0/',
        'HP'                 => 'http://purl.obolibrary.org/obo/HP_',
        'OMIM'               => 'http://purl.obolibrary.org/obo/OMIM_',
        'id'                 => 'id',
        'type'               => 'type',
        'subject'            => 'pxf:subject',
        'phenotypicFeatures' => 'pxf:phenotypicFeatures',
        'description'        => 'pxf:description',
        'severity'           => 'pxf:severity',
        'diagnosis'          => 'pxf:diagnosis',
        'disease'            => 'pxf:disease',
        'ageAtCollection'    => 'pxf:ageAtCollection',
        'sex'                => 'pxf:sex',
        'MALE'               => 'pxf:MALE',
    };

    # Add key for @context
    # NB: arg [expandContext => $ctx] was not viable
    $pxf->{'@context'} = $context;

    # Compact the data
    my $compact = $jld->compact($pxf);

    # Expand the data
    my $expanded = $jld->expand($pxf);

    # Convert to RDF
    #my $rdf =  $jld->to_rdf($pxf);

    # Return the transformed data
    return $compact;
}

1;
