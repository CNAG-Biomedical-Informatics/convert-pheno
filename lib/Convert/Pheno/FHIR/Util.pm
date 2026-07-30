package Convert::Pheno::FHIR::Util;

use strict;
use warnings;

use Exporter 'import';

our @EXPORT_OK = qw(
  canonical_reference
  codeable_concept_to_term
  coding_to_term
  quantity_unit_to_term
  reference_aliases
  resolve_reference
  source_term
);

my %SYSTEM_PREFIX = (
    'http://human-phenotype-ontology.org'              => 'HP',
    'http://loinc.org'                                 => 'LOINC',
    'http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl' => 'NCIT',
    'http://purl.bioontology.org/ontology/ICD10'       => 'ICD10',
    'http://purl.bioontology.org/ontology/NCIT'        => 'NCIT',
    'http://purl.obolibrary.org/obo/hp.owl'            => 'HP',
    'http://snomed.info/sct'                           => 'SNOMEDCT',
    'http://unitsofmeasure.org'                        => 'UCUM',
    'http://www.nlm.nih.gov/research/umls/rxnorm'      => 'RxNorm',
    'http://hl7.org/fhir/sid/icd-10'                   => 'ICD10',
    'http://hl7.org/fhir/sid/icd-10-cm'                => 'ICD10CM',
    'http://hl7.org/fhir/sid/icd-10-pcs'               => 'ICD10PCS',
    'urn:oid:2.16.840.1.113883.6.238'                  => 'CDCREC',
);

sub canonical_reference {
    my ($reference) = @_;
    return unless defined $reference && !ref($reference);

    $reference =~ s/^\s+|\s+$//g;
    return unless length $reference;
    return $reference if $reference =~ /^#/;

    $reference =~ s{/+_history/[^/?#]+\z}{};
    if ( $reference =~ m{(?:\A|/)([A-Z][A-Za-z0-9]+)/([^/?#]+)\z} ) {
        return "$1/$2";
    }

    return $reference;
}

sub reference_aliases {
    my ( $resource, $full_url ) = @_;
    return [] unless ref($resource) eq 'HASH';

    my @aliases;
    push @aliases, $full_url
      if defined $full_url && !ref($full_url) && length $full_url;

    if ( defined $resource->{resourceType}
        && !ref( $resource->{resourceType} )
        && defined $resource->{id}
        && !ref( $resource->{id} )
        && length $resource->{id} )
    {
        push @aliases, "$resource->{resourceType}/$resource->{id}";
    }

    my %seen;
    my @normalized;
    for my $alias (@aliases) {
        for my $candidate ( $alias, canonical_reference($alias) ) {
            next unless defined $candidate && length $candidate;
            push @normalized, $candidate unless $seen{$candidate}++;
        }
    }

    return \@normalized;
}

sub resolve_reference {
    my ( $index, $reference ) = @_;
    return unless ref($index) eq 'HASH';
    return unless defined $reference && !ref($reference);

    return $index->{$reference} if exists $index->{$reference};
    my $canonical = canonical_reference($reference);
    return unless defined $canonical;
    return $index->{$canonical};
}

sub codeable_concept_to_term {
    my ( $concept, $fallback_namespace ) = @_;
    return unless ref($concept) eq 'HASH';

    for my $coding ( @{ $concept->{coding} || [] } ) {
        next unless ref($coding) eq 'HASH'
          && defined $coding->{code}
          && !ref( $coding->{code} )
          && length $coding->{code};
        my $term = coding_to_term( $coding, $concept->{text} );
        return $term if defined $term;
    }

    my $text = _trim( $concept->{text} );
    return unless defined $text && length $text;
    return source_term( $fallback_namespace || 'CodeableConcept', $text, $text );
}

sub coding_to_term {
    my ( $coding, $fallback_label ) = @_;
    return unless ref($coding) eq 'HASH';

    my $code = _trim( $coding->{code} );
    my $label = _trim( $coding->{display} );
    $label = _trim($fallback_label) unless defined $label && length $label;

    return source_term( 'Coding', $label, $label )
      unless defined $code && length $code;

    $code =~ s/^HP_([0-9]+)\z/HP:$1/;
    my $id;
    if ( $code =~ /^\w[^:]+:.+\z/ ) {
        $id = $code;
    }
    else {
        my $prefix = _prefix_for_system( $coding->{system} );
        $id = "$prefix:$code";
    }

    $id =~ s/\s+/_/g;
    my $term = { id => $id };
    $term->{label} = $label
      if defined $label && length $label;
    return $term;
}

sub quantity_unit_to_term {
    my ($quantity) = @_;
    return unless ref($quantity) eq 'HASH';

    my $code = _trim( $quantity->{code} );
    my $unit = _trim( $quantity->{unit} );
    my $system = _trim( $quantity->{system} );

    if ( defined $code && length $code ) {
        return coding_to_term(
            {
                code    => $code,
                display => $unit,
                system  => $system,
            },
            $unit,
        );
    }

    return unless defined $unit && length $unit;
    return source_term( 'Unit', $unit, $unit );
}

sub source_term {
    my ( $namespace, $value, $label ) = @_;
    $namespace = _trim($namespace) // 'Value';
    $value     = _trim($value);
    return unless defined $value && length $value;

    $namespace =~ s/[^A-Za-z0-9_.-]+/_/g;
    $namespace = 'Value' unless length $namespace;

    my $local = $value;
    $local =~ s/\s+/_/g;
    $local =~ s/[^A-Za-z0-9_.:\/\[\]{}+%=-]+/_/g;
    $local =~ s/^_+|_+$//g;
    $local = 'unknown' unless length $local;

    my $term = { id => "FHIR:$namespace.$local" };
    $term->{label} = $label
      if defined $label && !ref($label) && length $label;
    return $term;
}

sub _prefix_for_system {
    my ($system) = @_;
    $system = _trim($system);
    return 'FHIR' unless defined $system && length $system;

    $system =~ s{/+\z}{};
    return $SYSTEM_PREFIX{$system} if exists $SYSTEM_PREFIX{$system};

    my ($tail) = $system =~ m{([^/:#]+)\z};
    $tail //= 'Coding';
    $tail =~ s/[^A-Za-z0-9_.-]+/_/g;
    $tail = 'Coding' unless length $tail;
    return "FHIR-$tail";
}

sub _trim {
    my ($value) = @_;
    return unless defined $value;
    return $value if ref($value);
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

1;
