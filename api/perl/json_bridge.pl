#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../../lib";
use JSON::XS;
use Convert::Pheno;
use Convert::Pheno::HTTP::Service qw(catalog execute health is_service_error);
use Convert::Pheno::Operations qw(is_public_conversion);

binmode STDIN,  ':raw';
binmode STDOUT, ':raw';
binmode STDERR, ':encoding(UTF-8)';

my $raw  = do { local $/; <STDIN> };
my $json = JSON::XS->new->canonical;

sub fail_service {
    my ( $message, $status, $code ) = @_;
    chomp $message;
    print STDOUT $json->encode(
        {
            ok    => JSON::XS::false,
            error => {
                status  => $status || 500,
                code    => $code || 'infrastructure_error',
                message => $message,
            },
        }
    );
    exit 0;
}

sub fail_legacy {
    my ($message) = @_;
    chomp $message;
    print STDERR $message, "\n";
    exit 1;
}

fail_legacy('Expected JSON payload on STDIN')
  unless defined $raw && $raw =~ /\S/;
my $payload = eval { $json->decode($raw) };
fail_legacy("Invalid JSON payload: $@") if $@;
fail_legacy('JSON payload must decode to an object')
  unless ref $payload eq 'HASH';

my $action = $payload->{action} || q{};
if ( !$action ) {
    my $method = $payload->{method};
    fail_legacy("Payload must include string field 'method'")
      unless defined $method && !ref($method) && length($method);
    fail_legacy("Unsupported conversion <$method>")
      unless is_public_conversion($method);
}
my $result = eval {
    return health() if $action eq 'health';
    return catalog() if $action eq 'catalog';
    return execute( $payload->{conversion}, $payload->{request} )
      if $action eq 'execute';
    if ( !$action && is_public_conversion( $payload->{method} ) ) {
        my $method  = $payload->{method};
        my $convert = Convert::Pheno->new($payload);
        return $convert->$method();
    }
    die "Unsupported bridge action <$action>";
};

if ( my $error = $@ ) {
    fail_legacy($error) unless $action;
    if ( is_service_error($error) ) {
        fail_service( $error->message, $error->status, $error->code );
    }
    fail_service( 'The Perl conversion service failed unexpectedly', 500,
        'infrastructure_error' );
}

print STDOUT $json->encode($result);
