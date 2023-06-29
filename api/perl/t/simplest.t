#!/usr/bin/env perl
use Mojo::Base -strict;
use Test::Mojo;
use Test::More tests => 3;

use Mojolicious::Lite;

post '/api' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;
  $c->render(json => undef, status => 200);
  },
  'post_data';

plugin OpenAPI => {url => 'file://../openapi.json', schema => 'v3'};

my $t = Test::Mojo->new();

note 'Valid request should be ok';
$t->post_ok('/api', json => {method => "pxf2bff", data => {}, ohdsi_db => 0} )->status_is(200);
$t->post_ok('/api', json => {method => "pxf2bff", data => {}, ohdsi_db => 'foo'} )->status_is(200);
