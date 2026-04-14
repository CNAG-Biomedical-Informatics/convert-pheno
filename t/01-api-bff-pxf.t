#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Convert::Pheno::IO::CSVHandler qw(get_headers);
use Test::ConvertPheno qw(
  build_convert
  read_first_json_object
  temp_output_file
  write_json_file
  write_csv_rows
  structured_files_match
);

my @cases = (
    {
        name     => 'bff2pxf',
        method   => 'bff2pxf',
        in_file  => 't/bff2pxf/in/individuals.json',
        out_file => 't/bff2pxf/out/pxf.json',
        writer   => 'json',
    },
    {
        name     => 'pxf2bff_json',
        method   => 'pxf2bff',
        in_file  => 't/pxf2bff/in/pxf.json',
        out_file => 't/pxf2bff/out/individuals.json',
        writer   => 'json',
    },
    {
        name     => 'pxf2bff_yaml',
        method   => 'pxf2bff',
        in_file  => 't/pxf2bff/in/pxf.yaml',
        out_file => 't/pxf2bff/out/individuals.yaml',
        writer   => 'json',
    },
    {
        name     => 'bff2csv',
        method   => 'bff2csv',
        in_file  => 't/bff2pxf/in/individuals.json',
        out_file => 't/bff2csv/out/individuals.csv',
        writer   => 'csv',
    },
    {
        name     => 'bff2jsonf',
        method   => 'bff2jsonf',
        in_file  => 't/bff2pxf/in/individuals.json',
        out_file => 't/bff2jsonf/out/individuals.fold.json',
        writer   => 'json',
    },
    {
        name     => 'pxf2csv',
        method   => 'pxf2csv',
        in_file  => 't/pxf2bff/in/pxf.json',
        out_file => 't/pxf2csv/out/pxf.csv',
        writer   => 'csv',
    },
    {
        name     => 'pxf2jsonf',
        method   => 'pxf2jsonf',
        in_file  => 't/pxf2bff/in/pxf.json',
        out_file => 't/pxf2jsonf/out/pxf.fold.json',
        writer   => 'json',
    },
);

for my $case (@cases) {
    my $tmp_file = temp_output_file(
        suffix => $case->{writer} eq 'csv' ? '.csv' : '.json'
    );

    my $convert = build_convert(
        in_file  => $case->{in_file},
        out_file => $tmp_file,
        method   => $case->{method},
    );

    if ( $case->{writer} eq 'csv' ) {
        my $data = $convert->${ \$case->{method} };
        my $headers = get_headers($data);
        write_csv_rows( $tmp_file, $headers, $data );
    }
    else {
        my $suffix = $case->{out_file} =~ /\.ya?ml$/ ? '.yaml' : '.json';
        $tmp_file =~ s/\.[^.]+$/$suffix/;
        write_json_file( $tmp_file, $convert->${ \$case->{method} } );
    }

    my $match =
      $case->{writer} eq 'csv'
      ? Test::ConvertPheno::json_files_match( $case->{out_file}, $tmp_file )
      : structured_files_match( $case->{out_file}, $tmp_file );
    ok( $match, $case->{name} );
}

{
    my $bff = read_first_json_object('t/bff2pxf/in/individuals.json');
    my $pxf = read_first_json_object('t/bff2pxf/out/pxf.json');

    $pxf->{$_} = undef for qw(id metaData);

    my $convert = build_convert(
        in_textfile => 0,
        data        => $bff,
        method      => 'bff2pxf',
    );

    my $got = $convert->bff2pxf;
    $got->{$_} = undef for qw(id metaData);

    is_deeply( $got, $pxf, 'bff2pxf module conversion matches fixture' );
}

