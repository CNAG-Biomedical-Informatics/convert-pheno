package Convert::Pheno::PXF::ToBFF::Biosamples;

use strict;
use warnings;
use autodie;

use Exporter 'import';

our @EXPORT_OK = qw(extract_pxf_biosamples);

sub extract_pxf_biosamples {
    my ( $phenopacket, $individual_id ) = @_;

    return []
      unless exists $phenopacket->{biosamples}
      && ref( $phenopacket->{biosamples} ) eq 'ARRAY';

    my @biosamples;
    for my $biosample ( @{ $phenopacket->{biosamples} } ) {
        my %copy = %{$biosample};
        $copy{individualId} = $individual_id
          if defined $individual_id && !exists $copy{individualId};
        push @biosamples, \%copy;
    }

    return \@biosamples;
}

1;
