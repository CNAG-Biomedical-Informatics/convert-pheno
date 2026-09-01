#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Temp qw(tempfile);
use Storable qw(dclone);
use Test::Exception;
use Test::More;

use Convert::Pheno::IO::CSVHandler qw(read_mapping_file);
use Convert::Pheno::Mapping::Compiler qw(
  compile_mapping
  load_mapping_document
);
use Test::ConvertPheno qw(write_json_file);

sub base_mapping {
    return {
        mappingVersion => 2,
        source         => { profile => 'csv' },
        target         => {
            model         => 'beacon',
            schemaVersion => '2.0.0',
        },
        project => {
            id      => 'mapping_contract_test',
            version => '1',
        },
        defaults => { ontology => 'ncit' },
        records  => {},
        beacon   => {
            individuals => {
                id => {
                    sourceFields => ['PatientId'],
                    primaryKey   => 'PatientId',
                },
                sex => {
                    sourceField => 'Sex',
                    query       => 'Biological Sex',
                },
            },
        },
    };
}

sub base_sdtm_mapping {
    return {
        mappingVersion => 2,
        source         => { profile => 'sdtm' },
        target         => {
            model         => 'beacon',
            schemaVersion => '2.0.0',
        },
        project  => { id => 'sdtm_terms_test', version => '1' },
        defaults => { ontology => 'ncit' },
        terminology => {
            'AE.AESEV' => {
                terms => {
                    MILD => {
                        id    => 'NCIT:C70666',
                        label => 'Mild',
                    },
                },
            },
        },
    };
}

sub base_metadata_mapping {
    return {
        mappingVersion => 2,
        source         => { profile => 'omop' },
        target         => {
            model         => 'beacon',
            schemaVersion => '2.0.0',
        },
        project => {
            id          => 'omop-study',
            version     => '2026.1',
            description => 'OMOP metadata overlay test',
        },
        beacon => {
            datasets => {
                defaults => {
                    name        => 'OMOP study dataset',
                    externalUrl => 'https://example.org/datasets/omop-study',
                },
            },
            cohorts => {
                defaults => {
                    name       => 'OMOP study cohort',
                    cohortType => 'study-defined',
                },
            },
        },
    };
}

my $compiled;
lives_ok {
    $compiled = compile_mapping(
        base_mapping(),
        source_profile => 'csv',
        headers        => [qw(PatientId Sex)],
    );
}
'a valid mapping v2 contract compiles';

is( $compiled->{_compiled}{sourceProfile}, 'csv', 'compiler records the selected source profile' );
is( $compiled->{target}{schemaVersion}, '2.0.0', 'mapping declares the supported Beacon schema version' );
is(
    $compiled->{beacon}{individuals}{sex}{target}{query}{literal},
    'Biological Sex',
    'a concise fixed-label query is normalized for execution',
);