{
    my $bff = {
        id   => 'subject-1',
        sex  => { id => 'NCIT:C20197', label => 'male' },
        info => {
            phenopacket => {
                dateOfBirth    => '1980-01-02',
                biosamples     => [ { id => 'bio-1' } ],
                interpretations => [ { id => 'int-1' } ],
                files          => [ { uri => 'file://example' } ],
                genes          => [ { id => 'HGNC:5' } ],
                variants       => [ { id => 'var-1' } ],
                pedigree       => { id => 'ped-1' },
            },
        },
        phenotypicFeatures => [
            {
                featureType => { id => 'HP:0000118', label => 'Phenotypic abnormality' },
                onset       => { iso8601duration => 'P6M' },
                evidence    => {
                    evidenceCode => { id => 'ECO:0000033', label => 'author statement supported by traceable reference' },
                    reference    => {
                        id    => 'PMID:123',
                        notes => 'paper title',
                    },
                    info => {
                        phenopacket => {
                            evidence => [
                                {
                                    evidenceCode => { id => 'ECO:0000033', label => 'author statement supported by traceable reference' },
                                    reference    => {
                                        id          => 'PMID:123',
                                        description => 'paper title',
                                    },
                                }
                            ],
                        },
                    },
                },
            },
        ],
        interventionsOrProcedures => [
            {
                procedureCode   => { id => 'NCIT:C28743', label => 'Biopsy' },
                ageAtProcedure  => { iso8601duration => 'P20Y' },
            },
            {
                procedureCode   => { id => 'NCIT:C5189', label => 'Surgery' },
                dateOfProcedure => '2021-01-02',
            },
            {
                procedureCode => { id => 'NCIT:C111', label => 'Code only procedure' },
            },
        ],
        measures => [
            {
                assayCode         => { id => 'LOINC:1234-5', label => 'Example assay' },
                observationMoment => { iso8601duration => 'P2Y' },
                measurementValue  => {
                    typedQuantities => [
                        {
                            quantityType => { id => 'NCIT:C25208', label => 'Quantity' },
                            quantity     => {
                                unit  => { id => 'NCIT:C28253', label => 'Milligram' },
                                value => 10,
                            },
                        },
                    ],
                },
            },
            {
                assayCode        => { id => 'LOINC:3141-9', label => 'Weight' },
                date             => '2021-09-24',
                measurementValue => {
                    quantity => {
                        unit  => { id => 'NCIT:C28252', label => 'Kilogram' },
                        value => 85.6,
                    },
                },
            },
        ],
    };

    my $convert = build_convert(
        in_textfile => 0,
        data        => $bff,
        method      => 'bff2pxf',
    );

    my $got = $convert->bff2pxf;

    is( $got->{subject}{dateOfBirth}, '1980-01-02', 'bff2pxf restores dateOfBirth from info.phenopacket' );
    is( $got->{biosamples}[0]{id}, 'bio-1', 'bff2pxf restores biosamples from info.phenopacket' );
    is( $got->{interpretations}[0]{id}, 'int-1', 'bff2pxf restores interpretations from info.phenopacket' );
    is( $got->{files}[0]{uri}, 'file://example', 'bff2pxf restores files from info.phenopacket' );
    is( $got->{genes}[0]{id}, 'HGNC:5', 'bff2pxf restores genes from info.phenopacket' );
    is( $got->{variants}[0]{id}, 'var-1', 'bff2pxf restores variants from info.phenopacket' );
    is( $got->{pedigree}{id}, 'ped-1', 'bff2pxf restores pedigree from info.phenopacket' );

    is( $got->{phenotypicFeatures}[0]{type}{id}, 'HP:0000118', 'bff2pxf renames featureType to type without mutating source' );
    is( $got->{phenotypicFeatures}[0]{onset}{age}{iso8601duration}, 'P6M', 'bff2pxf wraps onset back into a Phenopackets time element' );
    is( $got->{phenotypicFeatures}[0]{evidence}[0]{reference}{description}, 'paper title', 'bff2pxf restores evidence arrays and reference descriptions' );

    is( $got->{medicalActions}[0]{procedure}{performed}{age}{iso8601duration}, 'P20Y', 'bff2pxf maps ageAtProcedure back to performed.age' );
    is( $got->{medicalActions}[1]{procedure}{performed}{timestamp}, '2021-01-02T00:00:00Z', 'bff2pxf maps dateOfProcedure back to performed.timestamp' );
    ok( !exists $got->{medicalActions}[2]{procedure}{performed}, 'bff2pxf does not fabricate performed when procedure timing is absent' );
    ok( !exists $got->{medicalActions}[2]{procedure}{bodySite}, 'bff2pxf does not fabricate bodySite when it is absent' );

    is( $got->{measurements}[0]{timeObserved}{age}{iso8601duration}, 'P2Y', 'bff2pxf wraps observationMoment back into timeObserved' );
    is( $got->{measurements}[0]{complexValue}{typedQuantities}[0]{type}{id}, 'NCIT:C25208', 'bff2pxf restores quantityType to type inside complexValue' );
    is( $got->{measurements}[1]{timeObserved}{timestamp}, '2021-09-24T00:00:00Z', 'bff2pxf derives timeObserved from Beacon measure date when needed' );

    is( $bff->{phenotypicFeatures}[0]{featureType}{id}, 'HP:0000118', 'bff2pxf does not mutate the input BFF record' );
}

