#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use IO::Compress::Zip qw($ZipError);
use JSON::XS;
use Path::Tiny qw(path);
use Test::Exception;
use Test::More;

use Convert::Pheno;
use Convert::Pheno::Source qw(source_adapter);
use Test::ConvertPheno qw(
  cli_script_path
  load_json_file
  run_command_capture
  test_ohdsi_db_dir
);

my $fixture_dir = 't/cbioportal2bff/in/acyc_mgh_2016';
my @fixture_files = qw(
  meta_study.txt
  meta_clinical_patient.txt
  meta_clinical_sample.txt
  data_clinical_patient.txt
  data_clinical_sample.txt
  case_lists/cases_all.txt
);

sub memory_fixture {
    my %files = map {
        my $name = $_;
        ( "study/$name" => path( $fixture_dir, split m{/}, $name )->slurp_utf8 )
    } @fixture_files;
    return { files => \%files };
}

sub write_fixture_zip {
    my ( $zip_file, $files ) = @_;
    my @names = sort keys %{$files};
    my $first = shift @names;
    my $zip = IO::Compress::Zip->new(
        $zip_file,
        Name          => $first,
        CanonicalName => 1,
    ) or die "Cannot create cBioPortal test ZIP: $ZipError";
    $zip->print( $files->{$first} )
      or die "Cannot write cBioPortal test ZIP member <$first>: $ZipError";
    for my $name (@names) {
        $zip->newStream( Name => $name, CanonicalName => 1 )
          or die "Cannot create cBioPortal test ZIP member <$name>: $ZipError";
        $zip->print( $files->{$name} )
          or die "Cannot write cBioPortal test ZIP member <$name>: $ZipError";
    }
    $zip->close or die "Cannot close cBioPortal test ZIP: $ZipError";
    return $zip_file;
}

{
    my $source = source_adapter(
        Convert::Pheno->new(
            {
                method  => 'cbioportal2bff',
                in_file => $fixture_dir,
                test    => 1,
            }
        ),
        'cbioportal',
    )->load;

    is( scalar @{ $source->data }, 10, 'cBioPortal source emits one record per patient' );
    is( $source->data->[0]{patient}{PATIENT_ID}, 'ACCX12', 'patient order follows the clinical table' );
    is( $source->data->[0]{samples}[0]{SAMPLE_ID}, 'ACCX12', 'samples remain linked to their patient' );
    is( $source->artifact('study')->{id}, 'acyc_mgh_2016', 'study metadata is exposed by the source adapter' );
    is( scalar @{ $source->artifact('study')->{caseLists} }, 1, 'case lists are discovered from the study package' );
}

{
    my $convert = Convert::Pheno->new(
        {
            method   => 'cbioportal2bff',
            in_file  => $fixture_dir,
            entities => [qw(individuals biosamples datasets cohorts)],
            test     => 1,
        }
    );
    my $bundle = $convert->_run_bundle_view;
    my $individual = $bundle->entities('individuals')->[0];
    my $biosample  = $bundle->entities('biosamples')->[0];

    is( scalar @{ $bundle->entities('individuals') }, 10, 'clinical patients map to BFF individuals' );
    is( scalar @{ $bundle->entities('biosamples') }, 10, 'clinical samples map to BFF biosamples' );
    is( $individual->{diseases}[0]{diseaseCode}{id}, 'OncoTree:ACYC', 'OncoTree code maps to a disease term' );
    is( $biosample->{individualId}, 'ACCX12', 'BFF biosample retains its patient link' );
    is( $biosample->{histologicalDiagnosis}{id}, 'OncoTree:ACYC', 'OncoTree code maps to histological diagnosis' );
    is( $biosample->{sampleOriginType}{id}, 'NCIT:C126101', 'an unverified SAMPLE_TYPE uses Not Available' );
    is( $biosample->{info}{cbioportal}{sample}{SAMPLE_TYPE}, 'Primary', 'the exact SAMPLE_TYPE remains in provenance' );
    unlike( $biosample->{sampleOriginType}{id}, qr/^cBioPortal:/, 'semantic fields do not receive invented source-local CURIEs' );
    is( $bundle->entities('datasets')->[0]{id}, 'acyc_mgh_2016', 'study metadata maps to a BFF dataset' );
    is( $bundle->entities('cohorts')->[0]{cohortSize}, 10, 'case-list membership maps to cohort size' );
}

{
    my $bundle = Convert::Pheno->new(
        {
            method      => 'cbioportal2bff',
            in_file     => $fixture_dir,
            entities    => [qw(individuals biosamples cohorts)],
            source_info => 0,
            test        => 1,
        }
    )->_run_bundle_view;

    ok( !exists $bundle->entities('individuals')->[0]{info}{cbioportal}, '--no-source-info omits raw patient attributes' );
    ok( !exists $bundle->entities('biosamples')->[0]{info}{cbioportal}, '--no-source-info omits raw sample attributes' );
    ok( exists $bundle->entities('cohorts')->[0]{info}{cbioportal}{membership}, 'semantic cohort membership remains without raw provenance' );
}

