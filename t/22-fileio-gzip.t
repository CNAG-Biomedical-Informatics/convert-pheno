#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);
use Convert::Pheno::IO::CSVHandler qw(write_csv);
use Convert::Pheno::Audit::Terminology;
use Path::Tiny qw(path);
use Encode qw(encode);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

my $tmpdir = tempdir( CLEANUP => 1 );

{
    my $file = "$tmpdir/sample.json.gz";
    my $data = {
        id    => 'sample-1',
        count => 2,
        nested => {
            label => 'Alpha',
        },
    };

    ok(
        io_yaml_or_json(
            {
                filepath => $file,
                mode     => 'write',
                data     => $data,
            }
        ),
        'io_yaml_or_json writes gzipped JSON'
    );

    my $got = io_yaml_or_json(
        {
            filepath => $file,
            mode     => 'read',
        }
    );

    is_deeply( $got, $data, 'io_yaml_or_json reads gzipped JSON back correctly' );
}

{
    my $file = "$tmpdir/sample.yaml.gz";
    my $data = {
        id    => 'sample-2',
        count => 3,
        nested => {
            label => 'Beta',
        },
    };

    ok(
        io_yaml_or_json(
            {
                filepath => $file,
                mode     => 'write',
                data     => $data,
            }
        ),
        'io_yaml_or_json writes gzipped YAML'
    );

    my $got = io_yaml_or_json(
        {
            filepath => $file,
            mode     => 'read',
        }
    );

    is_deeply( $got, $data, 'io_yaml_or_json reads gzipped YAML back correctly' );
}

my $label = "Caf\x{e9}";
my $label_bytes = encode('UTF-8', $label);
my $multiline = "first\nsecond\r\nthird";
for my $format (qw(json yaml csv tsv)) {
    my @contents;
    for my $suffix ('', '.gz') {
        my $file = "$tmpdir/endings.$format$suffix";
        if ($format eq 'tsv') {
            my $audit = Convert::Pheno::Audit::Terminology->new(path => $file);
            $audit->write_row({row => 1, source_value => $label, match_status => 'not_found'});
            $audit->close;
        }
        elsif ($format eq 'csv') {
            write_csv({filepath => $file, sep => ',', headers => ['label'],
                data => [{label => $label}, {label => $multiline}]});
        }
        else {
            io_yaml_or_json({filepath => $file, mode => 'write',
                data => {label => $label, note => $multiline}});
        }
        my $bytes;
        if ($suffix) {
            gunzip $file => \$bytes or die $GunzipError;
        }
        else {
            $bytes = path($file)->slurp_raw;
        }
        push @contents, $bytes;
        like($bytes, qr/\n\z/, "$format$suffix ends with LF");
        like($bytes, qr/\Q$label_bytes\E/,
            "$format$suffix encodes Unicode exactly once");
        if ($format eq 'csv') {
            is($bytes, encode('UTF-8', "label\n$label\n\"$multiline\"\n"),
                "CSV$suffix uses LF records and preserves embedded LF and CRLF");
        }
        else {
            unlike($bytes, qr/\r/, "$format$suffix has no generated CR bytes");
            if ($format ne 'tsv') {
                my $got = io_yaml_or_json({filepath => $file, mode => 'read'});
                is($got->{note}, $multiline, "$format$suffix preserves embedded newlines");
            }
        }
    }
    is($contents[1], $contents[0], "$format plain and decompressed output match byte-for-byte");
}

done_testing();