{
    my $bff = {
        id   => 'subject-2',
        info => {
            phenopacket => {
                vitalStatus => {
                    status       => 'DECEASED',
                    causeOfDeath => { id => 'MONDO:0100096', label => 'COVID-19' },
                },
            },
        },
    };

    my $convert = build_convert(
        in_textfile => 0,
        data        => $bff,
        method      => 'bff2pxf',
        default_vital_status => 'UNKNOWN_STATUS',
    );

    my $got = $convert->bff2pxf;

    is( $got->{subject}{vitalStatus}{status}, 'DECEASED', 'bff2pxf prefers preserved Phenopackets vitalStatus over the default fallback' );
    is( $got->{subject}{vitalStatus}{causeOfDeath}{id}, 'MONDO:0100096', 'bff2pxf restores preserved vitalStatus details' );
}

{
    my $bff = {
        id => 'subject-3',
    };

    my $convert = build_convert(
        in_textfile => 0,
        data        => $bff,
        method      => 'bff2pxf',
        default_vital_status => 'UNKNOWN_STATUS',
    );

    my $got = $convert->bff2pxf;

    is( $got->{subject}{vitalStatus}{status}, 'UNKNOWN_STATUS', 'bff2pxf uses the configured default vitalStatus when no source value is available' );
}

{
    my $bff = {
        id => 'subject-4',
        diseases => [
            {
                diseaseCode => { id => 'MONDO:0000001', label => 'disease 1' },
                _visit      => { occurrence_id => 42 },
            },
        ],
        treatments => [
            {
                treatmentCode => { id => 'NCIT:C123', label => 'Treatment X' },
                _info         => { field => 'DrugName' },
                _visit        => { occurrence_id => 42 },
            },
        ],
    };

    my $convert = build_convert(
        in_textfile => 0,
        data        => $bff,
        method      => 'bff2pxf',
    );

    my $got = $convert->bff2pxf;

    ok( !exists $got->{diseases}[0]{_visit}, 'bff2pxf strips private disease helper fields from Phenopackets output' );
    ok( !exists $got->{medicalActions}[0]{treatment}{_info}, 'bff2pxf strips private treatment helper fields from Phenopackets output' );
    ok( !exists $got->{medicalActions}[0]{treatment}{_visit}, 'bff2pxf strips private visit helper fields from Phenopackets output' );
}

{
    use Convert::Pheno::CSV qw(do_pxf2csv);
    use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);

    my $pxf = read_first_json_object('t/pxf2bff/in/pxf.json');
    my $row = do_pxf2csv( bless( {}, 'Convert::Pheno' ), $pxf );
    my @ref_keys = grep { ref $row->{$_} } keys %{$row};

    is_deeply( \@ref_keys, [], 'pxf2csv normalizes folded ref values to CSV-safe scalars' );
    is( $row->{'diseases:0.excluded'}, 'false', 'pxf2csv preserves folded JSON booleans as scalar text' );
    is(
        $row->{'interpretations:1.diagnosis.genomicInterpretations:0.variantInterpretation.variationDescriptor.variation.allele.literalSequenceExpression'},
        '{}',
        'pxf2csv preserves folded empty hashes as JSON text'
    );
}

done_testing();
