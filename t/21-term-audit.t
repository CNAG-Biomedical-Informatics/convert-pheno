#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use File::Spec;
use Test::Exception;
use Test::More;
use Convert::Pheno::Audit::Terminology;
use Convert::Pheno::CLI::Args qw(build_cli_request);
use Convert::Pheno::Mapping::Shared qw(finalize_term_audit record_term_audit);
use Test::ConvertPheno qw(build_convert temp_output_file slurp_file gunzip_file_content slurp_zip_member test_tmpdir);

my $tmpdir = test_tmpdir();

{
    my $request = build_cli_request(
        argv => [
            '-icsv', 't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '-obff', 'individuals.json',
            '--term-audit', 'term-audit.tsv',
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
        'CLI parser resolves --term-audit relative to --out-dir'
    );
}

{
    my $request = build_cli_request(
        argv => [
            '-icsv', 't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '-obff', 'individuals.json',
            '--term-audit', 'term-audit.tsv.gz',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );

    is(
        $request->{data}{term_audit_file},
        File::Spec->catfile( $tmpdir, 'term-audit.tsv.gz' ),
        'CLI parser resolves compressed --term-audit relative to --out-dir'
    );
}

{
    my $request = build_cli_request(
        argv => [
            '-icsv', 't/csv2bff/in/csv_data.csv',
            '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
            '-obff', 'individuals.json',
            '--term-audit', 'term-audit.xlsx',
        ],
        usage_error => sub { die @_ },
        schema_file => 'share/schema/mapping-v2.json',
        out_dir     => $tmpdir,
        color       => 1,
    );

    is(
        $request->{data}{term_audit_file},
        File::Spec->catfile( $tmpdir, 'term-audit.xlsx' ),
        'CLI parser resolves XLSX --term-audit relative to --out-dir'
    );
}

throws_ok(
    sub {
        local *STDERR;
        open STDERR, '>', \my $stderr
          or die "Could not capture STDERR: $!";
        build_cli_request(
            argv => [
                '-icsv', 't/csv2bff/in/csv_data.csv',
                '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
                '-obff', 'individuals.json',
                '--term-audit', 'term-audit.csv',
            ],
            usage_error => sub { die @_ },
            schema_file => 'share/schema/mapping-v2.json',
            out_dir     => $tmpdir,
            color       => 1,
        );
    },
    qr/\.tsv, \.tsv\.gz, or \.xlsx/,
    'CLI parser rejects unsupported terminology audit formats'
);

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
            qw(row source_record source_field source_value source_label lookup_query lookup_column converted_term_label converted_term_id ontology configured_search_mode effective_search_mode text_similarity_method min_text_similarity_score levenshtein_weight match_status decision_reason review_action match_source lookup_resolution fallback_action retrieval_path best_candidate_label best_candidate_id best_candidate_score score_margin)
        ),
        'terminology audit TSV starts with the expected header'
    );
    cmp_ok( scalar @lines, '>', 1, 'terminology audit TSV contains at least one mapped row' );

    my @cols = split /\t/, $lines[1], -1;
    is( scalar @cols, 26, 'terminology audit TSV rows contain the expected number of columns' );
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
        qr/^(?:direct_mapping|exact_match|similarity_accepted|spelling_variant_accepted|score_below_threshold|no_candidate|not_searched|source_fallback|resolved)$/,
        'terminology audit TSV records the decision reason'
    );
    like(
        $cols[17],
        qr/^(?:keep|review_similarity|resolve_or_accept_fallback|review_source_fallback)$/,
        'terminology audit TSV recommends a review action'
    );
    like(
        $cols[18],
        qr/^(?:db|cache|mapping|fallback_na)$/,
        'terminology audit TSV records the resolution source'
    );
    like(
        $cols[19],
        qr/^(?:exact|similarity|direct_term|fallback_na)$/,
        'terminology audit TSV records how the term was resolved'
    );
    like( $cols[20], qr/^(?:none|na)$/, 'terminology audit TSV records the fallback action' );
    like(
        $cols[21],
        qr/^(?:exact_lookup|all_tokens|one_token_relaxed|not_used)?$/,
        'terminology audit TSV records the candidate retrieval path used'
    );
    like( $cols[24], qr/^(?:\d\.\d{4})?$/, 'terminology audit TSV records a formatted best-candidate score when applicable' );
    like( $cols[25], qr/^(?:\d\.\d{4})?$/, 'terminology audit TSV records a formatted score margin when applicable' );
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
            qw(row source_record source_field source_value source_label lookup_query lookup_column converted_term_label converted_term_id ontology configured_search_mode effective_search_mode text_similarity_method min_text_similarity_score levenshtein_weight match_status decision_reason review_action match_source lookup_resolution fallback_action retrieval_path best_candidate_label best_candidate_id best_candidate_score score_margin)
        ),
        'gzipped terminology audit TSV starts with the expected header'
    );
    cmp_ok( scalar @lines, '>', 1, 'gzipped terminology audit TSV contains at least one mapped row' );
}

