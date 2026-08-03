package Convert::Pheno::DB::Similarity;
use strict;
use warnings;
use Text::Similarity::Overlaps;
use Text::Levenshtein::XS qw(distance);
use Exporter 'import';
our @EXPORT_OK =
  qw(combine_similarity_scores composite_similarity compute_token_similarity compute_normalized_levenshtein compute_single_token_spelling_similarity);

use constant MIN_SPELLING_TOKEN_SIMILARITY => 0.8;

sub compute_token_similarity {
    my ( $query, $candidate, $method, $ts ) = @_;
    $ts ||= Text::Similarity::Overlaps->new();
    my ( $score, %scores ) = $ts->getSimilarityStrings( $query, $candidate );
    return $scores{$method} // 0;
}

sub compute_normalized_levenshtein {
    my ( $query, $candidate ) = @_;
    my $d = distance( $query, $candidate );
    my $max_len =
      length($query) > length($candidate) ? length($query) : length($candidate);
    return $max_len ? 1 - ( $d / $max_len ) : 1;
}

sub compute_single_token_spelling_similarity {
    my ( $query, $candidate, $method ) = @_;
    return unless defined $query && defined $candidate;
    return unless $method eq 'cosine' || $method eq 'dice';

    my @query_tokens = grep { length }
      split /[^\p{L}\p{N}]+/u, lc $query;
    my @candidate_tokens = grep { length }
      split /[^\p{L}\p{N}]+/u, lc $candidate;
    return unless @query_tokens && @query_tokens == @candidate_tokens;

    my @remaining_candidates = @candidate_tokens;
    my @unmatched_query;
  QUERY_TOKEN:
    for my $query_token (@query_tokens) {
        for my $index ( 0 .. $#remaining_candidates ) {
            next unless $query_token eq $remaining_candidates[$index];
            splice @remaining_candidates, $index, 1;
            next QUERY_TOKEN;
        }
        push @unmatched_query, $query_token;
    }

    return unless @unmatched_query == 1 && @remaining_candidates == 1;
    my $spelling_similarity = compute_normalized_levenshtein(
        $unmatched_query[0], $remaining_candidates[0]
    );
    return if $spelling_similarity < MIN_SPELLING_TOKEN_SIMILARITY;

    my $query_count     = scalar @query_tokens;
    my $candidate_count = scalar @candidate_tokens;
    my $soft_overlap    = $query_count - 1 + $spelling_similarity;
    my $adjusted_similarity = $method eq 'cosine'
      ? $soft_overlap / sqrt( $query_count * $candidate_count )
      : ( 2 * $soft_overlap ) / ( $query_count + $candidate_count );

    return {
        adjusted_similarity          => $adjusted_similarity,
        query_token                  => $unmatched_query[0],
        candidate_token              => $remaining_candidates[0],
        spelling_token_similarity    => $spelling_similarity,
    };
}

sub combine_similarity_scores {
    my ( $token_sim, $lev_sim, $token_weight, $lev_weight ) = @_;
    return ( $token_weight * $token_sim ) + ( $lev_weight * $lev_sim );
}

sub composite_similarity {
    my ( $query, $candidate, $token_weight, $lev_weight, $method ) = @_;
    my $token_sim = compute_token_similarity( $query, $candidate, $method );
    my $lev_sim   = compute_normalized_levenshtein( $query, $candidate );
    return combine_similarity_scores( $token_sim, $lev_sim, $token_weight, $lev_weight );
}

1;
