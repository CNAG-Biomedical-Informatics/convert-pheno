#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Convert::Pheno::DB::Similarity qw(
  composite_similarity
  compute_normalized_levenshtein
  compute_token_similarity
);

my $cosine = compute_token_similarity( 'acute viral pharyngitis', 'acute viral pharyngitis', 'cosine' );
my $dice   = compute_token_similarity( 'acute viral pharyngitis', 'acute viral pharyngitis', 'dice' );

cmp_ok( $cosine, '>=', 0.99, 'cosine similarity is high for identical strings' );
cmp_ok( $dice,   '>=', 0.99, 'dice similarity is high for identical strings' );
cmp_ok( compute_token_similarity( 'alpha', 'beta', 'cosine' ), '<', $cosine, 'cosine similarity drops for different strings' );

is( compute_normalized_levenshtein( 'abc', 'abc' ), 1, 'normalized levenshtein is 1 for identical strings' );
is( compute_normalized_levenshtein( '', '' ), 1, 'normalized levenshtein is 1 for two empty strings' );
cmp_ok( compute_normalized_levenshtein( 'abc', 'xyz' ), '<', 0.5, 'normalized levenshtein is low for different strings' );

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
