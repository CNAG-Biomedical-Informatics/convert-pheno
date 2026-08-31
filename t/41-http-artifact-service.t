use strict;
use warnings;

use lib qw(./lib ../lib t/lib);

use File::Find qw(find);
use File::Temp qw(tempdir);
use IO::Compress::Zip qw($ZipError);
use JSON::XS qw(decode_json);
use Path::Tiny qw(path);
use Test::More;
use Text::CSV_XS;

use Convert::Pheno::HTTP::Service qw(catalog execute execute_files is_service_error);
use Convert::Pheno::Operations qw(public_conversions);
use Test::ConvertPheno qw(test_ohdsi_db_dir write_zip_from_files);

sub load_json {
    return decode_json( path(shift)->slurp_raw );
}

my $catalog = catalog();
is( $catalog->{meta}{count}, 44, 'catalog exposes every public route' );
is_deeply(
    [ sort map { $_->{id} } @{ $catalog->{data} } ],
    public_conversions(),
    'catalog route list comes from the public registry'
);
my ($i2b2_omop_route) = grep { $_->{id} eq 'i2b22omop' } @{ $catalog->{data} };
ok(
    scalar( grep { $_->{name} eq 'term_audit' } @{ $i2b2_omop_route->{options} } ),
    'OMOP-target table routes expose terminology audit output',
);

sub uploaded_file {
    my ( $path, $filename ) = @_;
    return { path => $path, filename => $filename || path($path)->basename };
}

sub zip_directory {
    my ( $directory, $destination ) = @_;
    my @files;
    find( { no_chdir => 1, wanted => sub { push @files, $File::Find::name if -f $File::Find::name } }, $directory );
    my $zip;
    for my $file ( sort @files ) {
        my $name = $file;
        $name =~ s{^\Q$directory\E[\\/]*}{};
        if ($zip) {
            $zip->newStream( Name => $name ) or die $ZipError;
        }
        else {
            $zip = IO::Compress::Zip->new( $destination, Name => $name ) or die $ZipError;
        }
        $zip->print( path($file)->slurp_raw );
    }
    $zip->close;
}

{
    local $ENV{CONVERT_PHENO_OHDSI_DB_DIR} = '/missing/convert-pheno-resource';
    my ($route) = grep { $_->{id} eq 'bff2omop' } @{ catalog()->{data} };
    ok( !$route->{available}, 'OHDSI-dependent conversion remains visible when unavailable' );
    like( $route->{unavailableReason}, qr/ohdsi\.db/i, 'catalog explains the missing resource' );

    my $error;
    eval { execute( 'bff2omop', { input => { data => {} } } ); 1 }
      or $error = $@;
    ok( is_service_error($error), 'unavailable conversion returns a service error' );
    is( $error->status, 503, 'unavailable resource uses 503' );
}

local $ENV{CONVERT_PHENO_OHDSI_DB_DIR} = test_ohdsi_db_dir();

my $upload_workspace = tempdir( CLEANUP => 1 );
my $cbio_zip = path($upload_workspace)->child('acyc_mgh_2016.zip')->stringify;
zip_directory( 't/cbioportal2bff/in/acyc_mgh_2016', $cbio_zip );
my $omop_zip = path($upload_workspace)->child('omop-tables.zip')->stringify;
write_zip_from_files(
    $omop_zip,
    [ map {
        +{
            file => "t/omop2bff/in/$_.csv",
            name => "tables/$_.csv",
        }
    } qw(CONCEPT DRUG_EXPOSURE PERSON) ],
);
my @dataset_json = map { uploaded_file($_) }
  sort glob 't/datasetjson2bff/in/*.json';
my @dataset_xml = map { uploaded_file("t/datasetxml2bff/in/$_.xml") }
  qw(dm mh lb ts);

