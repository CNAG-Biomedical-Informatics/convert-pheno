#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Exception;
use Test::Warn;
use File::Spec::Functions qw(catdir catfile);
use File::Temp qw(tempdir);
use DBI;
use Convert::Pheno::Mapping::Shared qw(map_ontology_term);

{
    package Test::FakeSTH;

    sub new {
        my ( $class, %args ) = @_;
        return bless {
            rows          => $args{rows} || [],
            execute_error => $args{execute_error},
            bound         => [],
            finished      => 0,
        }, $class;
    }

    sub bind_param {
        my ( $self, $idx, $value ) = @_;
        $self->{bound}[$idx] = $value;
        return 1;
    }

    sub execute {
        my ($self) = @_;
        die $self->{execute_error} if defined $self->{execute_error};
        return 1;
    }

    sub fetchrow_arrayref {
        my ($self) = @_;
        return shift @{ $self->{rows} };
    }

    sub finish {
        my ($self) = @_;
        $self->{finished} = 1;
        return 1;
    }
}

use Convert::Pheno::DB::SQLite;

is(
    Convert::Pheno::DB::SQLite::build_query( 'ncit', 'label', 'exact_match' ),
    'SELECT * FROM NCIT_table WHERE label = ? COLLATE NOCASE',
    'build_query creates exact-match SQL'
);
is(
    Convert::Pheno::DB::SQLite::build_query( 'ohdsi', 'concept_id', 'exact_match' ),
    'SELECT * FROM OHDSI_table WHERE concept_id = ?',
    'build_query omits COLLATE NOCASE for numeric concept_id exact matches'
);
is(
    Convert::Pheno::DB::SQLite::build_query( 'ncit', 'id', 'exact_match' ),
    'SELECT * FROM NCIT_table WHERE id = ? COLLATE NOCASE',
    'build_query creates an indexed exact identifier lookup'
);
is(
    Convert::Pheno::DB::SQLite::build_query( 'ohdsi', 'concept_id', 'full_text_search' ),
    'SELECT * FROM OHDSI_fts WHERE concept_id MATCH ?',
    'build_query creates full-text SQL'
);
is(
    Convert::Pheno::DB::SQLite::build_query( 'ncit', 'label', 'relaxed_full_text_search' ),
    'SELECT * FROM NCIT_fts WHERE label MATCH ? ORDER BY bm25(NCIT_fts) LIMIT 200',
    'build_query bounds relaxed full-text candidates using BM25'
);
is(
    Convert::Pheno::DB::SQLite::build_strict_fts_query(
        'Stroke/Myocardial (Infarction)'
    ),
    '"Stroke" AND "Myocardial" AND "Infarction"',
    'build_strict_fts_query requires every literal word'
);
is(
    Convert::Pheno::DB::SQLite::build_strict_fts_query(
        'Stroke OR Bleeding'
    ),
    '"Stroke" AND "OR" AND "Bleeding"',
    'build_strict_fts_query quotes FTS operators as source words'
);
is(
    Convert::Pheno::DB::SQLite::build_strict_fts_query('---'),
    undef,
    'build_strict_fts_query rejects input without searchable words'
);
is(
    Convert::Pheno::DB::SQLite::build_relaxed_fts_query('Sudden Infant Deth Syndrome'),
    '("Infant" AND "Deth" AND "Syndrome") OR ("Sudden" AND "Deth" AND "Syndrome") OR ("Sudden" AND "Infant" AND "Syndrome") OR ("Sudden" AND "Infant" AND "Deth")',
    'build_relaxed_fts_query permits one missing token for a multi-token label'
);
is(
    Convert::Pheno::DB::SQLite::build_relaxed_fts_query('Brain Hemorrhage'),
    '("Brain") OR ("Hemorrhage")',
    'build_relaxed_fts_query uses a bounded OR fallback for two-token labels'
);
is(
    Convert::Pheno::DB::SQLite::build_relaxed_fts_query('Syndrome'),
    undef,
    'build_relaxed_fts_query does not broaden a single-token label'
);

