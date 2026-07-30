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
        source         => { profiles => ['csv'] },
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
                    source => {
                        fields     => ['PatientId'],
                        primaryKey => 'PatientId',
                    },
                },
                sex => {
                    source => { field => 'Sex' },
                    target => {
                        term => {
                            id    => 'NCIT:C28421',
                            label => 'Sex',
                        },
                    },
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
  'the conversion route must match a declared source profile';

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
    $mapping->{beacon}{individuals}{ethnicity} = {
        source => {
            field    => 'OptionalEthnicity',
            optional => 1,
        },
        target => {
            term => {
                id    => 'NCIT:C16564',
                label => 'Ethnic Group',
            },
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
                    schema_file          => 'share/schema/mapping.json',
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
