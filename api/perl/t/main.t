#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use Mojo::JSON ();
use Test::Mojo;
use Test::More;

require "$Bin/../main.pl";
my $t = Test::Mojo->new(main::app());

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

note 'OpenAPI should reject invalid input shape';
$t->post_ok('/api', json => { conversion => 'pxf2bff', input => [] })
  ->status_is(400);

note 'Conversion failures should use the JSON error envelope';
$t->post_ok('/api', json => { conversion => 'not_a_method', input => { data => {} } })
  ->status_is(422)->json_is('/ok', Mojo::JSON->false)
  ->json_is('/error/code', 'conversion_error')
  ->json_like('/error/message', qr/not_a_method/);

note 'Duplicate keys across sections should be rejected';
$t->post_ok(
    '/api',
    json => {
        conversion => 'pxf2bff',
        input      => { entities => ['individuals'] },
        output     => { entities => ['biosamples'] },
    }
)->status_is(422)->json_is('/ok', Mojo::JSON->false)
  ->json_is('/error/code', 'invalid_request')
  ->json_like('/error/message', qr/Duplicate key 'entities'/);

done_testing;
