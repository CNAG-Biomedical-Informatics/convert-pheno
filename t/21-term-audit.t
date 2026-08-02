#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Spec;
use Test::Exception;
use Test::More;
use Convert::Pheno::CLI::Args qw(build_cli_request);
use Test::ConvertPheno qw(build_convert temp_output_file slurp_file gunzip_file_content test_tmpdir);

my $tmpdir = test_tmpdir();

{
    my $request = build_cli_request(
        argv => [
            '-icsv', 't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '-obff', 'individuals.json',
            '--term-audit-tsv', 'term-audit.tsv',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );

    is( $request->{action}, 'run', 'CLI parser returns a run action for terminology audit requests' );
    is(
        $request->{data}{term_audit_file},
        File::Spec->catfile( $tmpdir, 'term-audit.tsv' ),
        'CLI parser resolves --term-audit-tsv relative to --out-dir'
    );
}

{
    my $request = build_cli_request(
        argv => [
            '-icsv', 't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '-obff', 'individuals.json',
            '--term-audit-tsv', 'term-audit.tsv.gz',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );

    is(
        $request->{data}{term_audit_file},
        File::Spec->catfile( $tmpdir, 'term-audit.tsv.gz' ),
        'CLI parser resolves gzipped --term-audit-tsv relative to --out-dir'
    );
}

{
    my $audit_file = temp_output_file( suffix => '.tsv', dir => $tmpdir );
    my $convert = build_convert(
        in_file           => 't/csv2bff/in/csv_data.csv',
        mapping_file      => 't/csv2bff/in/csv_mapping.yaml',
        sep               => ',',
        out_file          => temp_output_file(),
        method            => 'csv2bff',
        term_audit_file   => $audit_file,
    );

    my $data = $convert->csv2bff;
    ok( ref $data eq 'ARRAY' && @{$data}, 'csv2bff still returns data when terminology audit is enabled' );
    ok( -f $audit_file, 'terminology audit TSV is written when requested' );

    my @lines = grep { length } split /\n/, slurp_file($audit_file);
    is(
        $lines[0],
        join(
            "\t",
            qw(row source_record source_field source_value source_label lookup_query lookup_column converted_term_label converted_term_id ontology configured_search_mode effective_search_mode text_similarity_method min_text_similarity_score levenshtein_weight match_status match_source lookup_resolution fallback_action)
        ),
        'terminology audit TSV starts with the expected header'
    );
    cmp_ok( scalar @lines, '>', 1, 'terminology audit TSV contains at least one mapped row' );

    my @cols = split /\t/, $lines[1], -1;
    is( scalar @cols, 19, 'terminology audit TSV rows contain the expected number of columns' );
    like( $cols[0], qr/^\d+$/, 'terminology audit TSV records the source row number' );
    ok( length $cols[2], 'terminology audit TSV records the source field' );
    ok( length $cols[3], 'terminology audit TSV records the source value' );
    ok( length $cols[4], 'terminology audit TSV records the source label' );
    ok( length $cols[5], 'terminology audit TSV records the lookup query' );
    is( $cols[6], 'label', 'terminology audit TSV identifies a label lookup' );
    ok( length $cols[7], 'terminology audit TSV records the converted term label' );
    like( $cols[8], qr/^[A-Z]+:/, 'terminology audit TSV records the converted term id' );
    ok( length $cols[9], 'terminology audit TSV records the ontology name' );
    like( $cols[10], qr/^(?:exact|mixed|fuzzy)$/, 'terminology audit TSV records the configured search mode' );
    like( $cols[11], qr/^(?:exact|mixed|fuzzy|not_used)$/, 'terminology audit TSV records the effective search mode' );
    like(
        $cols[12],
        qr/^(?:cosine|dice)$/,
        'terminology audit TSV records the configured text-similarity method'
    );
    like(
        $cols[13],
        qr/^(?:0(?:\.\d+)?|1(?:\.0+)?)$/,
        'terminology audit TSV records the configured minimum text-similarity score'
    );
    like(
        $cols[14],
        qr/^(?:0(?:\.\d+)?|1(?:\.0+)?)$/,
        'terminology audit TSV records the configured Levenshtein weight'
    );
    like( $cols[15], qr/^(?:matched|configured|not_found)$/, 'terminology audit TSV records the resolution status' );
    like(
        $cols[16],
        qr/^(?:db|cache|mapping|fallback_na)$/,
        'terminology audit TSV records the resolution source'
    );
    like(
        $cols[17],
        qr/^(?:exact|similarity|direct_term|fallback_na)$/,
        'terminology audit TSV records how the term was resolved'
    );
    like( $cols[18], qr/^(?:none|na)$/, 'terminology audit TSV records the fallback action' );
}

{
    my $audit_file = temp_output_file( suffix => '.tsv.gz', dir => $tmpdir );
    my $convert = build_convert(
        in_file           => 't/csv2bff/in/csv_data.csv',
        mapping_file      => 't/csv2bff/in/csv_mapping.yaml',
        sep               => ',',
        out_file          => temp_output_file(),
        method            => 'csv2bff',
        term_audit_file   => $audit_file,
    );

    my $data = $convert->csv2bff;
    ok( ref $data eq 'ARRAY' && @{$data}, 'csv2bff still returns data when gzipped terminology audit is enabled' );
    ok( -f $audit_file, 'gzipped terminology audit TSV is written when requested' );

    my @lines = grep { length } split /\n/, gunzip_file_content($audit_file);
    is(
        $lines[0],
        join(
            "\t",
            qw(row source_record source_field source_value source_label lookup_query lookup_column converted_term_label converted_term_id ontology configured_search_mode effective_search_mode text_similarity_method min_text_similarity_score levenshtein_weight match_status match_source lookup_resolution fallback_action)
        ),
        'gzipped terminology audit TSV starts with the expected header'
    );
    cmp_ok( scalar @lines, '>', 1, 'gzipped terminology audit TSV contains at least one mapped row' );
}

throws_ok(
    sub {
        build_cli_request(
            argv => [
                '-icsv', 't/csv2bff/in/csv_data.csv',
                '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
                '-obff', 'individuals.json',
                '--search-audit-tsv', 'legacy.tsv',
            ],
            usage_error => sub { die @_ },
            schema_file => 'share/schema/mapping-v2.json',
            out_dir     => $tmpdir,
            color       => 1,
        );
    },
    qr/Invalid command-line arguments/,
    'the replaced --search-audit-tsv option is rejected'
);

done_testing();
