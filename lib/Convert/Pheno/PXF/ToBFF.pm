package Convert::Pheno::PXF::ToBFF;

use strict;
use warnings;
use autodie;

use Exporter 'import';

use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Mapping::Shared;
use Convert::Pheno::PXF::ToBFF::Individuals qw(map_pxf_to_individual);
use Convert::Pheno::PXF::ToBFF::Biosamples qw(extract_pxf_biosamples);

our @EXPORT_OK = qw(do_pxf2bff run_pxf_to_bundle map_pxf_to_individual);

sub do_pxf2bff {
    my ( $self, $data ) = @_;
    my $bundle = run_pxf_to_bundle( $self, $data, $self->{conversion_context} );
    return $bundle->legacy_primary_entity('individuals');
}

sub run_pxf_to_bundle {
    my ( $self, $data, $context ) = @_;

    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => 'pxf',
            target_format => 'beacon',
            entities      => $self->{entities} || ['individuals'],
        }
    );

    my $bundle = Convert::Pheno::Model::Bundle->new(
        {
            context  => $context,
            entities => $context->entities,
        }
    );

    my ( $phenopacket, $cohort, $family ) = _extract_pxf_payload($data);

    die "Are you sure that your input is not already a bff?\n"
      unless validate_format( $phenopacket, 'pxf' );

    _normalize_phenopacket_aliases($phenopacket);

    my $individual = map_pxf_to_individual( $self, $phenopacket, $cohort, $family );
    $bundle->add_entity( individuals => $individual );

    if ( _context_requests_entity( $context, 'biosamples' ) ) {
        for my $biosample ( @{ extract_pxf_biosamples( $phenopacket, $individual->{id} ) } ) {
            $bundle->add_entity( biosamples => $biosample );
        }
    }

    return $bundle;
}

sub _extract_pxf_payload {
    my ($data) = @_;

    my $phenopacket =
      exists $data->{phenopacket} ? $data->{phenopacket} : $data;

    my $cohort = exists $data->{family} ? $data->{cohort} : undef;
    my $family = exists $data->{family} ? $data->{family} : undef;

    return ( $phenopacket, $cohort, $family );
}

sub _normalize_phenopacket_aliases {
    my ($phenopacket) = @_;

    if ( exists $phenopacket->{medical_actions} ) {
        $phenopacket->{medicalActions} = delete $phenopacket->{medical_actions};
    }

    if ( exists $phenopacket->{meta_data} ) {
        $phenopacket->{metaData} = delete $phenopacket->{meta_data};
    }

    return 1;
}

sub _context_requests_entity {
    my ( $context, $entity ) = @_;
    return scalar grep { $_ eq $entity } @{ $context->entities };
}

1;