is(
    Convert::Pheno::DB::SQLite::prune_problematic_chars( 'OPCS(v4-0.0):Cannulation_of-lymphatic/duct', 'full_text_search' ),
    'Cannulation of lymphatic duct',
    'prune_problematic_chars normalizes punctuation for full text search'
);
is(
    Convert::Pheno::DB::SQLite::prune_problematic_chars( '2 - mild', 'exact_match' ),
    'mild',
    'prune_problematic_chars removes leading numeric prefixes'
);
is(
    Convert::Pheno::DB::SQLite::prune_problematic_chars( '0 (none)', 'exact_match' ),
    'none',
    'prune_problematic_chars normalizes parenthesized numeric prefixes'
);

{
    local $Convert::Pheno::share_dir = '/tmp/convert-pheno-share';
    is(
        Convert::Pheno::DB::SQLite::get_database_file_path( 'ncit', undef ),
        catfile( catdir( '/tmp/convert-pheno-share', 'db' ), 'ncit.db' ),
        'get_database_file_path uses default share dir for regular ontologies'
    );
    is(
        Convert::Pheno::DB::SQLite::get_database_file_path( 'ohdsi', '/custom/ohdsi' ),
        catfile( '/custom/ohdsi', 'ohdsi.db' ),
        'get_database_file_path uses custom ohdsi path when provided'
    );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    mkdir "$tmpdir/db";
    my $dbfile = "$tmpdir/db/test.db";
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '', { RaiseError => 1, AutoCommit => 1 } );
    $dbh->do('CREATE TABLE sample (id INTEGER)');
    $dbh->disconnect;

    local $Convert::Pheno::share_dir = $tmpdir;
    my $ro = Convert::Pheno::DB::SQLite::open_db_SQLite( 'test', undef );
    isa_ok( $ro, 'DBI::db', 'open_db_SQLite returns a DBI handle' );
    ok( Convert::Pheno::DB::SQLite::close_db_SQLite($ro), 'close_db_SQLite disconnects cleanly' );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $dbfile = catfile( $tmpdir, 'ohdsi.db' );
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$dbfile", '', '',
        { RaiseError => 1, AutoCommit => 1 }
    );
    $dbh->do(
        'CREATE TABLE OHDSI_table '
          . '(label TEXT, id TEXT, concept_id INTEGER, vocabulary_id TEXT)'
    );
    $dbh->do(
        'CREATE VIRTUAL TABLE OHDSI_fts '
          . 'USING fts5(label, id, concept_id, vocabulary_id)'
    );
    $dbh->disconnect;

    throws_ok(
        sub { Convert::Pheno::DB::SQLite::open_db_SQLite( 'ohdsi', $tmpdir ) },
        qr/Athena-OHDSI database .* uses the pre-bundle schema/,
        'open_db_SQLite rejects the old four-column OHDSI database'
    );
}

{
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $dbfile = catfile( $tmpdir, 'ohdsi.db' );
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$dbfile", '', '',
        { RaiseError => 1, AutoCommit => 1 }
    );
    $dbh->do(
        'CREATE TABLE OHDSI_table ('
          . 'label TEXT, id TEXT, concept_id INTEGER, vocabulary_id TEXT, '
          . 'domain_id TEXT, concept_class_id TEXT, standard_concept TEXT, '
          . 'valid_start_date TEXT, valid_end_date TEXT, invalid_reason TEXT)'
    );
    $dbh->do(
        'CREATE VIRTUAL TABLE OHDSI_fts '
          . 'USING fts5(label, id, concept_id, vocabulary_id)'
    );
    $dbh->do(
        'CREATE TABLE OHDSI_maps_to ('
          . 'source_concept_id INTEGER, target_concept_id INTEGER, '
          . 'relationship_id TEXT, valid_start_date TEXT, '
          . 'valid_end_date TEXT, invalid_reason TEXT)'
    );
    $dbh->disconnect;

    my $ro = Convert::Pheno::DB::SQLite::open_db_SQLite( 'ohdsi', $tmpdir );
    isa_ok( $ro, 'DBI::db', 'open_db_SQLite accepts the enriched OHDSI schema' );
    ok(
        Convert::Pheno::DB::SQLite::close_db_SQLite($ro),
        'enriched OHDSI test database disconnects cleanly'
    );
}

