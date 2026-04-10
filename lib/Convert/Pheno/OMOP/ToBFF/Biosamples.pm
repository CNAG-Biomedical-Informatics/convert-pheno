package Convert::Pheno::OMOP::ToBFF::Biosamples;

use strict;
use warnings;
use autodie;

use Exporter 'import';

our @EXPORT_OK = qw(extract_participant_biosamples);

sub extract_participant_biosamples {
    my ( $self, $participant, $individual ) = @_;

    # Placeholder for future SPECIMEN -> Beacon biosamples support.
    # Keep the contract stable now: callers can request biosamples from the
    # OMOP bundle path, and this adapter currently returns none.
    return [];
}

1;