my @file_cases = (
    {
        route => 'csv2bff',
        files => {
            source  => [ uploaded_file('t/csv2bff/in/csv_data.csv') ],
            mapping => [ uploaded_file('t/csv2bff/in/csv_mapping.yaml') ],
        },
        options => { separator => ',', term_audit => 'tsv' },
    },
    {
        route => 'redcap2bff',
        files => {
            source     => [ uploaded_file('t/redcap2bff/in/redcap_data.csv') ],
            dictionary => [ uploaded_file('t/redcap2bff/in/redcap_dictionary.csv') ],
            mapping    => [ uploaded_file('t/redcap2bff/in/redcap_mapping.yaml') ],
        },
    },
    {
        route => 'cdiscodm2bff',
        files => {
            source     => [ uploaded_file('t/cdiscodm2bff/in/cdisc_odm_data.xml') ],
            dictionary => [ uploaded_file('t/redcap2bff/in/redcap_dictionary.csv') ],
            mapping    => [ uploaded_file('t/redcap2bff/in/redcap_mapping.yaml') ],
        },
    },
    {
        route => 'datasetjson2bff',
        files => { source => \@dataset_json },
    },
    {
        route => 'datasetxml2bff',
        files => {
            source => \@dataset_xml,
            define => [ uploaded_file('t/datasetxml2bff/in/define.xml') ],
        },
    },
    {
        route => 'cbioportal2bff',
        files => { source => [ uploaded_file( $cbio_zip, 'acyc_mgh_2016.zip' ) ] },
    },
    {
        route => 'i2b22bff',
        files => { source => [ uploaded_file('t/i2b22bff/in/PATIENT_DIMENSION.csv'), uploaded_file('t/i2b22bff/in/OBSERVATION_FACT.csv') ] },
    },
    {
        route => 'pcornet2bff',
        files => { source => [ uploaded_file('t/pcornet2bff/in/DEMOGRAPHIC.csv'), uploaded_file('t/pcornet2bff/in/DIAGNOSIS.csv') ] },
    },
    {
        route => 'sentinel2bff',
        files => { source => [ uploaded_file('t/sentinel2bff/in/DEMOGRAPHIC.csv'), uploaded_file('t/sentinel2bff/in/DIAGNOSIS.csv') ] },
    },
    {
        route => 'omop2bff',
        files => {
            source => [ uploaded_file( $omop_zip, 'omop-tables.zip' ) ],
        },
    },
);

my %file_response;
for my $case (@file_cases) {
    my $response = execute_files(
        $case->{route},
        {
            output  => { entities => ['individuals'] },
            options => { %{ $case->{options} || {} }, test => JSON::XS::true },
        },
        $case->{files},
        { workspace => $upload_workspace },
    );
    $file_response{ $case->{route} } = $response;
    ok( $response->{ok}, "$case->{route} succeeds through the file service" );
    is( $response->{artifacts}[0]{filename}, 'individuals.json',
        "$case->{route} returns the requested BFF entity" );
}
ok(
    scalar( grep { $_->{filename} eq 'term-audit.tsv' }
          @{ $file_response{csv2bff}{artifacts} } ),
    'file service returns the requested terminology audit artifact',
);
my $audit_review = $file_response{csv2bff}{meta}{terminologyAudit};
ok( $audit_review, 'file service returns structured terminology review metadata' );
is( $audit_review->{reportArtifactId}, 'term-audit',
    'terminology review identifies its complete downloadable report' );
is( $audit_review->{previewRows}, scalar @{ $audit_review->{rows} },
    'terminology review reports the number of retained preview rows' );
my $audit_count = 0;
$audit_count += $_ for values %{ $audit_review->{counts} };
is( $audit_count, $audit_review->{totalDecisions},
    'terminology review counts cover every audit decision' );
ok(
    !grep(
        { $_->{review_action} !~ /\A(?:keep|review_similarity|resolve_or_accept_fallback|review_source_fallback)\z/ }
          @{ $audit_review->{rows} }
    ),
    'terminology review rows use the authoritative review actions',
);

my $bff      = load_json('t/bff2omop/in/individuals.json');
my $pxf      = load_json('t/pxf2bff/in/pxf.json');
my $fhir     = load_json('t/fhir2bff/in/patient-bundle.json');
my $openehr  = load_json('t/openehr2bff/in/gecco_personendaten_patient.json');
my $omop_req = load_json('t/fixtures/http-omop-request.json');
my $omop     = $omop_req->{input}{data};

# Use a PXF generated by the Perl serializer from an OMOP-compatible BFF
# fixture for the pxf2omop route.
my $pxf_omop_artifacts = execute(
    'bff2pxf',
    { input => { data => $bff }, options => { test => JSON::XS::true } }
)->{artifacts};
my $pxf_for_omop = decode_json( $pxf_omop_artifacts->[0]{content} );

my %input_for = (
    bff      => $bff,
    fhir     => $fhir,
    omop     => $omop,
    openehr  => $openehr,
    pxf      => $pxf,
);

