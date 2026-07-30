#!/usr/bin/env perl
use strict;
use warnings;
use Convert::Pheno::Operations qw(http_request_fields);
use FindBin qw($Bin);
use Mojo::JSON ();
use Path::Tiny qw(path);
use Test::Mojo;
use Test::More;

require "$Bin/../main.pl";
my $t = Test::Mojo->new(main::app());

note 'OpenAPI request fields should match the public registry';
my $openapi = Mojo::JSON::decode_json( path("$Bin/../openapi.json")->slurp_raw );
my $request_properties =
  $openapi->{paths}{'/api'}{post}{requestBody}{content}{'application/json'}{schema}{properties};
my $http_fields = http_request_fields();
for my $section (qw(input output options)) {
    is_deeply(
        [ sort keys %{ $request_properties->{$section}{properties} } ],
        [ sort @{ $http_fields->{$section} } ],
        "$section fields match the conversion registry"
    );
}

note 'Valid request should return the response envelope';
$t->post_ok(
    '/api',
    json => {
        conversion => 'pxf2bff',
        input => {
            data => {
                phenopacket => {
                    id      => 'P0007500',
                    subject => {
                        id          => 'P0007500',
                        dateOfBirth => 'unknown-01-01T00:00:00Z',
                        sex         => 'FEMALE',
                    },
                },
            },
        },
    }
)->status_is(200)->json_is('/ok', Mojo::JSON->true)->json_is('/meta/conversion', 'pxf2bff')
  ->json_is('/data/id', 'P0007500');

note 'FHIR Bundles should be available through the in-memory HTTP contract';
my $fhir_bundle = Mojo::JSON::decode_json(
    path("$Bin/../../../t/fhir2bff/in/patient-bundle.json")->slurp_raw
);
$t->post_ok(
    '/api',
    json => {
        conversion => 'fhir2bff',
        input      => { data => $fhir_bundle },
        options    => { test => Mojo::JSON->true },
    }
)->status_is(200)->json_is('/ok', Mojo::JSON->true)
  ->json_is('/meta/conversion', 'fhir2bff')
  ->json_is('/data/0/id', '5b24c87b-6223-f5b4-51e9-82051159bd1d');

note 'OpenAPI should reject invalid input shape';
$t->post_ok('/api', json => { conversion => 'pxf2bff', input => [] })
  ->status_is(400);

note 'OpenAPI should reject host filesystem options';
$t->post_ok(
    '/api',
    json => {
        conversion => 'pxf2bff',
        input      => { data => {} },
        options    => { out_file => '/tmp/result.json' },
    }
)->status_is(400);

note 'Conversion failures should use the JSON error envelope';
$t->post_ok('/api', json => { conversion => 'not_a_method', input => { data => {} } })
  ->status_is(422)->json_is('/ok', Mojo::JSON->false)
  ->json_is('/error/code', 'conversion_error')
  ->json_like('/error/message', qr/not_a_method/);

note 'Callable internal methods should not be API conversions';
$t->post_ok('/api', json => { conversion => 'get_info', input => {} })
  ->status_is(422)->json_is('/ok', Mojo::JSON->false)
  ->json_is('/error/code', 'conversion_error')
  ->json_like('/error/message', qr/Unsupported conversion <get_info>/)
  ->json_hasnt('/data');

note 'File-based conversion routes should remain on the CLI';
$t->post_ok(
    '/api',
    json => {
        conversion => 'redcap2bff',
        input      => { data => {} },
    }
)->status_is(422)->json_is('/ok', Mojo::JSON->false)
  ->json_is('/error/code', 'conversion_error')
  ->json_like('/error/message', qr/not available over HTTP/);

note 'The request flattener should also reject host filesystem options';
my $flatten_error;
eval {
    main::flatten_public_request(
        {
            conversion => 'pxf2bff',
            input      => { data => {} },
            options    => { mapping_file => '/srv/mapping.yaml' },
        }
    );
    1;
} or $flatten_error = $@;
like(
    $flatten_error,
    qr/Unsupported key 'mapping_file' in 'options'/,
    'request flattener rejects host filesystem options'
);

done_testing;
