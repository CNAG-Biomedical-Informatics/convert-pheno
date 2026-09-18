#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use File::Temp qw(tempdir);
use Mojo::JSON qw(decode_json true);
use Path::Tiny qw(path);
use Test::Mojo;
use Test::More;

local $ENV{CONVERT_PHENO_API_TOKEN} = 'test-api-token-' x 3;
local $ENV{CONVERT_PHENO_STATE_DIR} = tempdir(CLEANUP => 1);
local $ENV{CONVERT_PHENO_JOB_LIMIT} = 4;
require "$Bin/../main.pl";
my $t = Test::Mojo->new(main::app());
my $auth = {Authorization => 'Bearer ' . $ENV{CONVERT_PHENO_API_TOKEN}};

$t->get_ok('/api/jobs/settings')->status_is(401);
$t->get_ok('/api/jobs/settings' => $auth)->status_is(200)
  ->json_is('/data/maxConcurrentJobs', 1);
$t->post_ok('/api/jobs/settings' => $auth => json => {maxConcurrentJobs => 4})
  ->status_is(200)->json_is('/data/maxConcurrentJobs', 4);
$t->post_ok('/api/jobs/settings' => $auth => json => {maxConcurrentJobs => 0})
  ->status_is(422);
$t->get_ok('/api/jobs/settings' => $auth)->status_is(200)
  ->json_is('/data/maxConcurrentJobs', 4);
$t->post_ok('/api/jobs/settings' => $auth => json => {maxConcurrentJobs => 1})
  ->status_is(200);

$t->get_ok('/api/health')->status_is(401);
$t->get_ok('/api/health' => $auth)->status_is(200)->json_is('/ok', true);
$t->get_ok('/api/conversions' => $auth)->status_is(200);
ok(grep($_->{id} eq 'pxf2bff', @{$t->tx->res->json->{data}}), 'catalog includes fixture route');

sub complete_job {
    my ($request) = @_;
    $t->post_ok('/api/jobs' => $auth => json => $request)->status_is(202);
    my $id = $t->tx->res->json->{data}{id};
    BAIL_OUT('Submission did not return a job ID') unless $id;
    my $deadline = time + 30;
    my $job;
    while (time < $deadline) {
        my $response = $t->ua->get("/api/jobs/$id" => $auth)->result;
        $job = $response->json->{data};
        last if $job && $job->{status} !~ /\A(?:queued|running)\z/;
        select undef, undef, undef, .05;
    }
    is($job->{status}, 'completed', 'HTTP job completes a real fixture conversion')
      or diag explain $job;
    return ($id, $job);
}

my $pxf = decode_json(path("$Bin/../../../t/pxf2bff/in/pxf.json")->slurp_raw);
my ($id, $job) = complete_job({
    conversion => 'pxf2bff', input => {data => $pxf},
    output => {entities => ['individuals', 'biosamples']}, options => {test => true},
});
is_deeply([sort map {$_->{filename}} @{$job->{result}{artifacts}}],
    ['biosamples.json', 'individuals.json'], 'both entity outputs are retained');
$t->get_ok("/api/jobs/$id/outputs/individuals/preview" => $auth)->status_is(200)
  ->json_has('/data/data');
$t->get_ok("/api/jobs/$id/outputs/individuals/download" => $auth)->status_is(200);
my $download = decode_json($t->tx->res->body);
ok(ref($download) eq 'ARRAY' && @$download, 'download contains converted individuals');

$t->post_ok('/api/inputs' => $auth => form => {
    source => {file => "$Bin/../../../t/csv2bff/in/csv_data.csv"},
    mapping => {file => "$Bin/../../../t/csv2bff/in/csv_mapping.yaml"},
})->status_is(201);
my %handles = map {$_->{filename} => $_->{id}} @{$t->tx->res->json->{data}};
my ($source) = map {$handles{$_}} grep {/csv_data\.csv\z/} keys %handles;
my ($mapping) = map {$handles{$_}} grep {/csv_mapping\.yaml\z/} keys %handles;
ok($source && $mapping, 'uploads return handles for both input roles');
my ($csv_id, $csv_job) = complete_job({
    conversion => 'csv2bff', input => {files => {source => [$source], mapping => [$mapping]}},
    output => {entities => ['individuals']},
    options => {separator => ',', term_audit => 'xlsx', test => true},
});
ok($csv_job->{result}{meta}{terminologyAudit}, 'audit summary accompanies completed job');
$t->get_ok("/api/jobs/$csv_id/outputs/term-audit/download" => $auth)->status_is(200);
is(substr($t->tx->res->body, 0, 2), 'PK', 'Excel audit downloads as a binary workbook');

$t->post_ok('/api/jobs' => $auth => json => {conversion => 'not-a-route', input => {data => {}}})
  ->status_is(422)->json_is('/error/code', 'invalid_request');
$t->post_ok('/api/jobs' => $auth => json => {conversion => 'pxf2bff', input => {files => {source => ['/tmp/input.json']}}})
  ->status_is(422)->json_is('/error/code', 'invalid_request');
$t->post_ok('/api/inputs/local' => $auth => json => {paths => ['/tmp/input.json']})
  ->status_is(403);

done_testing;
