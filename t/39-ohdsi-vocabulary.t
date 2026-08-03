#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno qw(build_convert test_ohdsi_db_dir);
use Convert::Pheno::DB::SQLite qw(
  open_connections_SQLite close_connections_SQLite
);
use Convert::Pheno::OMOP::Vocabulary qw(resolve_standard_concept);

my $convert = build_convert(
    method           => 'bff2omop',
    ohdsi_db         => 1,
    path_to_ohdsi_db => test_ohdsi_db_dir(),
);
open_connections_SQLite($convert);

sub resolve {
    my (%arg) = @_;
    return resolve_standard_concept(
        {
            self         => $convert,
            mapping_type => $arg{mapping_type} // 'test',
            term         => $arg{term},
            domain       => $arg{domain},
            defined $arg{relationships}
            ? ( relationships => $arg{relationships} )
            : (),
        }
    );
}

subtest 'standard source identifier is retained directly' => sub {
    my $result = resolve(
        term   => { id => 'SNOMED:195662009', label => 'Acute viral pharyngitis' },
        domain => 'Condition',
    );
    is( $result->{concept_id}, 4112343, 'uses the standard Condition concept' );
    is( $result->{source_concept_id}, 4112343, 'retains the source concept identifier' );
    is( $result->{resolution}, 'identifier_standard', 'reports direct identifier resolution' );
};

subtest 'non-standard identifier follows Maps to' => sub {
    my $result = resolve(
        term   => { id => 'ICD10CM:E11', label => 'Type 2 diabetes mellitus' },
        domain => 'Condition',
    );
    is( $result->{concept_id}, 201826, 'uses the mapped standard SNOMED concept' );
    is( $result->{source_concept_id}, 1567956, 'retains the ICD10CM source concept' );
    is( $result->{resolution}, 'maps_to_standard', 'reports relationship resolution' );
};

subtest 'obsolete NDC source maps to a standard RxNorm Drug' => sub {
    my $result = resolve(
        term => {
            id    => 'NDC:00088500010',
            label => 'Fexofenadine hydrochloride 30 MG Oral Tablet',
        },
        domain => 'Drug',
    );
    is( $result->{concept_id}, 40223821, 'uses the RxNorm target concept' );
    is( $result->{source_concept_id}, 44957998, 'retains the obsolete NDC source concept' );
    is( $result->{target_id}, 'RxNorm:997488', 'returns the target vocabulary identifier' );
};

subtest 'domain-constrained label fallback avoids a wrong-domain identifier' => sub {
    my $result = resolve(
        term   => { id => 'LOINC:LP33332-5', label => 'metFORMIN' },
        domain => 'Drug',
    );
    is( $result->{concept_id}, 1503297, 'selects standard RxNorm metformin' );
    is( $result->{source_concept_id}, 44787139, 'retains the supplied LOINC source concept' );
    is( $result->{resolution}, 'domain_label_exact', 'reports domain label fallback' );
};

subtest 'label fallback can resolve a source term into another OMOP domain' => sub {
    my $result = resolve(
        term   => { id => 'LOINC:LA4457-3', label => 'White' },
        domain => 'Race',
    );
    is( $result->{concept_id}, 8527, 'selects the standard Race concept' );
    is( $result->{source_concept_id}, 45877987, 'retains the LOINC answer source concept' );
};

subtest 'wrong-domain match fails conservatively' => sub {
    my $result = resolve(
        term   => { id => 'LOINC:LA9367-9', label => 'Oral' },
        domain => 'Route',
    );
    is( $result->{concept_id}, 0, 'does not use the LOINC Meas Value as a Route' );
    is( $result->{source_concept_id}, 45878097, 'still records the supplied source concept' );
    is( $result->{decision_reason}, 'no_standard_concept', 'reports that no standard Route was found' );
};

subtest 'identifier prefix aliases are supported' => sub {
    my $result = resolve(
        term   => { id => 'SNOMEDCT:195662009', label => 'Acute viral pharyngitis' },
        domain => 'Condition',
    );
    is( $result->{concept_id}, 4112343, 'normalizes SNOMEDCT to the OHDSI SNOMED vocabulary' );
};

subtest 'ambiguous exact labels are not selected by row order' => sub {
    my $result = resolve(
        term   => { label => 'Oral' },
        domain => 'Observation',
    );
    is( $result->{concept_id}, 0, 'returns concept 0 for multiple standard Observation matches' );
    is( $result->{decision_reason}, 'label_ambiguous', 'reports exact-label ambiguity' );
};

close_connections_SQLite($convert);

my $fuzzy_convert = build_convert(
    method           => 'bff2omop',
    ohdsi_db         => 1,
    path_to_ohdsi_db => test_ohdsi_db_dir(),
    search           => 'fuzzy',
);
open_connections_SQLite($fuzzy_convert);

subtest 'fuzzy fallback remains constrained to the target domain' => sub {
    my $result = resolve_standard_concept(
        {
            self         => $fuzzy_convert,
            mapping_type => 'disease',
            term         => { label => 'Streptococal sore throat' },
            domain       => 'Condition',
        }
    );
    is( $result->{concept_id}, 28060, 'accepts a one-token spelling variant' );
    is( $result->{target_domain}, 'Condition', 'returns only a Condition candidate' );
    is( $result->{resolution}, 'domain_label_similarity', 'reports similarity resolution' );
};

close_connections_SQLite($fuzzy_convert);
done_testing;
