#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(decode_json);

sub read_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "Cannot read $file: $!\n";
    local $/;
    return <$fh>;
}
my $version = read_file('VERSION');
$version =~ s/\s+\z//;
die "Expected a stable VERSION such as 0.35\n" unless $version =~ /^\d+\.\d+$/;
my $tag = shift;
die "Release tag must equal VERSION ($version)\n" if defined($tag) && $tag ne $version;
my $desktop = "$version.0";
my ($core) = read_file('lib/Convert/Pheno.pm') =~ /our \$VERSION = '([^']+)'/;
die "Core version does not match VERSION\n" unless defined($core) && $core eq $version;
for my $file ('app/package.json', 'app/package-lock.json', 'app/src-tauri/tauri.conf.json') {
    my $data = decode_json(read_file($file));
    die "Version mismatch in $file\n" unless $data->{version} eq $desktop;
    die "Root package version mismatch in $file\n"
      if $data->{packages} && $data->{packages}{''}{version} ne $desktop;
}
my ($cargo) = read_file('app/src-tauri/Cargo.toml') =~ /^version = "([^"]+)"/m;
die "Cargo version mismatch\n" unless defined($cargo) && $cargo eq $desktop;
my ($lock) = read_file('app/src-tauri/Cargo.lock') =~ /name = "convert-pheno-desktop"\s+version = "([^"]+)"/;
die "Cargo lock version mismatch\n" unless defined($lock) && $lock eq $desktop;
die "API version mismatch\n"
  unless decode_json(read_file('api/perl/openapi.json'))->{info}{version} eq $version;
die "Citation version mismatch\n"
  unless read_file('CITATION.cff') =~ /^version: "\Q$version\E"$/m;
die "Changes does not contain the release version\n"
  unless read_file('Changes') =~ /^\Q$version\E /m;
print "Release versions agree: $version (Desktop $desktop)\n";
