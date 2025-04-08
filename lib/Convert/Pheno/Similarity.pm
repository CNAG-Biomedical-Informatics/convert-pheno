package Convert::Pheno::Similarity;
use strict;
use warnings;
use Text::Similarity::Overlaps;
use Text::Levenshtein::XS qw(distance);
use Exporter 'import';
our @EXPORT_OK =
  qw(composite_similarity compute_token_similarity compute_normalized_levenshtein);

sub compute_token_similarity {
    my ( $query, $candidate, $method ) = @_;
    my $ts = Text::Similarity::Overlaps->new();
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

sub composite_similarity {
    my ( $query, $candidate, $token_weight, $lev_weight, $method ) = @_;
    $token_weight //= 0.9;
    $lev_weight   //= 0.1;
    my $token_sim = compute_token_similarity( $query, $candidate, $method );
    my $lev_sim   = compute_normalized_levenshtein( $query, $candidate );
    return ( $token_weight * $token_sim ) + ( $lev_weight * $lev_sim );
}

1;
