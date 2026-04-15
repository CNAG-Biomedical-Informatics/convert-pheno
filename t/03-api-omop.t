#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Warn;
use Test::ConvertPheno
  qw(build_convert temp_output_file has_ohdsi_db structured_files_match load_csv_table);
use File::Temp qw(tempdir);
use File::Spec;

my @snapshot_cases = (
    {
        name     => 'omop2bff',
        method   => 'omop2bff',
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        sep      => ',',
        out_file => 't/omop2bff/out/individuals.json',
    },
    {
        name     => 'omop2pxf',
        method   => 'omop2pxf',
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        sep      => ',',
        out_file => 't/omop2pxf/out/pxf.json',
    },
);

for my $case (@snapshot_cases) {
    my $tmp_file = temp_output_file();
    my $convert  = build_convert(
        in_files  => $case->{in_files},
        sep       => $case->{sep},
        out_file  => $tmp_file,
        method    => $case->{method},
    );

    $convert->${ \$case->{method} };

    ok( structured_files_match( $case->{out_file}, $tmp_file ), $case->{name} );
}

{
    my $convert = build_convert(
        in_files => [
            't/omop2bff/in/CONCEPT.csv',
            't/omop2bff/in/DRUG_EXPOSURE.csv',
            't/omop2bff/in/PERSON.csv',
            't/omop2bff/in/DUMMY.csv',
        ],
        out_file => temp_output_file(),
        ohdsi_db => 1,
        method   => 'omop2bff',
    );

  SKIP: {
        skip q{share/db/ohdsi.db is required for OMOP warning test}, 1
          unless has_ohdsi_db();
        warning_is { $convert->omop2bff }
          qq(<DUMMY> is not a valid table in OMOP-CDM\n),
          'warns on unsupported OMOP table';
    }
}

{
    my $convert = build_convert(
        in_files => [
            't/omop2bff/in/CONCEPT.csv',
            't/omop2bff/in/DRUG_EXPOSURE.csv',
            't/omop2bff/in/PERSON.csv',
        ],
        out_file => temp_output_file(),
        ohdsi_db => 1,
        method   => 'omop2bff',
    );

  SKIP: {
        skip q{share/db/ohdsi.db is required for reduced OMOP fixture test}, 1
          unless has_ohdsi_db();
        my $tmp_file = $convert->{out_file};
        $convert->omop2bff;
        ok( structured_files_match( 't/omop2bff/out/ohdsi.json', $tmp_file ),
            'omop2bff with OHDSI db matches reduced fixture' );
    }
}

{
    my $out_dir = tempdir( CLEANUP => 1 );
    my $convert = build_convert(
        in_files => ['t/omop2bff/in/omop_cdm_eunomia.sql'],
        out_dir  => $out_dir,
        out_file => temp_output_file(),
        sql2csv  => 1,
        method   => 'omop2bff',
    );

    $convert->omop2bff;

    my $specimen_csv = File::Spec->catfile( $out_dir, 'SPECIMEN.csv' );
    ok( -f $specimen_csv, 'sql2csv exports SPECIMEN.csv by default for supported OMOP tables' );
    is_deeply( load_csv_table($specimen_csv), [], 'empty specimen fixture exports as an empty CSV table' );
}

done_testing();
