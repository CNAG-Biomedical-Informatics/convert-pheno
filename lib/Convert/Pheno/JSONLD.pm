package Convert::Pheno::JSONLD;

use strict;
use warnings;
use Carp qw(croak);
use Exporter 'import';

our @EXPORT_OK = qw(do_bff2jsonld do_pxf2jsonld);

my $JSONLD_AVAILABLE;

sub _load_jsonld {
    return 1 if $JSONLD_AVAILABLE;

    eval {
        require JSONLD;
        1;
    };
    croak "JSONLD Perl module is required but could not be loaded: $@" if $@;

    return $JSONLD_AVAILABLE = 1;
}

sub _context_for {
    my ($format) = @_;

    my %common = (
        '@vocab' => 'https://ncithesaurus.nci.nih.gov/ncitbrowser/',
        'HP'                 => 'http://purl.obolibrary.org/obo/HP_',
        'OMIM'               => 'http://purl.obolibrary.org/obo/OMIM_',
        'id'                 => 'id',
        'type'               => 'type',
    );

    return {
        %common,
        'bff'                =>
'https://github.com/ga4gh-beacon/beacon-v2/tree/main/models/src/beacon-v2-default-model/individuals',
        'subject'            => 'bff:subject',
        'phenotypicFeatures' => 'bff:phenotypicFeatures',
        'description'        => 'bff:description',
        'severity'           => 'bff:severity',
        'diagnosis'          => 'bff:diagnosis',
        'disease'            => 'bff:disease',
        'ageAtCollection'    => 'bff:ageAtCollection',
        'sex'                => 'bff:sex',
        'MALE'               => 'bff:MALE',
      } if $format eq 'bff';

    return {
        %common,
        'pxf'                =>
'https://phenopacket-schema.readthedocs.io/en/latest/schema.html#version-2-0/',
        'subject'            => 'pxf:subject',
        'phenotypicFeatures' => 'pxf:phenotypicFeatures',
        'description'        => 'pxf:description',
        'severity'           => 'pxf:severity',
        'diagnosis'          => 'pxf:diagnosis',
        'disease'            => 'pxf:disease',
        'ageAtCollection'    => 'pxf:ageAtCollection',
        'sex'                => 'pxf:sex',
        'MALE'               => 'pxf:MALE',
      } if $format eq 'pxf';

    croak "Unsupported JSON-LD context format <$format>";
}

sub _compact_document {
    my ( $document, $context ) = @_;

    return unless defined $document;

    croak 'JSON-LD conversion expects a hashref document'
      unless ref($document) eq 'HASH';

    _load_jsonld();

    my $jld = JSONLD->new();
    $document->{'@context'} = $context;

    return $jld->compact($document);
}

###############
###############
#  BFF2JSONLD #
###############
###############

sub do_bff2jsonld {
    my ( $self, $bff ) = @_;
    return _compact_document( $bff, _context_for('bff') );
}

###############
###############
#  PXF2JSONLD #
###############
###############

sub do_pxf2jsonld {
    my ( $self, $pxf ) = @_;
    return _compact_document( $pxf, _context_for('pxf') );
}

1;