{
    my $audit_file = temp_output_file( suffix => '.xlsx', dir => $tmpdir );
    my $convert = build_convert(
        in_file         => 't/csv2bff/in/csv_data.csv',
        mapping_file    => 't/csv2bff/in/csv_mapping.yaml',
        sep             => ',',
        out_file        => temp_output_file(),
        method          => 'csv2bff',
        term_audit_file => $audit_file,
    );

    my $data = $convert->csv2bff;
    ok( ref $data eq 'ARRAY' && @{$data}, 'csv2bff still returns data when XLSX terminology audit is enabled' );
    ok( -f $audit_file, 'XLSX terminology audit is written when requested' );

    my $workbook_xml = slurp_zip_member( $audit_file, 'xl/workbook.xml' );
    like( $workbook_xml, qr/name="Summary"/, 'XLSX audit contains a Summary sheet' );
    like( $workbook_xml, qr/name="Terminology Audit"/, 'XLSX audit contains a Terminology Audit sheet' );

    my $shared_strings = slurp_zip_member( $audit_file, 'xl/sharedStrings.xml' );
    like( $shared_strings, qr/decision_reason/, 'XLSX audit contains decision provenance columns' );
    like( $shared_strings, qr/review_action/, 'XLSX audit contains an explicit review recommendation' );
    like( $shared_strings, qr/Colors prioritize review/, 'XLSX summary explains how to interpret colors' );
    like( $shared_strings, qr/Technical audit columns are present but hidden/, 'XLSX summary explains its focused default view' );

    my $audit_sheet = slurp_zip_member( $audit_file, 'xl/worksheets/sheet2.xml' );
    like( $audit_sheet, qr/<pane\b/, 'XLSX audit freezes its header and source columns' );
    like( $audit_sheet, qr/<autoFilter\b/, 'XLSX audit enables filtering' );
    like( $audit_sheet, qr/<conditionalFormatting\b/, 'XLSX audit color-codes rows by review category' );
    like( $audit_sheet, qr/hidden="1"/, 'XLSX audit hides technical columns by default' );
}

{
    my $audit_file = temp_output_file( suffix => '.xlsx', dir => $tmpdir );
    my $writer = Convert::Pheno::Audit::Terminology->new(
        path   => $audit_file,
        config => {
            search                    => 'exact',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.8,
            levenshtein_weight        => 0.1,
        },
    );
    $writer->write_row(
        {
            row                    => 1,
            source_value           => '=1+1',
            match_status           => 'matched',
            decision_reason        => 'exact_match',
            lookup_resolution      => 'exact',
            retrieval_path         => 'exact_lookup',
            best_candidate_score   => 1,
        }
    );
    $writer->close;

    my $shared_strings = slurp_zip_member( $audit_file, 'xl/sharedStrings.xml' );
    like( $shared_strings, qr/=1\+1/, 'XLSX audit preserves formula-like source text as a string' );
    my $audit_sheet = slurp_zip_member( $audit_file, 'xl/worksheets/sheet2.xml' );
    unlike( $audit_sheet, qr/<f>/, 'XLSX audit does not create formulas from source values' );
}

