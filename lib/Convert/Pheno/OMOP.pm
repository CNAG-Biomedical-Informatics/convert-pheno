package Convert::Pheno::OMOP;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::OMOP::ToBFF::Individuals qw(map_participant);
use Convert::Pheno::OMOP::ToBFF::Biosamples qw(extract_participant_biosamples);

our @EXPORT = qw(do_omop2bff run_omop_to_bundle);

sub do_omop2bff {
    my ( $self, $participant ) = @_;
    my $bundle = run_omop_to_bundle( $self, $participant, $self->{conversion_context} );
    return $bundle->legacy_primary_entity('individuals');
}

sub run_omop_to_bundle {
    my ( $self, $participant, $context ) = @_;

    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => 'omop',
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

    my $individual = map_participant( $self, $participant );
    $bundle->add_entity( individuals => $individual );

    if ( _context_requests_entity( $context, 'biosamples' ) ) {
        for my $biosample ( @{ extract_participant_biosamples( $self, $participant, $individual ) } ) {
            $bundle->add_entity( biosamples => $biosample );
        }
    }

    return $bundle;
}

sub _context_requests_entity {
    my ( $context, $entity ) = @_;
    return scalar grep { $_ eq $entity } @{ $context->entities };
}

1;
