#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib);
use Test::More;
use Test::Exception;
use File::Path qw(make_path);
use File::Spec::Functions qw(catdir catfile);
use File::Temp qw(tempdir);
use JSON::XS qw(encode_json);

use Convert::Pheno::DB::Bundle qw(
  bundled_database_path
  current_bundle_dir
);

sub write_manifest {
    my ( $share_dir, $data ) = @_;
    my $db_root = catdir( $share_dir, 'db' );
    make_path($db_root);
    open my $fh, '>:raw', catfile( $db_root, 'manifest.json' );
    print {$fh} encode_json($data);
    close $fh;
}

sub manifest_data {
    return {
        format        => 'convert-pheno-sqlite-bundle',
        formatVersion => 1,
        bundleVersion => 'v0',
        currentBundle => 'v0',
        databases     => { ncit => { file => 'ncit.db' } },
    };
}

{
    my $share_dir = tempdir( CLEANUP => 1 );
    my $bundle_dir = catdir( $share_dir, 'db', 'v0' );
    make_path($bundle_dir);
    write_manifest( $share_dir, manifest_data() );

    is(
        current_bundle_dir($share_dir),
        $bundle_dir,
        'current_bundle_dir follows currentBundle from the manifest'
    );
    is(
        bundled_database_path( $share_dir, 'ncit' ),
        catfile( $bundle_dir, 'ncit.db' ),
        'bundled_database_path resolves a declared database within the current bundle'
    );
    throws_ok(
        sub { bundled_database_path( $share_dir, 'hpo' ) },
        qr/not declared in the current bundle/,
        'undeclared databases are rejected'
    );
}

{
    my $share_dir = tempdir( CLEANUP => 1 );
    my $manifest = manifest_data();
    $manifest->{currentBundle} = '../v0';
    write_manifest( $share_dir, $manifest );

    throws_ok(
        sub { current_bundle_dir($share_dir) },
        qr/no valid currentBundle/,
        'unsafe current bundle paths are rejected'
    );
}

{
    my $share_dir = tempdir( CLEANUP => 1 );
    my $manifest = manifest_data();
    $manifest->{currentBundle} = 'v1';
    write_manifest( $share_dir, $manifest );

    throws_ok(
        sub { current_bundle_dir($share_dir) },
        qr/points to <v1> but describes <v0>/,
        'the current pointer and bundle metadata cannot drift apart'
    );
}

{
    my $share_dir = tempdir( CLEANUP => 1 );
    write_manifest( $share_dir, manifest_data() );

    throws_ok(
        sub { current_bundle_dir($share_dir) },
        qr/Current database bundle directory not found/,
        'a missing current bundle directory is reported clearly'
    );
}

done_testing();
