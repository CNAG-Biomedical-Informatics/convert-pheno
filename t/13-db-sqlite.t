#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Exception;
use Test::Warn;
use File::Temp qw(tempdir);
use DBI;

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
    Convert::Pheno::DB::SQLite::build_query( 'ohdsi', 'concept_id', 'full_text_search' ),
    'SELECT * FROM OHDSI_fts WHERE concept_id MATCH ?',
    'build_query creates full-text SQL'
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
        '/tmp/convert-pheno-share/db/ncit.db',
        'get_database_file_path uses default share dir for regular ontologies'
    );
    is(
        Convert::Pheno::DB::SQLite::get_database_file_path( 'ohdsi', '/custom/ohdsi' ),
        '/custom/ohdsi/ohdsi.db',
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
    is_deeply( \@result, [ undef, undef, undef ], 'execute_query_SQLite returns undefs after execute failure' );
} qr/Query execution failed: boom/, 'execute_query_SQLite warns on execute failure';

{
    my $sth = Test::FakeSTH->new(
        rows => [
            [ 'Acute viral pharyngitis', '195662009', 4112343, 'SNOMED' ],
            [ 'Pharyngitis', '123', 321, 'SNOMED' ],
        ],
    );
    my ( $id, $label, $concept_id ) = Convert::Pheno::DB::SQLite::similarity_match(
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
}

{
    my $sth = Test::FakeSTH->new(
        rows => [
            [ 'Acute viral pharyngitis', '195662009', 4112343, 'SNOMED' ],
            [ 'Viral pharyngitis', '999', 222, 'SNOMED' ],
        ],
    );
    my ( $id, $label, $concept_id ) = Convert::Pheno::DB::SQLite::composite_similarity_match(
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
}

{
    no warnings 'redefine';
    local *Convert::Pheno::DB::SQLite::execute_query_SQLite = sub {
        my ($arg) = @_;
        return ( undef, undef, undef ) if $arg->{match_type} eq 'exact_match';
        return ( 'NCIT:C123', 'Fallback term', undef );
    };

    my ( $id, $label, $concept_id ) = Convert::Pheno::DB::SQLite::get_ontology_terms(
        {
            ontology                  => 'ncit',
            sth_column_ref            => { exact_match => 1, full_text_search => 1 },
            query                     => 'fallback',
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

done_testing();