{
    my $bundle = Convert::Pheno->new(
        {
            method       => 'cbioportal2bff',
            in_file      => $fixture_dir,
            mapping_file => 't/cbioportal2bff/in/cbioportal_mapping.yaml',
            schema_file  => 'share/schema/mapping-v2.json',
            entities     => [qw(individuals biosamples)],
            test         => 1,
        }
    )->_run_bundle_view;

    is( $bundle->entities('individuals')->[0]{info}{STUDY}, 'ACyC (MGH 2016)', 'optional mapping augments patient semantics' );
    is( $bundle->entities('biosamples')->[0]{info}{PLATFORM}, 'WGS', 'optional mapping augments sample semantics' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $zip_file = File::Spec->catfile( $tmpdir, 'study.zip' );
    write_fixture_zip( $zip_file, memory_fixture()->{files} );

    my $source = source_adapter(
        Convert::Pheno->new(
            {
                method  => 'cbioportal2bff',
                in_file => $zip_file,
                test    => 1,
            }
        ),
        'cbioportal',
    )->load;
    is( scalar @{ $source->data }, 10, 'ZIP packages use the same cBioPortal normalization path' );
    is( $source->artifact('study')->{sampleCount}, 10, 'ZIP package preserves study counts' );
}

{
    my $bad = memory_fixture();
    $bad->{files}{'study/case_lists/cases_all.txt'} =~
      s/^case_list_ids:.*$/case_list_ids: UNKNOWN_SAMPLE/m;
    throws_ok {
        source_adapter(
            Convert::Pheno->new(
                {
                    method => 'cbioportal2bff',
                    data   => $bad,
                    test   => 1,
                }
            ),
            'cbioportal',
        )->load;
    }
    qr/references unknown SAMPLE_ID <UNKNOWN_SAMPLE>/,
      'unknown case-list sample references fail before conversion';
}

{
    my $without_patients = memory_fixture();
    delete $without_patients->{files}{'study/meta_clinical_patient.txt'};
    delete $without_patients->{files}{'study/data_clinical_patient.txt'};
    my $source = source_adapter(
        Convert::Pheno->new(
            {
                method => 'cbioportal2bff',
                data   => $without_patients,
                test   => 1,
            }
        ),
        'cbioportal',
    )->load;
    is( scalar @{ $source->data }, 10, 'patients can be derived when the optional patient table is absent' );
    is( $source->data->[0]{patient}{PATIENT_ID}, 'ACCX12', 'derived patients retain sample-table identifiers' );
}

{
    my $out_dir = tempdir( CLEANUP => 1 );
    my ( $status, undef, $stderr ) = run_command_capture(
        command => [
            $^X,
            cli_script_path(),
            '-icbioportal', $fixture_dir,
            '-obff',
            '--entities', qw(individuals biosamples datasets cohorts),
            '--out-dir', $out_dir,
            '-O',
            '--test',
        ],
    );
    is( $status, 0, 'CLI writes entity-aware cBioPortal BFF output' ) or diag $stderr;
    for my $entity (qw(individuals biosamples datasets cohorts)) {
        ok( -s File::Spec->catfile( $out_dir, "$entity.json" ), "CLI writes $entity.json" );
    }
}

{
    my ( $fh, $outfile ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    my ( $status, undef, $stderr ) = run_command_capture(
        command => [
            $^X,
            cli_script_path(),
            '-icbioportal', $fixture_dir,
            '-opxf', $outfile,
            '-O',
            '--test',
        ],
    );
    is( $status, 0, 'CLI accepts cBioPortal study directories' ) or diag $stderr;
    my $pxf = load_json_file($outfile);
    is( scalar @{$pxf}, 10, 'cBioPortal to PXF emits one Phenopacket per patient' );
    is( $pxf->[0]{biosamples}[0]{sampleType}{id}, 'NCIT:C126101', 'PXF does not inherit an invented SAMPLE_TYPE CURIE' );
}

{
    my $out_dir = tempdir( CLEANUP => 1 );
    my ( $status, undef, $stderr ) = run_command_capture(
        command => [
            $^X,
            cli_script_path(),
            '-icbioportal', $fixture_dir,
            '-oomop',
            '--out-dir', $out_dir,
            '--ohdsi-db',
            '--path-to-ohdsi-db', test_ohdsi_db_dir(),
            '-O',
            '--test',
        ],
    );
    is( $status, 0, 'CLI accepts cBioPortal to OMOP conversion' ) or diag $stderr;
    ok( -s File::Spec->catfile( $out_dir, 'PERSON.csv' ), 'cBioPortal to OMOP writes PERSON' );
    ok( -s File::Spec->catfile( $out_dir, 'CONDITION_OCCURRENCE.csv' ), 'cBioPortal to OMOP writes conditions' );
}

done_testing();
