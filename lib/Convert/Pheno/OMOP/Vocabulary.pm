package Convert::Pheno::OMOP::Vocabulary;

use strict;
use warnings;

use Exporter 'import';
use Convert::Pheno::DB::SQLite ();
use Convert::Pheno::Mapping::Shared qw(record_term_audit);

our @EXPORT_OK = qw(resolve_standard_concept);

my %VOCABULARY_ALIAS = (
    SNOMEDCT       => 'SNOMED',
    RXNORM         => 'RxNorm',
    RXNORMEXTENSION => 'RxNorm Extension',
    ICD10CM        => 'ICD10CM',
    ICD9CM         => 'ICD9CM',
    OMOPEXTENSION  => 'OMOP Extension',
);

sub resolve_standard_concept {
    my ($arg) = @_;
    my $self = $arg->{self}
      or die "OHDSI concept resolution requires a converter instance\n";
    my $term = ref( $arg->{term} ) eq 'HASH'
      ? $arg->{term}
      : { label => $arg->{term} };
    my @domains = ref( $arg->{domains} ) eq 'ARRAY'
      ? @{ $arg->{domains} }
      : ( $arg->{domain} );
    @domains = grep { defined && length } @domains;
    die "OHDSI concept resolution requires an expected OMOP domain\n"
      unless @domains;

    my @relationships = ref( $arg->{relationships} ) eq 'ARRAY'
      ? @{ $arg->{relationships} }
      : ( $arg->{relationship} // 'Maps to' );
    my $source_id    = _trim( $term->{id} );
    my $source_label = _trim( $term->{label} );
    my $source_value = length($source_label) ? $source_label : $source_id;

    return _empty_result($source_value)
      unless length($source_id) || length($source_label);

    my $search = _setting( $self, 'search', 'exact' );
    my $cache_key = join "\x1e",
      $arg->{mapping_type} // q{}, join( q{|}, @domains ),
      join( q{|}, @relationships ), $source_id, $source_label, $search;
    my $cache = $self->{_ohdsi_standard_concept_cache} ||= {};
    if ( exists $cache->{$cache_key} ) {
        my $cached = { %{ $cache->{$cache_key} }, match_source => 'cache' };
        _record_audit( $self, $arg, $cached );
        return _public_result($cached);
    }

    my $result;
    my $source_concept;
    if ( length $source_id ) {
        my $source_candidates = _lookup_identifier( $self, $source_id );
        if ( @{$source_candidates} > 1 ) {
            $result = _failure_result(
                source_value    => $source_value,
                source_id       => $source_id,
                source_label    => $source_label,
                decision_reason => 'identifier_ambiguous',
                lookup_query    => $source_id,
                lookup_column   => 'id',
            );
        }
        elsif ( @{$source_candidates} == 1 ) {
            $source_concept = $source_candidates->[0];
            if ( _is_eligible_standard( $source_concept, \@domains ) ) {
                $result = _success_result(
                    target            => $source_concept,
                    source_concept_id => $source_concept->{concept_id},
                    source_value      => $source_value,
                    source_id         => $source_id,
                    source_label      => $source_label,
                    resolution        => 'identifier_standard',
                    decision_reason   => 'identifier_standard',
                    lookup_query      => $source_id,
                    lookup_column     => 'id',
                );
            }
            else {
                my $targets = _lookup_mapped_targets(
                    $self, $source_concept->{concept_id},
                    \@relationships, \@domains
                );
                if ( @{$targets} == 1 ) {
                    $result = _success_result(
                        target            => $targets->[0],
                        source_concept_id => $source_concept->{concept_id},
                        source_value      => $source_value,
                        source_id         => $source_id,
                        source_label      => $source_label,
                        resolution        => 'maps_to_standard',
                        decision_reason   => 'identifier_maps_to_standard',
                        lookup_query      => $source_id,
                        lookup_column     => 'id',
                    );
                }
                elsif ( @{$targets} > 1 ) {
                    $result = _failure_result(
                        source_value      => $source_value,
                        source_id         => $source_id,
                        source_label      => $source_label,
                        source_concept_id => $source_concept->{concept_id},
                        decision_reason   => 'mapping_ambiguous',
                        lookup_query      => $source_id,
                        lookup_column     => 'id',
                    );
                }
            }
        }
    }

    unless ($result) {
        my $source_concept_id = $source_concept
          ? $source_concept->{concept_id}
          : 0;
        if ( length $source_label ) {
            my $label_candidates =
              _lookup_standard_label( $self, $source_label, \@domains );
            if ( @{$label_candidates} == 1 ) {
                $result = _success_result(
                    target            => $label_candidates->[0],
                    source_concept_id => $source_concept_id,
                    source_value      => $source_value,
                    source_id         => $source_id,
                    source_label      => $source_label,
                    resolution        => 'domain_label_exact',
                    decision_reason   => 'domain_label_exact',
                    lookup_query      => $source_label,
                    lookup_column     => 'label',
                );
            }
            elsif ( @{$label_candidates} > 1 ) {
                $result = _failure_result(
                    source_value      => $source_value,
                    source_id         => $source_id,
                    source_label      => $source_label,
                    source_concept_id => $source_concept_id,
                    decision_reason   => 'label_ambiguous',
                    lookup_query      => $source_label,
                    lookup_column     => 'label',
                );
            }
            elsif ( $search eq 'mixed' || $search eq 'fuzzy' ) {
                my $similar = _lookup_similar_standard_label(
                    $self, $source_label, \@domains, $search
                );
                if ( $similar->{target} ) {
                    $result = _success_result(
                        target            => $similar->{target},
                        source_concept_id => $source_concept_id,
                        source_value      => $source_value,
                        source_id         => $source_id,
                        source_label      => $source_label,
                        resolution        => 'domain_label_similarity',
                        decision_reason   => 'domain_label_similarity',
                        lookup_query      => $source_label,
                        lookup_column     => 'label',
                        search_evidence   => $similar->{search_evidence},
                    );
                }
                elsif ( $similar->{ambiguous} ) {
                    $result = _failure_result(
                        source_value      => $source_value,
                        source_id         => $source_id,
                        source_label      => $source_label,
                        source_concept_id => $source_concept_id,
                        decision_reason   => 'similarity_ambiguous',
                        lookup_query      => $source_label,
                        lookup_column     => 'label',
                        search_evidence   => $similar->{search_evidence},
                    );
                }
            }
        }
    }

    $result ||= _failure_result(
        source_value      => $source_value,
        source_id         => $source_id,
        source_label      => $source_label,
        source_concept_id => $source_concept ? $source_concept->{concept_id} : 0,
        decision_reason   => 'no_standard_concept',
        lookup_query      => length($source_label) ? $source_label : $source_id,
        lookup_column     => length($source_label) ? 'label' : 'id',
    );

    $result->{match_source} = $result->{matched} ? 'db' : 'fallback_na';
    $cache->{$cache_key} = { %{$result} };
    _record_audit( $self, $arg, $result );
    return _public_result($result);
}

sub _lookup_identifier {
    my ( $self, $curie ) = @_;
    return [] if $curie =~ /:NA0000\z/i;

    my ( $prefix, $code ) = split /:/, $curie, 2;
    return [] unless defined $code && length $prefix && length $code;

    if ( uc($prefix) eq 'OHDSI' && $code =~ /\A\d+\z/ ) {
        my $rows = _select_rows(
            _statement(
                $self,
                concept_id => 'SELECT * FROM OHDSI_table WHERE concept_id = ?'
            ),
            0 + $code
        );
        return _deduplicate_concepts($rows);
    }

    my @vocabularies = _vocabulary_candidates($prefix);
    my @rows;
    my $sth = _statement(
        $self,
        vocabulary_code =>
          'SELECT * FROM OHDSI_table '
          . 'WHERE vocabulary_id = ? COLLATE NOCASE AND id = ? COLLATE NOCASE'
    );
    for my $vocabulary (@vocabularies) {
        push @rows, @{ _select_rows( $sth, $vocabulary, $code ) };
    }
    return _deduplicate_concepts(\@rows);
}

sub _lookup_mapped_targets {
    my ( $self, $source_concept_id, $relationships, $domains ) = @_;
    my $sth = _statement(
        $self,
        maps_to =>
          'SELECT t.* FROM OHDSI_maps_to AS m '
          . 'JOIN OHDSI_table AS t ON t.concept_id = m.target_concept_id '
          . 'WHERE m.source_concept_id = ? AND m.relationship_id = ? '
          . q{AND m.invalid_reason = '' AND t.standard_concept = 'S' }
          . q{AND t.invalid_reason = ''}
    );

    my @rows;
    for my $relationship ( @{$relationships} ) {
        push @rows,
          grep { _domain_matches( $_->{domain_id}, $domains ) }
          @{ _select_rows( $sth, $source_concept_id, $relationship ) };
    }
    return _deduplicate_concepts(\@rows);
}

sub _lookup_standard_label {
    my ( $self, $label, $domains ) = @_;
    my $sth = _statement(
        $self,
        standard_label =>
          'SELECT * FROM OHDSI_table '
          . q{WHERE domain_id = ? COLLATE NOCASE AND standard_concept = 'S' }
          . q{AND label = ? COLLATE NOCASE AND invalid_reason = ''}
    );

    my @rows;
    for my $domain ( @{$domains} ) {
        push @rows, @{ _select_rows( $sth, $domain, $label ) };
    }
    return _deduplicate_concepts(\@rows);
}

sub _lookup_similar_standard_label {
    my ( $self, $label, $domains, $search ) = @_;
    my $domain_placeholders = join q{,}, ('?') x @{$domains};
    my $base_sql =
        'SELECT t.label, t.id, t.concept_id, t.vocabulary_id '
      . 'FROM OHDSI_fts JOIN OHDSI_table AS t '
      . 'ON t.concept_id = CAST(OHDSI_fts.concept_id AS INTEGER) '
      . 'WHERE OHDSI_fts.label MATCH ? '
      . q{AND t.standard_concept = 'S' AND t.invalid_reason = '' }
      . "AND t.domain_id COLLATE NOCASE IN ($domain_placeholders)";
    my $normalized = Convert::Pheno::DB::SQLite::prune_problematic_chars(
        $label, 'full_text_search'
    );
    my $strict_query =
      Convert::Pheno::DB::SQLite::build_strict_fts_query($label);
    return { search_evidence => _search_evidence( undef, 'strict_fts' ) }
      unless defined $strict_query;

    my $strict = _score_similarity_candidates(
        $self,
        statement_name => 'standard_fts_' . @{$domains},
        sql            => $base_sql,
        query          => $strict_query,
        scoring_query  => $normalized,
        domains        => $domains,
        search         => $search,
        strategy       => 'strict_fts',
    );
    return $strict if $strict->{target} || $strict->{ambiguous};
    return $strict unless $search eq 'fuzzy';
    return $strict if ( $strict->{search_evidence}{candidates_evaluated} // 0 ) > 0;

    my $relaxed_query =
      Convert::Pheno::DB::SQLite::build_relaxed_fts_query($label);
    return $strict unless defined $relaxed_query;

    return _score_similarity_candidates(
        $self,
        statement_name => 'standard_relaxed_fts_' . @{$domains},
        sql            => $base_sql . ' ORDER BY bm25(OHDSI_fts) LIMIT 200',
        query          => $relaxed_query,
        scoring_query  => $normalized,
        domains        => $domains,
        search         => $search,
        strategy       => 'relaxed_fts',
        allow_spelling_variant => 1,
    );
}

sub _score_similarity_candidates {
    my ( $self, %arg ) = @_;
    my $sth = _statement( $self, $arg{statement_name}, $arg{sql} );
    $sth->execute( $arg{query}, @{ $arg{domains} } );

    my %score_arg = (
        sth                       => $sth,
        query                     => $arg{scoring_query},
        ontology                  => 'ohdsi',
        id_column                 => 1,
        label_column              => 0,
        concept_id_column         => 2,
        text_similarity_method    => _setting( $self, 'text_similarity_method', 'cosine' ),
        min_text_similarity_score => _setting( $self, 'min_text_similarity_score', 0.8 ),
        levenshtein_weight        => _setting( $self, 'levenshtein_weight', 0.1 ),
        self                      => $self,
    );
    my ( $id, undef, $concept_id, $stats ) =
      $arg{search} eq 'mixed'
      ? Convert::Pheno::DB::SQLite::similarity_match(\%score_arg)
      : Convert::Pheno::DB::SQLite::composite_similarity_match(
        { %score_arg, allow_spelling_variant => $arg{allow_spelling_variant} }
      );
    $sth->finish;

    my $evidence = _search_evidence( $stats, $arg{strategy} );
    my $min_score = $score_arg{min_text_similarity_score};
    my $ambiguous = defined $id
      && defined $stats->{runner_up_score}
      && $stats->{runner_up_score} >= $min_score
      && ( $stats->{score_margin} // 0 ) <= 0;
    return { ambiguous => 1, search_evidence => $evidence } if $ambiguous;
    return { search_evidence => $evidence } unless defined $concept_id;

    my $target = _lookup_concept_id( $self, $concept_id );
    return {
        target          => $target,
        search_evidence => $evidence,
    };
}

sub _lookup_concept_id {
    my ( $self, $concept_id ) = @_;
    my $rows = _select_rows(
        _statement(
            $self,
            concept_id => 'SELECT * FROM OHDSI_table WHERE concept_id = ?'
        ),
        $concept_id
    );
    return $rows->[0];
}

sub _statement {
    my ( $self, $name, $sql ) = @_;
    my $dbh = $self->{dbh}{ohdsi}
      or die "Athena-OHDSI lookup requires an open ohdsi.db connection\n";
    return $self->{sth}{ohdsi}{standard_concept}{$name} ||=
      $dbh->prepare($sql);
}

sub _select_rows {
    my ( $sth, @bind ) = @_;
    $sth->execute(@bind);
    my $rows = $sth->fetchall_arrayref( {} );
    $sth->finish;
    return $rows;
}

sub _vocabulary_candidates {
    my ($prefix) = @_;
    my $normalized = uc($prefix);
    $normalized =~ s/[^A-Z0-9]+//g;

    my @candidates;
    push @candidates, $VOCABULARY_ALIAS{$normalized}
      if exists $VOCABULARY_ALIAS{$normalized};
    push @candidates, $prefix;
    if ( $prefix =~ /_/ ) {
        ( my $with_spaces = $prefix ) =~ tr/_/ /;
        push @candidates, $with_spaces;
    }

    my %seen;
    return grep { defined && length && !$seen{lc $_}++ } @candidates;
}

sub _is_eligible_standard {
    my ( $concept, $domains ) = @_;
    return 0 unless ( $concept->{standard_concept} // q{} ) eq 'S';
    return 0 if length( $concept->{invalid_reason} // q{} );
    return _domain_matches( $concept->{domain_id}, $domains );
}

sub _domain_matches {
    my ( $domain, $domains ) = @_;
    return 0 unless defined $domain;
    return scalar grep { lc($domain) eq lc($_) } @{$domains};
}

sub _deduplicate_concepts {
    my ($rows) = @_;
    my %seen;
    return [ grep { !$seen{ $_->{concept_id} }++ } @{$rows} ];
}

sub _success_result {
    my (%arg) = @_;
    return {
        matched           => 1,
        concept_id        => 0 + $arg{target}{concept_id},
        source_concept_id => 0 + ( $arg{source_concept_id} // 0 ),
        source_value      => $arg{source_value},
        source_id         => $arg{source_id},
        source_label      => $arg{source_label},
        target_id         => _concept_curie( $arg{target} ),
        target_label      => $arg{target}{label},
        target_domain     => $arg{target}{domain_id},
        resolution        => $arg{resolution},
        decision_reason   => $arg{decision_reason},
        lookup_query      => $arg{lookup_query},
        lookup_column     => $arg{lookup_column},
        search_evidence   => $arg{search_evidence},
    };
}

sub _failure_result {
    my (%arg) = @_;
    return {
        matched           => 0,
        concept_id        => 0,
        source_concept_id => 0 + ( $arg{source_concept_id} // 0 ),
        source_value      => $arg{source_value},
        source_id         => $arg{source_id},
        source_label      => $arg{source_label},
        target_id         => 'OHDSI:NA0000',
        target_label      => 'No matching standard concept',
        resolution        => 'fallback_concept_0',
        decision_reason   => $arg{decision_reason},
        lookup_query      => $arg{lookup_query},
        lookup_column     => $arg{lookup_column},
        search_evidence   => $arg{search_evidence},
    };
}

sub _empty_result {
    my ($source_value) = @_;
    return {
        concept_id        => 0,
        source_concept_id => 0,
        source_value      => $source_value,
        matched           => 0,
        resolution        => 'not_searched',
    };
}

sub _public_result {
    my ($result) = @_;
    my %public = %{$result};
    delete @public{qw(lookup_query lookup_column search_evidence match_source)};
    return \%public;
}

sub _record_audit {
    my ( $self, $arg, $result ) = @_;
    record_term_audit(
        {
            self                  => $self,
            source_field          => $arg->{mapping_type},
            source_value          => $result->{source_id} || $result->{source_value},
            source_label          => $result->{source_label},
            lookup_query          => $result->{lookup_query},
            lookup_column         => $result->{lookup_column},
            ontology              => 'ohdsi',
            term                  => {
                id                => $result->{target_id},
                label             => $result->{target_label},
                search_resolution => $result->{resolution},
                search_evidence   => $result->{search_evidence},
            },
            effective_search_mode => $result->{lookup_column} eq 'label'
            ? _setting( $self, 'search', 'exact' )
            : 'exact',
            match_status      => $result->{matched} ? 'matched' : 'not_found',
            decision_reason   => $result->{decision_reason},
            match_source      => $result->{match_source},
            lookup_resolution => $result->{resolution},
            fallback_action   => $result->{matched} ? 'none' : 'concept_0',
        }
    );
}

sub _search_evidence {
    my ( $stats, $strategy ) = @_;
    $stats ||= {};
    return {
        candidate_strategy  => $strategy,
        candidates_evaluated => $stats->{candidate_rows} // 0,
        eligible_candidates  => $stats->{shortlisted_candidates} // 0,
        map { $_ => $stats->{$_} }
          grep { exists $stats->{$_} }
          qw(best_candidate_label best_candidate_id best_candidate_score token_similarity base_token_similarity normalized_levenshtein spelling_variant spelling_query_token spelling_candidate_token spelling_token_similarity runner_up_label runner_up_id runner_up_score score_margin),
    };
}

sub _concept_curie {
    my ($concept) = @_;
    my $prefix = $concept->{vocabulary_id};
    $prefix =~ s/\s+/_/g;
    return $prefix . ':' . $concept->{id};
}

sub _setting {
    my ( $self, $name, $default ) = @_;
    my $value = $self->can($name) ? $self->$name : $self->{$name};
    return defined $value ? $value : $default;
}

sub _trim {
    my ($value) = @_;
    return q{} unless defined $value && !ref $value;
    $value =~ s/\A\s+//;
    $value =~ s/\s+\z//;
    return $value;
}

1;