my $i2b2_json = execute(
    'i2b22bff',
    {
        input => {
            data => {
                PATIENT_DIMENSION => [ { PATIENT_NUM => 'HTTP-I2B2-1', SEX_CD => 'F' } ],
                OBSERVATION_FACT  => [],
            },
        },
        output  => { entities => ['individuals'] },
        options => { test => JSON::XS::true },
    }
);
ok( $i2b2_json->{ok}, 'i2b2 succeeds through the JSON artifact service' );
is(
    decode_json( $i2b2_json->{artifacts}[0]{content} )->[0]{id},
    'HTTP-I2B2-1',
    'i2b2 JSON service input retains the patient identifier',
);

my @routes = qw(
  bff2csv bff2jsonf bff2jsonld bff2omop bff2pxf
  fhir2bff fhir2omop fhir2pxf omop2bff omop2pxf
  openehr2bff openehr2pxf pxf2bff pxf2csv pxf2jsonf
  pxf2jsonld pxf2omop
);

for my $route (@routes) {
    my ($source) = $route =~ /\A(bff|fhir|omop|openehr|pxf)2/;
    my $data = $route eq 'pxf2omop' ? $pxf_for_omop : $input_for{$source};
    my $output = $route =~ /2bff\z/ ? { entities => ['individuals'] } : {};
    my $response = execute(
        $route,
        {
            input   => { data => $data },
            output  => $output,
            options => { test => JSON::XS::true },
        }
    );
    ok( $response->{ok}, "$route succeeds through the artifact service" );
    ok( @{ $response->{artifacts} } > 0, "$route returns at least one artifact" );
    for my $artifact ( @{ $response->{artifacts} } ) {
        ok( defined $artifact->{content} && !ref $artifact->{content},
            "$route returns serialized artifact content" );
        like( $artifact->{filename}, qr/\.(?:json|jsonld|csv)\z/,
            "$route returns a download filename" );
    }
}

my $fhir_multi = execute(
    'fhir2bff',
    {
        input  => { data => $fhir },
        output => { entities => [qw(individuals biosamples datasets cohorts)] },
        options => { test => JSON::XS::true },
    }
);
is_deeply(
    [ map { $_->{filename} } @{ $fhir_multi->{artifacts} } ],
    [qw(individuals.json biosamples.json datasets.json cohorts.json)],
    'FHIR emits one artifact for every requested BFF entity'
);
for my $artifact ( @{ $fhir_multi->{artifacts} } ) {
    my $expected = load_json( 't/fhir2bff/out/' . $artifact->{filename} );
    my $actual = decode_json( $artifact->{content} );
    # File and in-memory adapters intentionally identify their source
    # differently; the clinical and entity structures must otherwise match.
    for my $index ( 0 .. $#{$actual} ) {
        next unless exists $actual->[$index]{info}
          && exists $actual->[$index]{info}{fhir}
          && ref( $actual->[$index]{info}{fhir}{bundles} ) eq 'ARRAY';
        for my $bundle_index ( 0 .. $#{ $actual->[$index]{info}{fhir}{bundles} } ) {
            $expected->[$index]{info}{fhir}{bundles}[$bundle_index]{source} =
              $actual->[$index]{info}{fhir}{bundles}[$bundle_index]{source};
        }
    }
    is_deeply( $actual, $expected,
        "$artifact->{filename} matches the existing FHIR reference structurally" );
}

my $csv_response = execute(
    'bff2csv',
    { input => { data => load_json('t/bff2pxf/in/individuals.json') }, options => { test => JSON::XS::true } }
);
my $csv = Text::CSV_XS->new( { binary => 1, sep_char => ';' } );
open my $csv_fh, '<', \$csv_response->{artifacts}[0]{content};
my $generated_rows = $csv->getline_all($csv_fh);
close $csv_fh;
my $reference_rows = Text::CSV_XS::csv(
    in => 't/bff2csv/out/individuals.csv', sep_char => ';'
);
is_deeply( $generated_rows, $reference_rows,
    'CSV artifact matches the parsed CLI reference fixture' );

my $path_error;
eval {
    execute( 'pxf2bff', { input => { data => '/tmp/individuals.json' } } );
    1;
} or $path_error = $@;
is( $path_error->status, 422, 'filesystem-shaped scalar input is rejected' );

my $option_error;
eval {
    execute( 'pxf2csv', {
        input => { data => $pxf }, options => { default_vital_status => 'ALIVE' }
    } );
    1;
} or $option_error = $@;
is( $option_error->status, 422, 'route-inapplicable option is rejected' );

done_testing;
