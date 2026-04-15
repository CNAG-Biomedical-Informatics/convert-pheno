#!/usr/bin/env perl
use Mojo::Base -strict;
use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);
use Mojo::JSON ();
use Test::Mojo;
use Test::More tests => 4;

use Mojolicious::Lite;

post '/api' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;
  my $payload = $c->req->json;
  $c->render(
    json => {
      ok   => Mojo::JSON->true,
      data => {},
      meta => { conversion => $payload->{conversion} },
    },
    status => 200
  );
  },
  'post_data';

plugin OpenAPI => {url => 'file://' . catfile( $Bin, '..', 'openapi.json' ), schema => 'v3'};

my $t = Test::Mojo->new();

note 'Valid request should be ok';
$t->post_ok('/api', json => {conversion => "pxf2bff", input => {data => {}}, options => {ohdsi_db => 0}} )->status_is(200);
$t->post_ok('/api', json => {conversion => "pxf2bff", input => []} )->status_is(400);
