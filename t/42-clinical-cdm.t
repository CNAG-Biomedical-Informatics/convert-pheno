use strict;
use warnings;

use lib qw(./lib ../lib t/lib);

use File::Temp qw(tempdir);
use IO::Compress::Zip qw($ZipError);
use JSON::XS qw(decode_json);
use Path::Tiny qw(path);
use Test::More;

use Convert::Pheno;
use Test::ConvertPheno qw(test_ohdsi_db_dir);

my @profiles = (
    { source => 'i2b2',     fixture => 'i2b22bff',     first => '101' },
    { source => 'pcornet',  fixture => 'pcornet2bff',  first => 'P001' },
    { source => 'sentinel', fixture => 'sentinel2bff', first => 'S001' },
);

sub convert_fixture {
    my ( $profile, $target, %extra ) = @_;
    my $method = $profile->{source} . '2' . $target;
    return Convert::Pheno->new(
        {
            method   => $method,
            in_files => [ 't/' . $profile->{fixture} . '/in' ],
            test     => 1,
            %extra,
        }
    )->$method;
}

for my $profile (@profiles) {
    my $actual = convert_fixture( $profile, 'bff' );
    my $expected = decode_json(
        path( 't/' . $profile->{fixture} . '/out/individuals.json' )->slurp_raw
    );
    is_deeply(
        $actual,
        $expected,
        "$profile->{source} tables reproduce the BFF reference fixture",
    );
    is( scalar @{$actual}, 2, "$profile->{source} groups rows into two people" );
    is( $actual->[0]{id}, $profile->{first}, "$profile->{source} retains the patient identifier" );

    if ( $profile->{source} eq 'i2b2' ) {
        is(
            scalar @{ $actual->[0]{treatments} || [] },
            1,
            'i2b2 base observations map once rather than duplicating modifier rows',
        );
    }

    my $pxf = convert_fixture( $profile, 'pxf' );
    is( scalar @{$pxf}, 2, "$profile->{source} to PXF reuses the complete BFF pipeline" );
    is( $pxf->[0]{subject}{id}, $profile->{first}, "$profile->{source} PXF retains the patient identifier" );

    my $omop = convert_fixture(
        $profile,
        'omop',
        ohdsi_db         => 1,
        path_to_ohdsi_db => test_ohdsi_db_dir(),
    );
    is( scalar @{ $omop->{PERSON} }, 2, "$profile->{source} to OMOP emits one PERSON row per patient" );
    ok( @{ $omop->{CONDITION_OCCURRENCE} || [] }, "$profile->{source} to OMOP emits conditions" );
}

{
    my $actual = convert_fixture( $profiles[1], 'bff', source_info => 0 );
    ok(
        !exists $actual->[0]{info}{pcornet},
        '--no-source-info semantics omit raw PCORnet tables',
    );
    ok(
        exists $actual->[0]{info}{phenopacket}{dateOfBirth},
        'derived Phenopackets metadata remains available without raw source provenance',
    );
}

{
    my $input = {
        PATIENT_DIMENSION => [
            { PATIENT_NUM => 'M001', SEX_CD => 'F' },
        ],
        OBSERVATION_FACT => [],
    };
    my $before = JSON::XS->new->canonical->encode($input);
    my $actual = Convert::Pheno->new(
        {
            method => 'i2b22bff',
            data   => $input,
            test   => 1,
        }
    )->i2b22bff;
    is( $actual->[0]{id}, 'M001', 'i2b2 accepts an in-memory table object' );
    is(
        JSON::XS->new->canonical->encode($input),
        $before,
        'clinical CDM conversion does not modify caller-owned tables',
    );
}

{
    my $workspace = tempdir( CLEANUP => 1 );
    my $zip_file = path($workspace)->child('i2b2.zip')->stringify;
    my @files = sort glob 't/i2b22bff/in/*.csv';
    my $zip;
    for my $file (@files) {
        my $name = path($file)->basename;
        if ($zip) {
            $zip->newStream( Name => $name ) or die $ZipError;
        }
        else {
            $zip = IO::Compress::Zip->new( $zip_file, Name => $name )
              or die $ZipError;
        }
        $zip->print( path($file)->slurp_raw );
    }
    $zip->close;

    my $actual = Convert::Pheno->new(
        {
            method   => 'i2b22bff',
            in_files => [$zip_file],
            test     => 1,
        }
    )->i2b22bff;
    is( scalar @{$actual}, 2, 'i2b2 accepts a ZIP package of exported tables' );
}

{
    my $error;
    eval {
        Convert::Pheno->new(
            {
                method => 'pcornet2bff',
                data   => {
                    DEMOGRAPHIC => [ { PATID => 'P001', SEX => 'F' } ],
                    DIAGNOSIS   => [ { PATID => 'P999', DX => 'I10', DX_TYPE => '10' } ],
                },
                test => 1,
            }
        )->pcornet2bff;
        1;
    } or $error = $@;
    like(
        $error,
        qr/references unknown patient <P999>/,
        'cross-table references to unknown patients fail before conversion',
    );
}

{
    my $error;
    eval {
        Convert::Pheno->new(
            {
                method => 'sentinel2bff',
                data   => {
                    DEMOGRAPHIC => [ { PATID => 'S001', SEX => 'F' } ],
                    DIAGNOSIS   => [ { DX => 'J45.909', DX_TYPE => '10' } ],
                },
                test => 1,
            }
        )->sentinel2bff;
        1;
    } or $error = $@;
    like(
        $error,
        qr/table <DIAGNOSIS> row is missing a patient identifier/,
        'patient-scoped rows without a patient identifier are rejected',
    );
}

done_testing;
