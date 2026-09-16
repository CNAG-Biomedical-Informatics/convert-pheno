use strict;
use warnings;
use lib qw(lib t/lib);
use File::Temp qw(tempdir);
use Test::More;
use Test::Mojo;
use MIME::Base64 qw(decode_base64);
use Test::ConvertPheno qw(load_json_file);

local $ENV{CONVERT_PHENO_API_TOKEN} = 'a' x 32;
local $ENV{CONVERT_PHENO_STATE_DIR} = tempdir(CLEANUP => 1);
require './api/perl/main.pl';
my $t = Test::Mojo->new(main::app());
my $auth = {Authorization => 'Bearer ' . $ENV{CONVERT_PHENO_API_TOKEN}};
$t->get_ok('/api/conversions' => $auth)->status_is(200);
my %sources = map { $_->{source}{id} => 1 } @{$t->tx->res->json->{data}};
for my $source (sort keys %sources) {
    subtest "$source automatic example" => sub {
        $t->get_ok("/examples/$source?transport=auto" => $auth)->status_is(200);
        my $data = $t->tx->res->json->{data};
        if (ref($data) eq 'HASH' && ($data->{transport} || '') eq 'multipart') {
            ok(scalar(grep { $_->{role} eq 'source' } @{$data->{files}}), 'package contains source input');
            for my $file (@{$data->{files}}) {
                ok(length(decode_base64($file->{content})), "$file->{filename} has contents");
            }
        } else {
            ok(ref($data) eq 'ARRAY' ? @$data : ref($data) eq 'HASH' && keys %$data, 'JSON example has records');
        }
    };
}
$t->get_ok('/examples/beacon?transport=auto' => $auth)->status_is(200)
  ->json_is('/meta/filename', 'beacon-individuals-example.json')
  ->json_is('/data', load_json_file('t/bff2pxf/in/individuals.json'));
done_testing;
