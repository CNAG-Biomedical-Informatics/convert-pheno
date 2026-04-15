#!/usr/bin/env perl
#
#   JSON bridge for Python interoperability
#
#   This file is part of Convert::Pheno
#
#   Copyright (C) 2022-2026 Manuel Rueda - CNAG (manuel.rueda@cnag.eu)
#
#   License: Artistic License 2.0

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../../lib";
use JSON::XS;
use Convert::Pheno;

binmode STDIN,  ':raw';
binmode STDOUT, ':raw';
binmode STDERR, ':encoding(UTF-8)';

my $raw = do { local $/; <STDIN> };
my $json = JSON::XS->new->canonical;

sub fail {
    my ($message) = @_;
    chomp $message;
    print STDERR $message, "\n";
    exit 1;
}

fail('Expected JSON payload on STDIN')
  unless defined $raw && $raw =~ /\S/;

my $payload = eval { $json->decode($raw) };
fail("Invalid JSON payload: $@") if $@;
fail('JSON payload must decode to an object')
  unless ref $payload eq 'HASH';

my $method = $payload->{method};
fail("Payload must include string field 'method'")
  unless defined $method && !ref $method && length $method;

my $result = eval {
    my $convert = Convert::Pheno->new($payload);
    $convert->$method();
};
fail($@) if $@;

print STDOUT $json->encode($result);
