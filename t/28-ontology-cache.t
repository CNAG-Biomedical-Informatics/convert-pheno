use strict;
use warnings;

use Test::More;

use Convert::Pheno::Mapping::Shared qw(map_ontology_term);

sub cache_self {
    my ($source) = @_;
    return bless(
        {
            source                    => $source,
            debug                     => 0,
            search                    => 'exact',
            text_similarity_method    => 'cosine',
            min_text_similarity_score => 0.8,
            levenshtein_weight        => 0.1,
            databases                 => ['ncit'],
            sth                       => {
                ncit => {
                    label      => {},
                    concept_id => {},
                },
            },
        },
        'OntologyCacheProbe'
    );
}

{
    no warnings 'redefine';

    my $calls = 0;
    local *Convert::Pheno::Mapping::Shared::get_ontology_terms = sub {
        my ($arg) = @_;
        $calls++;
        return (
            'NCIT:' . $arg->{self}{source},
            $arg->{self}{source},
            100 + $calls,
            'exact',
        );
    };

    my $first  = cache_self('first');
    my $second = cache_self('second');

    my $first_result = map_ontology_term(
        {
            self     => $first,
            ontology => 'ncit',
            column   => 'label',
            query    => 'shared query',
        }
    );
    my $first_cached = map_ontology_term(
        {
            self     => $first,
            ontology => 'ncit',
            column   => 'label',
            query    => 'shared query',
        }
    );
    my $second_result = map_ontology_term(
        {
            self     => $second,
            ontology => 'ncit',
            column   => 'label',
            query    => 'shared query',
        }
    );

    is( $first_result->{label}, 'first', 'first converter receives its lookup result' );
    is_deeply( $first_cached, $first_result, 'identical lookup reuses the object-local cache' );
    is( $second_result->{label}, 'second', 'second converter does not reuse another converter cache' );
    is( $calls, 2, 'only identical lookups on the same converter are cached' );
}

{
    no warnings 'redefine';

    my $calls = 0;
    local *Convert::Pheno::Mapping::Shared::get_ontology_terms = sub {
        my ($arg) = @_;
        $calls++;
        return (
            'NCIT:' . $arg->{column},
            $arg->{column},
            4000 + $calls,
            'exact',
        );
    };

    my $self = cache_self('semantic');
    my $label_result = map_ontology_term(
        {
            self     => $self,
            ontology => 'ncit',
            column   => 'label',
            query    => 'same value',
        }
    );
    my $concept_result = map_ontology_term(
        {
            self               => $self,
            ontology           => 'ncit',
            column             => 'concept_id',
            query              => 'same value',
            require_concept_id => 1,
        }
    );

    is( $label_result->{label}, 'label', 'label lookup keeps its result' );
    is( $concept_result->{label}, 'concept_id', 'concept-id lookup has a separate cache key' );
    ok( exists $concept_result->{concept_id}, 'concept-id requirement is preserved in the cache key' );
    is( $calls, 2, 'different lookup semantics perform separate database queries' );
}

done_testing;
