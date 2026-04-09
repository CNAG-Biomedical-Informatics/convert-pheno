#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use IO::Uncompress::Gunzip;
use Test::ConvertPheno qw(build_convert temp_output_file has_ohdsi_db);

sub gunzip_file_content {
    my ($file) = @_;
    my $z = IO::Uncompress::Gunzip->new($file)
      or die "Cannot gunzip '$file': $IO::Uncompress::Gunzip::GunzipError";
    my $content = do { local $/; <$z> };
    $z->close();
    return $content;
}

{
    my $tmp_file = temp_output_file( suffix => '.json.gz' );
    my $convert  = build_convert(
        in_files       => ['t/omop2bff/in/gz/omop_cdm_eunomia.sql.gz'],
        out_file       => $tmp_file,
        stream         => 1,
        omop_tables    => ['DRUG_EXPOSURE'],
        max_lines_sql  => 2700,
        sep            => ',',
        method         => 'omop2bff',
    );

    $convert->omop2bff;

    is(
        gunzip_file_content('t/omop2bff/out/individuals_drug_exposure.json.gz'),
        gunzip_file_content($tmp_file),
        'omop2bff stream SQL.gz matches reference output',
    );
}

{
    my $tmp_file = temp_output_file( suffix => '.json.gz' );
    my $convert  = build_convert(
        in_files => [
            't/omop2bff/in/gz/PERSON.csv.gz',
            't/omop2bff/in/gz/CONCEPT.csv.gz',
            't/omop2bff/in/gz/DRUG_EXPOSURE.csv.gz',
        ],
        out_file      => $tmp_file,
        ohdsi_db      => 1,
        stream        => 1,
        max_lines_sql => 2700,
        sep           => "\t",
        method        => 'omop2bff',
    );

  SKIP: {
        skip q{share/db/ohdsi.db is required for streaming CSV.gz OMOP test}, 1
          unless has_ohdsi_db();
        $convert->omop2bff;
        is(
            gunzip_file_content('t/omop2bff/out/individuals_csv.json.gz'),
            gunzip_file_content($tmp_file),
            'omop2bff stream CSV.gz matches reference output',
        );
    }
}

done_testing();