{
    no warnings 'redefine';

    my $disconnects = 0;
    my $self = bless(
        {
            databases => [ 'first', 'second' ],
            debug     => 0,
        },
        'Convert::Pheno'
    );

    local *Convert::Pheno::DB::SQLite::open_db_SQLite = sub {
        my ($database) = @_;
        die "second database failed\n" if $database eq 'second';
        return {};
    };
    local *Convert::Pheno::DB::SQLite::close_db_SQLite = sub {
        $disconnects++;
        return 1;
    };

    throws_ok(
        sub { Convert::Pheno::DB::SQLite::open_connections_SQLite($self) },
        qr/second database failed/,
        'open_connections_SQLite preserves connection failures'
    );
    is( $disconnects, 1, 'open_connections_SQLite closes handles opened before a failure' );
    ok( !exists $self->{dbh}, 'failed connection setup removes transient database handles' );
    ok( !exists $self->{sth}, 'failed connection setup removes transient statement handles' );
}

{
    no warnings 'redefine';

    my $disconnects = 0;
    my $self = bless(
        {
            databases => [ 'first', 'second' ],
            dbh       => { first => {}, second => {} },
            sth       => { first => {}, second => {} },
            debug     => 0,
        },
        'Convert::Pheno'
    );

    local *Convert::Pheno::DB::SQLite::close_db_SQLite = sub {
        $disconnects++;
        die "first disconnect failed\n" if $disconnects == 1;
        return 1;
    };

    throws_ok(
        sub { Convert::Pheno::DB::SQLite::close_connections_SQLite($self) },
        qr/first disconnect failed/,
        'close_connections_SQLite reports disconnect failures'
    );
    is( $disconnects, 2, 'close_connections_SQLite attempts every disconnect after a failure' );
    ok( !exists $self->{dbh}, 'connection cleanup removes database handles' );
    ok( !exists $self->{sth}, 'connection cleanup removes statement handles' );
}

dies_ok {
    Convert::Pheno::DB::SQLite::open_db_SQLite( 'missing_ontology', '/definitely/missing/path' );
} 'open_db_SQLite dies when the database file is missing';

{
    my $sth = Test::FakeSTH->new(
        rows => [
            [ 'Acute viral pharyngitis', '195662009', 4112343, 'SNOMED' ],
        ],
    );

    my ( $id, $label, $concept_id ) = Convert::Pheno::DB::SQLite::execute_query_SQLite(
        {
            sth                       => $sth,
            query                     => 'Acute viral pharyngitis',
            ontology                  => 'ohdsi',
            databases                 => ['ohdsi'],
            search                    => 'exact',
            match_type                => 'exact_match',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.1,
            levenshtein_weight        => 0.1,
        }
    );

    is( $id, 'SNOMED:195662009', 'execute_query_SQLite returns prefixed ohdsi id for exact match' );
    is( $label, 'Acute viral pharyngitis', 'execute_query_SQLite returns label for exact match' );
    is( $concept_id, 4112343, 'execute_query_SQLite returns concept_id for exact match' );
    is( $sth->{bound}[1], 'Acute viral pharyngitis', 'execute_query_SQLite binds the raw exact query' );
    ok( $sth->{finished}, 'execute_query_SQLite finishes the statement handle' );
}

{
    my $sth = Test::FakeSTH->new( rows => [] );
    my ( $id, $label, $concept_id ) = Convert::Pheno::DB::SQLite::execute_query_SQLite(
        {
            sth                       => $sth,
            query                     => '',
            ontology                  => 'ncit',
            databases                 => [ 'ncit' ],
            search                    => 'exact',
            match_type                => 'exact_match',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.1,
            levenshtein_weight        => 0.1,
        }
    );
    is( $id, undef, 'execute_query_SQLite returns undef id for empty query' );
    is( $label, undef, 'execute_query_SQLite returns undef label for empty query' );
    is( $concept_id, undef, 'execute_query_SQLite returns undef concept_id for empty query' );
}

warning_like {
    my @result = Convert::Pheno::DB::SQLite::execute_query_SQLite(
        {
            sth                       => Test::FakeSTH->new( execute_error => "boom\n" ),
            query                     => 'query',
            ontology                  => 'ncit',
            databases                 => [ 'ncit' ],
            search                    => 'exact',
            match_type                => 'exact_match',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.1,
            levenshtein_weight        => 0.1,
        }
    );
    is_deeply( \@result, [ undef, undef, undef, undef, undef ], 'execute_query_SQLite returns undefs after execute failure' );
} qr/Query execution failed: boom/, 'execute_query_SQLite warns on execute failure';

