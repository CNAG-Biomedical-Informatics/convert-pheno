#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Convert::Pheno::CLI::Args qw(build_cli_request);
use Test::ConvertPheno qw(build_convert temp_output_file slurp_file gunzip_file_content);

{
    my $request = build_cli_request(
        argv => [
            '-icsv', 't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '-obff', 'individuals.json',
            '--search-audit-tsv', 'search-audit.tsv',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping.json',
        out_dir     => '/tmp',
        color       => 1,
    );

    is( $request->{action}, 'run', 'CLI parser returns a run action for search audit requests' );
    is(
        $request->{data}{search_audit_file},
        '/tmp/search-audit.tsv',
        'CLI parser resolves --search-audit-tsv relative to --out-dir'
    );
}

{
    my $request = build_cli_request(
        argv => [
            '-icsv', 't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '-obff', 'individuals.json',
            '--search-audit-tsv', 'search-audit.tsv.gz',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping.json',
        out_dir     => '/tmp',
        color       => 1,
    );

    is(
        $request->{data}{search_audit_file},
        '/tmp/search-audit.tsv.gz',
        'CLI parser resolves gzipped --search-audit-tsv relative to --out-dir'
    );
}

{
    my $audit_file = temp_output_file( suffix => '.tsv', dir => '/tmp' );
    my $convert = build_convert(
        in_file           => 't/csv2bff/in/csv_data.csv',
        mapping_file      => 't/csv2bff/in/csv_mapping.yaml',
        sep               => ',',
        out_file          => temp_output_file(),
        method            => 'csv2bff',
        search_audit_file => $audit_file,
    );

    my $data = $convert->csv2bff;
    ok( ref $data eq 'ARRAY' && @{$data}, 'csv2bff still returns data when search audit is enabled' );
    ok( -f $audit_file, 'search audit TSV is written when requested' );

    my @lines = grep { length } split /\n/, slurp_file($audit_file);
    is(
        $lines[0],
        join(
            "\t",
            qw(row original_term_label converted_term_label converted_term_id ontology configured_search_mode text_similarity_method min_text_similarity_score levenshtein_weight match_status match_source lookup_resolution)
        ),
        'search audit TSV starts with the expected header'
    );
    cmp_ok( scalar @lines, '>', 1, 'search audit TSV contains at least one mapped row' );

    my @cols = split /\t/, $lines[1], -1;
    is( scalar @cols, 12, 'search audit TSV rows contain the expected number of columns' );
    like( $cols[0], qr/^\d+$/, 'search audit TSV records the source row number' );
    ok( length $cols[1], 'search audit TSV records the original term label' );
    ok( length $cols[2], 'search audit TSV records the converted term label' );
    like( $cols[3], qr/^[A-Z]+:/, 'search audit TSV records the converted term id' );
    ok( length $cols[4], 'search audit TSV records the ontology name' );
    like( $cols[5], qr/^(?:exact|mixed|fuzzy)$/, 'search audit TSV records the effective search mode' );
    like(
        $cols[6],
        qr/^(?:cosine|dice)$/,
        'search audit TSV records the configured text-similarity method'
    );
    like(
        $cols[7],
        qr/^(?:0(?:\.\d+)?|1(?:\.0+)?)$/,
        'search audit TSV records the configured minimum text-similarity score'
    );
    like(
        $cols[8],
        qr/^(?:0(?:\.\d+)?|1(?:\.0+)?)$/,
        'search audit TSV records the configured Levenshtein weight'
    );
    like( $cols[9], qr/^(?:matched|not_found)$/, 'search audit TSV records whether the DB lookup matched' );
    like(
        $cols[10],
        qr/^(?:db|cache|fallback_na)$/,
        'search audit TSV records whether the result came from the DB, cache, or fallback'
    );
    like(
        $cols[11],
        qr/^(?:exact|similarity|fallback_na)$/,
        'search audit TSV records how the lookup was resolved'
    );
}

{
    my $audit_file = temp_output_file( suffix => '.tsv.gz', dir => '/tmp' );
    my $convert = build_convert(
        in_file           => 't/csv2bff/in/csv_data.csv',
        mapping_file      => 't/csv2bff/in/csv_mapping.yaml',
        sep               => ',',
        out_file          => temp_output_file(),
        method            => 'csv2bff',
        search_audit_file => $audit_file,
    );

    my $data = $convert->csv2bff;
    ok( ref $data eq 'ARRAY' && @{$data}, 'csv2bff still returns data when gzipped search audit is enabled' );
    ok( -f $audit_file, 'gzipped search audit TSV is written when requested' );

    my @lines = grep { length } split /\n/, gunzip_file_content($audit_file);
    is(
        $lines[0],
        join(
            "\t",
            qw(row original_term_label converted_term_label converted_term_id ontology configured_search_mode text_similarity_method min_text_similarity_score levenshtein_weight match_status match_source lookup_resolution)
        ),
        'gzipped search audit TSV starts with the expected header'
    );
    cmp_ok( scalar @lines, '>', 1, 'gzipped search audit TSV contains at least one mapped row' );
}

done_testing();
