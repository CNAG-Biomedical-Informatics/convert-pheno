package Convert::Pheno::Pipeline;

use strict;
use warnings;

use Exporter 'import';

use Convert::Pheno::ConversionRequest;
use Convert::Pheno::ExecutionContext;

our @EXPORT_OK = qw(run_conversion_pipeline);

sub run_conversion_pipeline {
    my ($converter) = @_;
    my $request = Convert::Pheno::ConversionRequest->from_converter($converter);
    my $spec    = $request->spec;

    die "Conversion <$spec->{name}> is not a compound pipeline\n"
      unless $spec->{operation} eq 'pipeline';
    die "Conversion <$spec->{name}> does not support streaming\n"
      if $converter->{stream} && !$spec->{streaming};

    my $execution = Convert::Pheno::ExecutionContext->new(
        { request => $request }
    );
    delete $converter->{_term_audit_review};

    # OMOP file input is already emitted one participant at a time. Preserve
    # that bounded-memory path while applying the downstream BFF-to-PXF stage
    # in the output sink rather than materializing the full BFF intermediate.
    if ( $spec->{name} eq 'omop2pxf' && !$request->has_data ) {
        my ( $stage, $arguments ) = $execution->begin_next_stage;
        my $stage_converter = Convert::Pheno->new($arguments);
        $stage_converter->{method_ori} = $spec->{name};
        my $result = $stage_converter->$stage();
        $converter->{_term_audit_review} = $stage_converter->term_audit_review;
        return $execution->complete_stage($result);
    }

    while ( $execution->has_next_stage ) {
        my ( $stage, $arguments ) = $execution->begin_next_stage;
        my $stage_converter = Convert::Pheno->new($arguments);
        my $result = $stage_converter->$stage();
        # Stages own their audit writers; callers need the review associated
        # with the last written report, not an intermediate mapping decision.
        if (my $review = $stage_converter->term_audit_review) {
            $converter->{_term_audit_review} = $review;
        }
        $execution->complete_stage($result);
    }

    return $execution->result;
}

1;