throws_ok(
    sub {
        local *STDERR;
        open STDERR, '>', \my $stderr
          or die "Could not capture STDERR: $!";
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

throws_ok(
    sub {
        local *STDERR;
        open STDERR, '>', \my $stderr
          or die "Could not capture STDERR: $!";
        build_cli_request(
            argv => [
                '-icsv', 't/csv2bff/in/csv_data.csv',
                '--mapping-file', 't/csv2bff/in/csv_mapping.yaml',
                '-obff', 'individuals.json',
                '--term-audit-tsv', 'legacy.tsv',
            ],
            usage_error => sub { die @_ },
            schema_file => 'share/schema/mapping-v2.json',
            out_dir     => $tmpdir,
            color       => 1,
        );
    },
    qr/Invalid command-line arguments/,
    'the superseded --term-audit-tsv option is rejected'
);

{
    my $audit_file = temp_output_file( suffix => '.tsv', dir => $tmpdir );
    my $self = bless(
        {
            current_row               => 4,
            term_audit_file           => $audit_file,
            search                    => 'fuzzy',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.8,
            levenshtein_weight        => 0.1,
        },
        'Convert::Pheno'
    );
    record_term_audit(
        {
            self          => $self,
            source_field  => 'diagnosis',
            source_value  => 'Sudden Adult Death Syndrome',
            source_label  => 'Sudden Adult Death Syndrome',
            lookup_query  => 'Sudden Adult Death Syndrome',
            lookup_column => 'label',
            ontology      => 'ncit',
            term          => {
                id                => 'NCIT:NA0000',
                label             => 'NA',
                search_resolution => 'fallback_na',
                search_evidence   => {
                    candidate_strategy  => 'relaxed_fts',
                    candidates_evaluated => 2,
                    eligible_candidates => 0,
                    best_candidate_label => 'Sudden Infant Death Syndrome',
                    best_candidate_id    => 'NCIT:C85173',
                    best_candidate_score => 0.757143,
                    token_similarity     => 0.75,
                    normalized_levenshtein => 0.821429,
                    runner_up_label => 'Family History of Sudden Infant Death Syndrome',
                    runner_up_id    => 'NCIT:C168209',
                    runner_up_score => 0.560252,
                    score_margin    => 0.196891,
                },
            },
            match_source => 'fallback_na',
        }
    );

    $self->{current_row} = 5;
    record_term_audit(
        {
            self          => $self,
            source_field  => 'diagnosis',
            source_value  => 'Sudden Infant Deth Syndrome',
            source_label  => 'Sudden Infant Deth Syndrome',
            lookup_query  => 'Sudden Infant Deth Syndrome',
            lookup_column => 'label',
            ontology      => 'ncit',
            term          => {
                id                => 'NCIT:C85173',
                label             => 'Sudden Infant Death Syndrome',
                search_resolution => 'similarity',
                search_evidence   => {
                    candidate_strategy    => 'relaxed_fts',
                    candidates_evaluated  => 2,
                    eligible_candidates   => 1,
                    best_candidate_label  => 'Sudden Infant Death Syndrome',
                    best_candidate_id     => 'NCIT:C85173',
                    best_candidate_score  => 0.951429,
                    token_similarity      => 0.95,
                    normalized_levenshtein => 0.964286,
                    spelling_variant      => 1,
                    spelling_query_token  => 'deth',
                    spelling_candidate_token => 'death',
                    spelling_token_similarity => 0.8,
                    runner_up_label => 'Family History of Sudden Infant Death Syndrome',
                    runner_up_id    => 'NCIT:C168209',
                    runner_up_score => 0.568948,
                    score_margin    => 0.382481,
                },
            },
            match_source => 'db',
        }
    );
    finalize_term_audit($self);

    my @lines = grep { length } split /\n/, slurp_file($audit_file);
    my @cols = split /\t/, $lines[1], -1;
    is( $cols[16], 'score_below_threshold', 'audit explains why the candidate was rejected' );
    is( $cols[17], 'resolve_or_accept_fallback', 'audit recommends resolving or accepting a rejected fallback' );
    is( $cols[21], 'one_token_relaxed', 'audit identifies one-token-relaxed candidate retrieval for a rejected match' );
    is( $cols[22], 'Sudden Infant Death Syndrome', 'audit preserves the rejected best-candidate label' );
    is( $cols[24], '0.7571', 'audit formats the rejected best-candidate score' );
    is( $cols[25], '0.1969', 'audit formats the best-to-runner-up score margin' );

    my @accepted_cols = split /\t/, $lines[2], -1;
    is( $accepted_cols[16], 'spelling_variant_accepted', 'audit explains an accepted spelling correction' );
    is( $accepted_cols[17], 'review_similarity', 'audit recommends review for an accepted spelling correction' );
    is( $accepted_cols[21], 'one_token_relaxed', 'accepted spelling correction retains its retrieval path' );
    is( $accepted_cols[24], '0.9514', 'audit records the spelling-aware fuzzy score' );
}

done_testing();