{
    my $sth = Test::FakeSTH->new(
        rows => [
            [ 'Acute viral pharyngitis', '195662009', 4112343, 'SNOMED' ],
            [ 'Pharyngitis', '123', 321, 'SNOMED' ],
        ],
    );
    my ( $id, $label, $concept_id, $stats ) = Convert::Pheno::DB::SQLite::similarity_match(
        {
            sth                       => $sth,
            query                     => 'Acute viral pharyngitis',
            ontology                  => 'ohdsi',
            id_column                 => 1,
            label_column              => 0,
            min_text_similarity_score => 0.2,
            text_similarity_method    => 'cosine',
            concept_id_column         => 2,
        }
    );
    is( $id, 'SNOMED:195662009', 'similarity_match picks the best candidate' );
    is( $label, 'Acute viral pharyngitis', 'similarity_match returns winning label' );
    is( $concept_id, 4112343, 'similarity_match returns winning concept_id' );
    is( $stats->{best_candidate_id}, 'SNOMED:195662009', 'similarity_match reports its best candidate' );
    cmp_ok( $stats->{best_candidate_score}, '>', $stats->{runner_up_score}, 'similarity_match reports an ordered score margin' );
}

{
    my $sth = Test::FakeSTH->new(
        rows => [
            [ 'Acute viral pharyngitis', '195662009', 4112343, 'SNOMED' ],
            [ 'Viral pharyngitis', '999', 222, 'SNOMED' ],
        ],
    );
    my ( $id, $label, $concept_id, $stats ) = Convert::Pheno::DB::SQLite::composite_similarity_match(
        {
            sth                       => $sth,
            query                     => 'Acute viral pharyngitis',
            ontology                  => 'ohdsi',
            id_column                 => 1,
            label_column              => 0,
            min_text_similarity_score => 0.2,
            text_similarity_method    => 'cosine',
            levenshtein_weight        => 0.2,
            concept_id_column         => 2,
        }
    );
    is( $id, 'SNOMED:195662009', 'composite_similarity_match picks the best candidate' );
    is( $label, 'Acute viral pharyngitis', 'composite_similarity_match returns winning label' );
    is( $concept_id, 4112343, 'composite_similarity_match returns winning concept_id' );
    is( $stats->{best_candidate_id}, 'SNOMED:195662009', 'composite_similarity_match reports its best candidate' );
    ok( defined $stats->{normalized_levenshtein}, 'composite_similarity_match reports the winning Levenshtein component' );
}

{
    my $sth = Test::FakeSTH->new(
        rows => [ [ 'abce', 'C1', undef ] ],
    );
    my ( $id, undef, undef, $stats ) = Convert::Pheno::DB::SQLite::composite_similarity_match(
        {
            sth                       => $sth,
            query                     => 'abcd',
            ontology                  => 'ncit',
            id_column                 => 1,
            label_column              => 0,
            min_text_similarity_score => 0.7,
            text_similarity_method    => 'cosine',
            levenshtein_weight        => 1,
            concept_id_column         => 2,
        }
    );
    is( $id, 'NCIT:C1', 'fuzzy acceptance uses the reported composite score' );
    cmp_ok( $stats->{best_candidate_score}, '>=', 0.7, 'reported fuzzy score satisfies the configured threshold' );
}

{
    no warnings 'redefine';
    my @calls;
    local *Convert::Pheno::DB::SQLite::execute_query_SQLite = sub {
        my ($arg) = @_;
        push @calls, { %{$arg} };
        return ( undef, undef, undef ) if $arg->{match_type} eq 'exact_match';
        return ( 'NCIT:C123', 'Fallback term', undef );
    };

    my ( $id, $label, $concept_id ) = Convert::Pheno::DB::SQLite::get_ontology_terms(
        {
            ontology                  => 'ncit',
            sth_column_ref            => { exact_match => 1, full_text_search => 1 },
            query                     => 'Stroke OR Bleeding',
            column                    => 'label',
            databases                 => [ 'ncit' ],
            search                    => 'mixed',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.1,
            levenshtein_weight        => 0.1,
        }
    );
    is( $id, 'NCIT:C123', 'get_ontology_terms falls back to full text search in mixed mode' );
    is( $label, 'Fallback term', 'get_ontology_terms returns fallback label from mixed mode' );
    is( $concept_id, undef, 'get_ontology_terms leaves concept_id undef for non-ohdsi ontologies' );
    is(
        $calls[1]{query},
        '"Stroke" AND "OR" AND "Bleeding"',
        'mixed search executes a literal all-token FTS expression'
    );
    is(
        $calls[1]{scoring_query},
        'Stroke OR Bleeding',
        'mixed search scores candidates against the original source label'
    );
    ok(
        $calls[1]{query_is_fts_expression},
        'mixed search does not normalize its generated FTS expression again'
    );
}

