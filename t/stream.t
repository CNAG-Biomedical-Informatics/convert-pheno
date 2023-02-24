#!/usr/bin/env perl
use strict;
use warnings;
use lib ( './lib', '../lib' );
use feature qw(say);
use Data::Dumper;
use File::Temp qw{ tempfile };    # core
use Test::More tests => 3;
use IO::Uncompress::Gunzip;
use File::Compare;
use Convert::Pheno;

# Test 1
use_ok('Convert::Pheno') or exit;

# Test 2
my $method = 'omop2bff';

{
my $out = 't/omop2bff/out/individuals_drug_exposure.json.gz';
my ( undef, $tmp_file ) = tempfile( DIR => 't', SUFFIX => ".json.gz", UNLINK => 1 );
my $convert = Convert::Pheno->new(
    {
        in_file              => undef,
        in_files             => ['t/omop2bff/in/gz/dump.sql.gz'],
        out_file             => $tmp_file,
        redcap_dictionary    => undef,
        mapping_file         => undef,
        self_validate_schema => undef,
        schema_file          => 'schema/mapping.json',
        in_textfile          => 1,
        stream               => 1,
        omop_tables          => ['DRUG_EXPOSURE'],
        max_lines_sql        => 2700,
        sep                  => ',',
        test                 => 1,
        search               => 'exact',
        method               => $method
    }
);
$convert->$method;
# Does not work with gzipped files
#ok( compare( $out, $tmp_file ) == 0,  qq/$method stream gzipped IO drug_exposure/);
# Open the first file for reading and uncompress it
my $z1 = new IO::Uncompress::Gunzip $out;

# Open the second file for reading and uncompress it
my $z2 = new IO::Uncompress::Gunzip $tmp_file;

# Read the contents of the first file
my $content1 = do { local $/; <$z1> };

# Read the contents of the second file
my $content2 = do { local $/; <$z2> };

# Compare the contents of the two files
is($content1, $content2, qq/$method stream gzipped IO drug_exposure/);

# Close the files
$z1->close();
$z2->close();
}

# Test 3
{
my $out = 't/omop2bff/out/individuals_csv.json.gz';
my ( undef, $tmp_file ) = tempfile( DIR => 't', SUFFIX => ".json.gz", UNLINK => 1 );
my $convert = Convert::Pheno->new(
    {
        in_file              => undef,
        in_files             => ['t/omop2bff/in/gz/PERSON.csv.gz', 't/omop2bff/in/gz/CONCEPT.csv.gz', 't/omop2bff/in/gz/MEASUREMENT.csv.gz'],
        out_file             => $tmp_file,
        redcap_dictionary    => undef,
        mapping_file         => undef,
        self_validate_schema => undef,
        schema_file          => 'schema/mapping.json',
        in_textfile          => 1,
        stream               => 1,
        omop_tables          => [],
        max_lines_sql        => 2700,
        sep                  => "\t",
        test                 => 1,
        search               => 'exact',
        method               => $method
    }
);
$convert->$method;
# Does not work with gzipped files
#ok( compare( $out, $tmp_file ) == 0,  qq/$method stream gzipped IO drug_exposure/);
# Open the first file for reading and uncompress it
my $z1 = new IO::Uncompress::Gunzip $out;

# Open the second file for reading and uncompress it
my $z2 = new IO::Uncompress::Gunzip $tmp_file;

# Read the contents of the first file
my $content1 = do { local $/; <$z1> };

# Read the contents of the second file
my $content2 = do { local $/; <$z2> };

# Compare the contents of the two files
 SKIP: {
        skip qq{because 'db/ohdsi.db' is required with <ohdsi_db>}, 1
          unless -f 'db/ohdsi.db';
          is($content1, $content2, qq/$method stream gzipped IO CSV/);
    }

# Close the files
$z1->close();
$z2->close();
}