{
    my ( $fh, $file ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    write_json_file( $file, base_metadata_mapping() );

    my $validated;
    lives_ok {
        $validated = read_mapping_file(
            {
                mapping_file         => $file,
                schema_file          => 'share/schema/mapping-v2.json',
                self_validate_schema => 0,
            }
        );
    }
    'a compact OMOP metadata mapping follows the mapping v2 schema';

    my $compiled_metadata;
    lives_ok {
        $compiled_metadata = compile_mapping(
            $validated,
            source_profile => 'omop',
        );
    }
    'a compact OMOP metadata mapping compiles without source headers';
    is(
        $compiled_metadata->{beacon}{datasets}{defaults}{name},
        'OMOP study dataset',
        'metadata compilation preserves dataset defaults',
    );
}

{
    my $project_only = base_metadata_mapping();
    delete $project_only->{beacon};

    my ( $fh, $file ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    write_json_file( $file, $project_only );

    lives_ok {
        read_mapping_file(
            {
                mapping_file         => $file,
                schema_file          => 'share/schema/mapping-v2.json',
                self_validate_schema => 0,
            }
        );
    }
    'project metadata alone is a valid compact mapping';
}

{
    my $mapping = base_metadata_mapping();
    $mapping->{beacon}{individuals} = {
        id => {
            sourceFields => ['person_id'],
            primaryKey   => 'person_id',
        },
    };
    my ( $fh, $file ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    write_json_file( $file, $mapping );

    dies_ok {
        read_mapping_file(
            {
                mapping_file         => $file,
                schema_file          => 'share/schema/mapping-v2.json',
                self_validate_schema => 0,
            }
        );
    }
    'metadata-only profiles cannot replace built-in individual mappings';
}

{
    my ( $fh, $file ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    write_json_file( $file, base_sdtm_mapping() );

    my $validated;
    lives_ok {
        $validated = read_mapping_file(
            {
                mapping_file         => $file,
                schema_file          => 'share/schema/mapping-v2.json',
                self_validate_schema => 0,
            }
        );
    }
    'an SDTM terminology map may use reviewed per-value terms without a DB query';

    my $compiled_sdtm = compile_mapping(
        $validated,
        source_profile => 'sdtm',
        headers        => [qw(DM.USUBJID AE.AESEV)],
    );
    is(
        $compiled_sdtm->{terminology}{'AE.AESEV'}{terms}{MILD}{id},
        'NCIT:C70666',
        'the compact SDTM terminology dictionary survives compilation',
    );
}

{
    my $mapping = base_mapping();
    delete $mapping->{mappingVersion};
    throws_ok { compile_mapping( $mapping, source_profile => 'csv' ) }
    qr/pre-v2 layout/,
      'mapping files without a version receive a migration error';
}

{
    my $mapping = base_mapping();
    $mapping->{mappingVersion} = 3;
    throws_ok { compile_mapping( $mapping, source_profile => 'csv' ) }
    qr/Unsupported mappingVersion <3>/,
      'unsupported mapping language versions are rejected';
}

{
    my $mapping = base_mapping();
    $mapping->{target}{schemaVersion} = '2.1.0';
    throws_ok { compile_mapping( $mapping, source_profile => 'csv' ) }
    qr/Unsupported Beacon target schema version <2\.1\.0>/,
      'unsupported Beacon schema versions are rejected';
}

throws_ok { compile_mapping( base_mapping(), source_profile => 'redcap' ) }
qr/Mapping source profile mismatch/,
  'the normalized conversion route must match the declared source profile';

{
    my $mapping = base_mapping();
    $mapping->{source}{profile} = 'redcap';
    my $compiled_cdisc = compile_mapping(
        $mapping,
        source_profile => 'cdisc-odm',
        record_profile => 'redcap',
        headers        => [qw(PatientId Sex)],
    );
    is(
        $compiled_cdisc->{_compiled}{sourceProfile},
        'cdisc-odm',
        'compiler retains the actual CDISC-ODM source route',
    );
    is(
        $compiled_cdisc->{_compiled}{recordProfile},
        'redcap',
        'REDCap-origin CDISC-ODM selects the REDCap record profile explicitly',
    );
}

{
    my $mapping = base_mapping();
    $mapping->{source}{profile} = 'cdisc-odm';
    my $compiled_cdisc = compile_mapping(
        $mapping,
        source_profile => 'cdisc-odm',
        record_profile => 'cdisc-odm',
        headers        => [qw(PatientId Sex)],
    );
    is(
        $compiled_cdisc->{_compiled}{recordProfile},
        'cdisc-odm',
        'generic CDISC-ODM uses its embedded-metadata record profile',
    );
}

throws_ok {
    compile_mapping(
        base_mapping(),
        source_profile => 'csv',
        headers        => ['PatientId'],
    );
}
qr/source columns not present.*<Sex>/s,
  'missing required source columns are rejected before conversion';

{
    my $mapping = base_mapping();
    $mapping->{beacon}{individuals}{diseases} = {
        rules => [ { sourceField => 'Diagnosis' } ],
    };
    throws_ok {
        compile_mapping(
            $mapping,
            source_profile => 'csv',
            headers        => [qw(PatientId Sex Diagnosis)],
        );
    }
    qr/beacon\.individuals\.diseases\.rules\[0\].*diseaseCode/s,
      'compiled rules must provide required targets directly or through defaults';
}

{
    my $mapping = base_mapping();
    $mapping->{beacon}{individuals}{ethnicity} = {
        sourceField => 'OptionalEthnicity',
        optional    => 1,
        term        => {
            id    => 'NCIT:C16564',
            label => 'Ethnic Group',
        },
    };
    lives_ok {
        compile_mapping(
            $mapping,
            source_profile => 'csv',
            headers        => [qw(PatientId Sex)],
        );
    }
    'explicitly optional source columns may be absent';
}

{
    my ( $fh, $file ) = tempfile( SUFFIX => '.yaml', UNLINK => 1 );
    print {$fh} "mappingVersion: 2\nmappingVersion: 2\n";
    close $fh;

    throws_ok { load_mapping_document($file) }
    qr/(?:duplicate.*mappingVersion|mappingVersion.*duplicate)/i,
      'duplicate YAML keys are rejected rather than silently overwritten';
}

{
    my $mapping = dclone( base_mapping() );
    $mapping->{beacon}{individuals}{notABeaconProperty} = {};

    my ( $fh, $file ) = tempfile( SUFFIX => '.json', UNLINK => 1 );
    close $fh;
    write_json_file( $file, $mapping );

    my $validation_output = '';
    open my $stdout, '>', \$validation_output or die $!;
    {
        local *STDOUT = $stdout;
        dies_ok {
            read_mapping_file(
                {
                    mapping_file         => $file,
                    schema_file          => 'share/schema/mapping-v2.json',
                    self_validate_schema => 0,
                }
            );
        }
        'properties outside the typed mapping vocabulary are rejected';
    }
    close $stdout;
    like( $validation_output, qr/notABeaconProperty/, 'schema error identifies the unsupported property' );
}

done_testing();