{
    no warnings 'redefine';
    local *Convert::Pheno::DB::SQLite::execute_query_SQLite = sub { return ( undef, undef, undef ) };

    my ( $id, $label, $concept_id ) = Convert::Pheno::DB::SQLite::get_ontology_terms(
        {
            ontology                  => 'ohdsi',
            sth_column_ref            => { exact_match => 1, full_text_search => 1 },
            query                     => 'missing',
            column                    => 'concept_id',
            databases                 => [ 'ohdsi' ],
            search                    => 'exact',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.1,
            levenshtein_weight        => 0.1,
        }
    );
    is( $id, 'OHDSI:NA0000', 'get_ontology_terms uses default id when no ohdsi match is found' );
    is( $label, 'No matching concept', 'get_ontology_terms uses default ohdsi label when no match is found' );
    is( $concept_id, 0, 'get_ontology_terms uses default ohdsi concept_id when no match is found' );
}

SKIP: {
    skip 'share/db/ncit.db is required for real SQLite search-mode tests', 28
      unless -f 'share/db/ncit.db';

    local $Convert::Pheno::share_dir = 'share';

    my $lookup = sub {
        my (%args) = @_;
        my $self = bless(
            {
                databases                 => ['ncit'],
                search                    => $args{search},
                text_similarity_method    => 'cosine',
                min_text_similarity_score => $args{min_score} // 0.1,
                levenshtein_weight        => 0.1,
            },
            'Convert::Pheno'
        );

        Convert::Pheno::DB::SQLite::open_connections_SQLite($self);
        my @result = Convert::Pheno::DB::SQLite::get_ontology_terms(
            {
                ontology                  => 'ncit',
                sth_column_ref            => $self->{sth}{ncit}{label},
                query                     => $args{query},
                column                    => 'label',
                databases                 => $self->{databases},
                search                    => $self->{search},
                text_similarity_method    => $self->{text_similarity_method},
                min_text_similarity_score => $self->{min_text_similarity_score},
                levenshtein_weight        => $self->{levenshtein_weight},
            }
        );
        Convert::Pheno::DB::SQLite::close_connections_SQLite($self);

        return @result;
    };

    my ( $exact_id, $exact_label, $exact_concept_id ) = $lookup->(
        search => 'exact',
        query  => 'Acute Bacterial Prostatitis',
    );
    is( $exact_id, 'NCIT:C92957', 'exact search returns the expected NCIT id from the real SQLite db' );
    is( $exact_label, 'Acute Bacterial Prostatitis', 'exact search returns the expected label from the real SQLite db' );
    is( $exact_concept_id, undef, 'exact search leaves concept_id undef for ncit in the real SQLite db' );

    my ( $mixed_id, $mixed_label, $mixed_concept_id ) = $lookup->(
        search => 'mixed',
        query  => 'Acute_Bacterial-Prostatitis',
    );
    is( $mixed_id, 'NCIT:C92957', 'mixed search falls back through the real SQLite path and returns the expected NCIT id' );
    is( $mixed_label, 'Acute Bacterial Prostatitis', 'mixed search normalizes punctuation and returns the expected label' );
    is( $mixed_concept_id, undef, 'mixed search leaves concept_id undef for ncit in the real SQLite db' );

    my ( $fuzzy_id, $fuzzy_label, $fuzzy_concept_id ) = $lookup->(
        search => 'fuzzy',
        query  => 'Acute_Bacterial-Prostatitis',
    );
    is( $fuzzy_id, 'NCIT:C92957', 'fuzzy search returns the expected NCIT id from the real SQLite db' );
    is( $fuzzy_label, 'Acute Bacterial Prostatitis', 'fuzzy search returns the expected label from the real SQLite db' );
    is( $fuzzy_concept_id, undef, 'fuzzy search leaves concept_id undef for ncit in the real SQLite db' );

    my ( $rejected_id, undef, undef, $rejected_resolution, $rejected_evidence ) = $lookup->(
        search    => 'fuzzy',
        query     => 'Sudden Adult Death Syndrome',
        min_score => 0.8,
    );
    is( $rejected_id, 'NCIT:NA0000', 'fuzzy search rejects a semantic token substitution' );
    is( $rejected_resolution, 'fallback_na', 'rejected semantic substitution retains the fallback resolution' );
    is( $rejected_evidence->{candidate_strategy}, 'relaxed_fts', 'semantic substitution reports relaxed candidate retrieval' );
    is( $rejected_evidence->{best_candidate_id}, 'NCIT:C85173', 'rejected semantic substitution still reports its best candidate' );
    cmp_ok( $rejected_evidence->{best_candidate_score}, '<', 0.8, 'semantic substitution remains below the configured threshold' );

    my ( $spelling_id, $spelling_label, undef, $spelling_resolution, $spelling_evidence ) = $lookup->(
        search    => 'fuzzy',
        query     => 'Sudden Infant Deth Syndrome',
        min_score => 0.8,
    );
    is( $spelling_id, 'NCIT:C85173', 'fuzzy search accepts a single near-spelling token at the default threshold' );
    is( $spelling_label, 'Sudden Infant Death Syndrome', 'spelling-aware fuzzy search returns the canonical label' );
    is( $spelling_resolution, 'similarity', 'spelling-aware fuzzy search reports similarity resolution' );
    is( $spelling_evidence->{candidate_strategy}, 'relaxed_fts', 'spelling-aware fuzzy search reports relaxed candidate retrieval' );
    ok( $spelling_evidence->{spelling_variant}, 'spelling-aware fuzzy search records spelling evidence' );
    cmp_ok( $spelling_evidence->{best_candidate_score}, '>=', 0.8, 'spelling-aware fuzzy score satisfies the unchanged threshold' );

    my $id_self = bless(
        {
            databases                 => ['ncit'],
            search                    => 'fuzzy',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.1,
            levenshtein_weight        => 0.1,
        },
        'Convert::Pheno'
    );
    Convert::Pheno::DB::SQLite::open_connections_SQLite($id_self);
    my $id_term = map_ontology_term(
        {
            ontology        => 'ncit',
            query           => 'C70666',
            column          => 'id',
            self            => $id_self,
            return_metadata => 1,
        }
    );
    Convert::Pheno::DB::SQLite::close_connections_SQLite($id_self);
    is( $id_term->{id}, 'NCIT:C70666', 'identifier lookup returns the expected NCIT id' );
    is( $id_term->{label}, 'Mild', 'identifier lookup obtains the canonical label from SQLite' );
    is( $id_term->{search_resolution}, 'exact', 'identifier lookup remains exact under global fuzzy search' );

    my $profile_self = bless(
        {
            databases                 => ['ncit'],
            debug                     => 2,
            search                    => 'exact',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.1,
            levenshtein_weight        => 0.1,
        },
        'Convert::Pheno'
    );

    Convert::Pheno::DB::SQLite::open_connections_SQLite($profile_self);
    map_ontology_term(
        {
            ontology => 'ncit',
            query    => 'Acute Bacterial Prostatitis',
            column   => 'label',
            self     => $profile_self,
        }
    );
    map_ontology_term(
        {
            ontology => 'ncit',
            query    => 'Acute Bacterial Prostatitis',
            column   => 'label',
            self     => $profile_self,
        }
    );

    my $stderr = q{};
    {
        local *STDERR;
        open STDERR, '>', \$stderr or die "Could not capture STDERR: $!";
        Convert::Pheno::DB::SQLite::close_connections_SQLite($profile_self);
    }

    like( $stderr, qr/DB lookup profile:/, 'debug level 2 prints a DB lookup profile summary' );
    like( $stderr, qr/mapping requests=2 cache_hits=1 db_lookups=1/, 'DB lookup profile reports cache-hit vs DB-hit counts' );
    like( $stderr, qr/final resolution exact=2 similarity=0 fallback_na=0/, 'DB lookup profile reports final lookup resolution counts' );
    like( $stderr, qr/sql exact_match=1 full_text_search=0/, 'DB lookup profile reports SQL execution counts by match type' );
    like( $stderr, qr/ontology\[ncit\] requests=2 cache_hits=1 db_lookups=1 exact=2 similarity=0 fallback_na=0/, 'DB lookup profile reports per-ontology lookup counts' );
}

done_testing();
