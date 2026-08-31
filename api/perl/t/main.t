#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use Mojo::JSON qw(encode_json);
use Path::Tiny qw(path);
use Test::Mojo;
use Test::More;

require "$Bin/../main.pl";
my $t = Test::Mojo->new(main::app());

$t->get_ok('/api/health')->status_is(200)
  ->json_is('/ok', Mojo::JSON->true)->json_is('/data/engine', 'perl');

$t->get_ok('/api/conversions')->status_is(200)
  ->json_is('/ok', Mojo::JSON->true)->json_is('/meta/count', 44)
  ->json_is('/data/0/id', 'bff2csv');

$t->get_ok('/examples/pxf')->status_is(200)
  ->json_is('/ok', Mojo::JSON->true)
  ->json_is('/meta/source', 'pxf')
  ->json_is('/meta/filename', 'phenopacket-example.json')
  ->json_is('/data/0/subject/id', '16-year-old boy')
  ->json_has('/data/0/phenotypicFeatures/0')
  ->json_has('/data/0/measurements/0');

for my $source (qw(beacon fhir)) {
    $t->get_ok("/examples/$source")->status_is(200)
      ->json_is('/ok', Mojo::JSON->true)
      ->json_is('/meta/source', $source);
}

$t->get_ok('/examples/csv')->status_is(200)
  ->json_is('/data/transport', 'multipart')
  ->json_is('/data/options/separator', ',')
  ->json_is('/data/files/0/role', 'source');

for my $source (qw(cbioportal cdisc-odm dataset-json dataset-xml i2b2 pcornet redcap sentinel)) {
    $t->get_ok("/examples/$source")->status_is(200)
      ->json_is('/data/transport', 'multipart')
      ->json_is('/data/files/0/role', 'source');
}

$t->get_ok('/examples/openehr')->status_is(200)
  ->json_is('/ok', Mojo::JSON->true)
  ->json_is('/meta/source', 'openehr')
  ->json_is('/meta/filename', 'openehr-patient-example.json')
  ->json_is('/data/subject/external_ref/id/value', 'openehr-patient-2');
my $openehr = $t->tx->res->json->{data};
$t->post_ok(
    '/api/conversions/openehr2bff',
    json => {
        input   => { data => $openehr },
        output  => { entities => ['individuals'] },
        options => { test => Mojo::JSON->true },
    }
)->status_is(200)->json_is('/ok', Mojo::JSON->true)
  ->json_is('/artifacts/0/filename', 'individuals.json');

$t->get_ok('/examples/omop')->status_is(200)
  ->json_is('/data/transport', 'multipart')
  ->json_is('/data/files/0/role', 'source');
$t->get_ok('/examples/omop?transport=json')->status_is(200)
  ->json_is('/data/PERSON/0/person_id', 974);

$t->get_ok('/examples/not-a-source')->status_is(404)
  ->json_is('/error/code', 'unknown_example');

my $pxf = Mojo::JSON::decode_json(
    path("$Bin/../../../t/pxf2bff/in/pxf.json")->slurp_raw
);
$t->post_ok(
    '/api/conversions/pxf2bff',
    json => {
        input   => { data => $pxf },
        output  => { entities => [ 'individuals', 'biosamples' ] },
        options => { test => Mojo::JSON->true },
    }
)->status_is(200)->json_is('/ok', Mojo::JSON->true)
  ->json_is('/meta/conversion', 'pxf2bff')
  ->json_is('/artifacts/0/filename', 'individuals.json')
  ->json_is('/artifacts/1/filename', 'biosamples.json');

$t->post_ok(
    '/api/conversions/csv2bff' => form => {
        request => encode_json(
            {
                output  => { entities => ['individuals'] },
                options => {
                    separator  => ',',
                    term_audit => 'xlsx',
                    test       => Mojo::JSON->true,
                },
            }
        ),
        source  => { file => "$Bin/../../../t/csv2bff/in/csv_data.csv" },
        mapping => { file => "$Bin/../../../t/csv2bff/in/csv_mapping.yaml" },
    }
)->status_is(200)->json_is('/ok', Mojo::JSON->true)
  ->json_is('/meta/conversion', 'csv2bff')
  ->json_has('/meta/terminologyAudit')
  ->json_is('/meta/terminologyAudit/reportArtifactId', 'term-audit')
  ->json_is('/artifacts/0/filename', 'individuals.json')
  ->json_is('/artifacts/1/filename', 'term-audit.xlsx');

$t->post_ok('/api/conversions/not-a-route', json => { input => { data => {} } })
  ->status_is(404)->json_is('/error/code', 'unknown_conversion');

$t->post_ok('/api/conversions/pxf2bff', json => { input => { data => {} }, options => { out_file => '/tmp/result.json' } })
  ->status_is(422)->json_is('/error/code', 'invalid_request');

$t->post_ok('/api/conversions/pxf2bff', json => { input => { data => '/tmp/input.json' } })
  ->status_is(422)->json_is('/error/code', 'invalid_request');

$t->post_ok('/api/conversions/pxf2bff', json => { input => [] })
  ->status_is(422)->json_is('/error/code', 'invalid_request');

done_testing;
