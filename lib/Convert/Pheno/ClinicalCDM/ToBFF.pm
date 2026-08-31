package Convert::Pheno::ClinicalCDM::ToBFF;

use strict;
use warnings;

use Exporter 'import';

use Convert::Pheno::ClinicalCDM::Claims qw(map_claims_individual);
use Convert::Pheno::ClinicalCDM::I2B2 qw(map_i2b2_individual);
use Convert::Pheno::Context;
use Convert::Pheno::Model::Bundle;

our @EXPORT_OK = qw(run_clinical_cdm_to_bundle);

sub run_clinical_cdm_to_bundle {
    my ( $self, $record, $context ) = @_;
    die "Normalized clinical CDM input must contain a patient-scoped object\n"
      unless ref($record) eq 'HASH'
      && defined $record->{model}
      && defined $record->{personId}
      && ref( $record->{patient} ) eq 'HASH';

    my $model = $record->{model};
    $context ||= Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => $model,
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

    my $individual = $model eq 'i2b2'
      ? map_i2b2_individual( $self, $record )
      : map_claims_individual( $self, $record );
    $bundle->add_entity( individuals => $individual );
    return $bundle;
}

1;
