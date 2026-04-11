#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);

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

done_testing();
