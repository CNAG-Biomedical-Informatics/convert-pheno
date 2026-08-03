#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Convert::Pheno::DB::Similarity qw(
  combine_similarity_scores
  composite_similarity
  compute_normalized_levenshtein
  compute_single_token_spelling_similarity
  compute_token_similarity
);

is(
    combine_similarity_scores( 0.75, 0.95, 0.9, 0.1 ),
    0.77,
    'combine_similarity_scores applies the configured weights to existing scores'
);

my $cosine = compute_token_similarity( 'acute viral pharyngitis', 'acute viral pharyngitis', 'cosine' );
my $dice   = compute_token_similarity( 'acute viral pharyngitis', 'acute viral pharyngitis', 'dice' );

cmp_ok( $cosine, '>=', 0.99, 'cosine similarity is high for identical strings' );
cmp_ok( $dice,   '>=', 0.99, 'dice similarity is high for identical strings' );
cmp_ok( compute_token_similarity( 'alpha', 'beta', 'cosine' ), '<', $cosine, 'cosine similarity drops for different strings' );

is( compute_normalized_levenshtein( 'abc', 'abc' ), 1, 'normalized levenshtein is 1 for identical strings' );
is( compute_normalized_levenshtein( '', '' ), 1, 'normalized levenshtein is 1 for two empty strings' );
cmp_ok( compute_normalized_levenshtein( 'abc', 'xyz' ), '<', 0.5, 'normalized levenshtein is low for different strings' );

my $spelling_variant = compute_single_token_spelling_similarity(
    'Sudden Infant Deth Syndrome',
    'Sudden Infant Death Syndrome',
    'cosine'
);
ok( $spelling_variant, 'one near-spelling token pair is detected' );
is( $spelling_variant->{query_token}, 'deth', 'spelling evidence records the source token' );
is( $spelling_variant->{candidate_token}, 'death', 'spelling evidence records the candidate token' );
cmp_ok( $spelling_variant->{spelling_token_similarity}, '>=', 0.8, 'near-spelling tokens satisfy the conservative token threshold' );
cmp_ok( $spelling_variant->{adjusted_similarity}, '>=', 0.95, 'soft token overlap restores similarity for a single spelling variant' );
ok(
    !compute_single_token_spelling_similarity(
        'Sudden Adult Death Syndrome',
        'Sudden Infant Death Syndrome',
        'cosine'
    ),
    'a semantic token substitution is not classified as a spelling variant'
);
ok(
    !compute_single_token_spelling_similarity(
        'Sudden Adult Deth Syndrome',
        'Sudden Infant Death Syndrome',
        'cosine'
    ),
    'more than one differing token is not classified as a spelling variant'
);

my $token_only = composite_similarity( 'acute viral pharyngitis', 'acute viral pharyngitis', 1, 0, 'cosine' );
my $mixed      = composite_similarity( 'acute viral pharyngitis', 'acute viral pharyngitis', 0.5, 0.5, 'cosine' );
cmp_ok( $token_only, '>=', 0.99, 'composite similarity can be token-only' );
cmp_ok( $mixed, '>=', 0.99, 'composite similarity stays high for identical strings' );
cmp_ok(
    composite_similarity( 'alpha', 'beta', 0.5, 0.5, 'cosine' ),
    '<',
    $mixed,
    'composite similarity drops for different strings'
);

done_testing();
