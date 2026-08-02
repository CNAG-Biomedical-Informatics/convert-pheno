package Convert::Pheno::BFF::Biosample;

use strict;
use warnings;

use Exporter 'import';
use Storable qw(dclone);

our @EXPORT_OK = qw(biosample_to_phenopacket);

sub biosample_to_phenopacket {
    my ($biosample) = @_;
    my $pxf = {
        id             => $biosample->{id},
        individualId   => $biosample->{individualId},
        materialSample => dclone( $biosample->{biosampleStatus} ),
        sampleType     => dclone( $biosample->{sampleOriginType} ),
    };

    $pxf->{sampledTissue} = dclone( $biosample->{sampleOriginDetail} )
      if exists $biosample->{sampleOriginDetail};
    $pxf->{histologicalDiagnosis} = dclone( $biosample->{histologicalDiagnosis} )
      if exists $biosample->{histologicalDiagnosis};
    $pxf->{timeOfCollection} = {
        timestamp => $biosample->{collectionDate} . 'T00:00:00Z',
      }
      if exists $biosample->{collectionDate};

    if ( ref( $biosample->{measurements} ) eq 'ARRAY' ) {
        $pxf->{measurements} = [
            map {
                my $measurement = {
                    assay => dclone( $_->{assayCode} ),
                    value => dclone( $_->{measurementValue} ),
                };
                $measurement->{timeObserved} = {
                    timestamp => $_->{date} . 'T00:00:00Z',
                  }
                  if exists $_->{date};
                $measurement;
            } @{ $biosample->{measurements} }
        ];
    }

    return $pxf;
}

1;
