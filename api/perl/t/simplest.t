#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);
use JSON::XS qw(decode_json);
use Test::More;

my $contract_path = catfile( $Bin, '..', 'openapi.json' );
open my $fh, '<', $contract_path or die "Cannot open $contract_path: $!";
local $/;
my $contract = decode_json(<$fh>);
close $fh;

open my $version_fh, '<', catfile($Bin, '..', '..', '..', 'VERSION')
  or die "Cannot open VERSION: $!";
my $version = <$version_fh>;
close $version_fh;
$version =~ s/\s+\z//;
is( $contract->{info}{version}, $version, 'OpenAPI documents the release version' );
ok( exists $contract->{paths}{'/api/health'}{get}, 'health endpoint is documented' );
ok( exists $contract->{paths}{'/api/conversions'}{get}, 'catalog endpoint is documented' );
ok(
    exists $contract->{paths}{'/api/jobs'}{post},
    'asynchronous job submission is documented'
);
ok(
    exists $contract->{paths}{'/api/inputs'}{post}{requestBody}{content}{'multipart/form-data'},
    'multipart input uploads are documented'
);
ok( !exists $contract->{paths}{'/api'}, 'removed POST /api contract is not published' );
ok( !exists $contract->{paths}{'/api/conversions/{conversion}'}, 'removed synchronous endpoint is not published' );
is($contract->{components}{securitySchemes}{BearerAuth}{scheme}, 'bearer', 'authentication is documented');

open my $source_fh, '<', catfile($Bin, '..', 'main.pl') or die $!;
my $source = <$source_fh>;
close $source_fh;
my %actual;
while ($source =~ /^(get|post|del) '([^']+)' =>/mg) {
    my ($method, $route) = ($1, $2);
    $method = 'delete' if $method eq 'del';
    $route =~ s/:([a-zA-Z_]+)/{$1}/g;
    $actual{"$method $route"} = 1;
}
my %documented;
for my $route (keys %{$contract->{paths}}) {
    for my $method (grep {/\A(?:get|post|delete|put|patch)\z/} keys %{$contract->{paths}{$route}}) {
        $documented{"$method $route"} = 1;
    }
}
is_deeply(\%documented, \%actual, 'OpenAPI paths match the implemented HTTP routes');
sub check_refs {
    my ($value) = @_;
    if (ref($value) eq 'HASH') {
        if (my $ref = $value->{'$ref'}) {
            my $target = $contract;
            my @parts = split '/', $ref;
            shift @parts;
            $target = ref($target) eq 'HASH' ? $target->{$_} : undef for @parts;
            ok(defined $target, "$ref resolves");
        }
        check_refs($_) for values %$value;
    } elsif (ref($value) eq 'ARRAY') {
        check_refs($_) for @$value;
    }
}
check_refs($contract);
done_testing;
