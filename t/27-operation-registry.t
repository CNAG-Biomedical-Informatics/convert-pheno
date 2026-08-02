use strict;
use warnings;

use lib qw(./lib ../lib);

use Test::More;

use Convert::Pheno;
use Convert::Pheno::Operations qw(
  conversion_spec
  http_request_fields
  is_http_conversion
  is_public_conversion
  public_conversions
);

ok( is_public_conversion('pxf2bff'), 'registry accepts a public conversion' );
ok( !is_public_conversion('get_info'), 'registry rejects callable helper methods' );
ok(
    !is_public_conversion('omop2bff_stream_processing'),
    'registry rejects internal conversion helpers'
);

my $csv_to_omop = conversion_spec('csv2omop');
is_deeply(
    $csv_to_omop->{pipeline},
    [ 'csv2bff', 'bff2omop' ],
    'registry defines compound conversion stages'
);
ok( $csv_to_omop->{resources}{sqlite}, 'registry defines route resources' );
ok( !$csv_to_omop->{http_enabled}, 'registry excludes file-based routes from HTTP' );

my $datasetjson_to_bff = conversion_spec('datasetjson2bff');
is_deeply(
    $datasetjson_to_bff->{pipeline},
    ['datasetjson2bff'],
    'registry defines Dataset-JSON as a direct BFF bundle operation'
);
ok(
    !$datasetjson_to_bff->{resources}{sqlite},
    'Dataset-JSON to BFF does not open ontology databases'
);
is_deeply(
    $datasetjson_to_bff->{entities}{supported},
    [ 'individuals', 'datasets', 'cohorts' ],
    'registry limits Dataset-JSON BFF output to implemented entities'
);
ok(
    !is_http_conversion('datasetjson2bff'),
    'registry keeps multi-file Dataset-JSON conversion outside HTTP'
);

is_deeply(
    conversion_spec('datasetjson2omop')->{pipeline},
    [ 'datasetjson2bff', 'bff2omop' ],
    'registry defines Dataset-JSON to OMOP as a compound conversion'
);

my $fhir_to_bff = conversion_spec('fhir2bff');
is_deeply(
    $fhir_to_bff->{pipeline},
    ['fhir2bff'],
    'registry defines FHIR as a direct BFF bundle operation'
);
ok(
    !$fhir_to_bff->{resources}{sqlite},
    'FHIR to BFF does not open ontology databases'
);
is_deeply(
    $fhir_to_bff->{entities}{supported},
    [ 'individuals', 'biosamples', 'datasets', 'cohorts' ],
    'registry exposes the implemented FHIR-derived BFF entities'
);
ok(
    is_http_conversion('fhir2bff'),
    'registry exposes in-memory FHIR conversion over HTTP'
);
is_deeply(
    conversion_spec('fhir2pxf')->{pipeline},
    [ 'fhir2bff', 'bff2pxf' ],
    'registry defines FHIR to PXF as a compound conversion'
);
is_deeply(
    conversion_spec('fhir2omop')->{pipeline},
    [ 'fhir2bff', 'bff2omop' ],
    'registry defines FHIR to OMOP as a compound conversion'
);

my $omop_to_bff = conversion_spec('omop2bff');
ok( $omop_to_bff->{streaming}, 'registry defines streaming capability' );
is_deeply(
    $omop_to_bff->{entities}{supported},
    [ 'individuals', 'biosamples', 'datasets', 'cohorts' ],
    'registry defines supported Beacon entities'
);
ok( is_http_conversion('pxf2bff'), 'registry exposes in-memory PXF conversion over HTTP' );
ok( !is_http_conversion('redcap2bff'), 'registry keeps file-based REDCap conversion on the CLI' );

my $http_fields = http_request_fields();
ok(
    scalar( grep { $_ eq 'data' } @{ $http_fields->{input} } ),
    'registry defines HTTP-safe input fields'
);
ok(
    !scalar( grep { $_ eq 'in_file' } @{ $http_fields->{input} } ),
    'registry excludes filesystem paths from HTTP input fields'
);

$csv_to_omop->{resources}{sqlite} = 0;
ok(
    conversion_spec('csv2omop')->{resources}{sqlite},
    'registry returns defensive copies of conversion metadata'
);

for my $conversion ( @{ public_conversions() } ) {
    ok(
        Convert::Pheno->can($conversion),
        "registered conversion <$conversion> exists"
    );
}

done_testing;
