#!/usr/bin/env perl
#
#   A simple API to interact with Convert::Pheno
#
#   This file is part of Convert::Pheno
#
#   Last Modified: Dec/10/2022
#
#   $VERSION taken from Convert::Pheno
#
#   Copyright (C) 2022-2026 Manuel Rueda - CNAG (manuel.rueda@cnag.eu)
#
#   License: Artistic License 2.0

#use Mojolicious::Lite -signatures; # No go for CentOs Perl v5.16
use Mojolicious::Lite;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
our $API_DIR;
BEGIN {
    $API_DIR = dirname( abs_path(__FILE__) );
    require lib;
    lib->import("$API_DIR/../../lib");
}
use Convert::Pheno;
use Mojo::JSON qw(true false);

sub render_error {
    my ( $c, $status, $code, $message, $conversion ) = @_;
    my $body = {
        ok    => false,
        error => {
            code    => $code,
            message => $message,
        },
    };
    $body->{meta} = { conversion => $conversion } if defined $conversion;
    $c->render( json => $body, status => $status );
}

sub flatten_public_request {
    my ($request) = @_;
    my $conversion = $request->{conversion};
    my %payload;

    for my $section_name (qw(input output options)) {
        my $section = $request->{$section_name} // {};
        die "Request field '$section_name' must be an object"
          unless ref($section) eq 'HASH';

        die "Reserved key 'method' is not allowed in '$section_name'"
          if exists $section->{method};

        for my $key ( keys %{$section} ) {
            die
"Duplicate key '$key' appears in more than one of input/output/options"
              if exists $payload{$key};
            $payload{$key} = $section->{$key};
        }
    }

    $payload{method} = $conversion;
    return ( $conversion, \%payload );
}

post '/api' =>  sub {

    # Validate input request or return an error document
    my $c = shift;
    $c->openapi->valid_input or return;

    # Get payload
    my $request = $c->req->json;
    my ( $conversion, $hash ) = eval { flatten_public_request($request) };
    return render_error( $c, 422, 'invalid_request', "$@" ) if $@;

    # Create new object
    my $result = eval {
        my $convert = Convert::Pheno->new($hash);
        $convert->$conversion;
    };

    return render_error( $c, 422, 'conversion_error', "$@", $conversion ) if $@;

    $c->render(
        json => {
            ok   => true,
            data => $result,
            meta => {
                conversion => $conversion,
            },
        }
    );
  },
  'post_data';  # Must match 'operationId' or 'x-mojo-name'

# Load specification and start web server
plugin OpenAPI => { url => 'file://' . catfile( $API_DIR, 'openapi.json' ), schema => 'v3' };
app->config( hypnotoad => { listen => ['https://*:8080'] } );
app->start unless caller;
