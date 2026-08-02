package Convert::Pheno::CDISC::SDTM::Terminology;

use strict;
use warnings;

use Exporter 'import';
use File::ShareDir::ProjectDistDir qw(dist_dir);
use File::Spec::Functions qw(catfile);
use Storable qw(dclone);

use Convert::Pheno::CDISC::SDTM::Normalizer qw(
  collect_sdtm_source_terms
  sdtm_source_fields
);
use Convert::Pheno::IO::CSVHandler qw(read_mapping_file);
use Convert::Pheno::Mapping::Compiler qw(compile_mapping);
use Convert::Pheno::Mapping::Shared qw(
  map_ontology_term
  record_term_audit
);

our @EXPORT_OK = qw(
  prepare_sdtm_terminology
  resolve_sdtm_term
);

my %SUPPORTED_FIELD = map { $_ => 1 } qw(
  DM.ETHNIC
  DM.COUNTRY
  MH.MHDECOD
  MH.MHTERM
  AE.AEDECOD
  AE.AETERM
  AE.AESEV
  LB.LBTESTCD
  LB.LBTEST
  LB.LBSTRESC
  LB.LBSTRESU
  VS.VSTESTCD
  VS.VSTEST
  VS.VSSTRESC
  VS.VSSTRESU
  CM.CMDECOD
  CM.CMTRT
  CM.CMROUTE
  EX.EXTRT
  EX.EXROUTE
  PR.PRDECOD
  PR.PRTRT
  PR.PRLOC
);

sub prepare_sdtm_terminology {
    my ( $converter, $metadata ) = @_;
    my $source_terms = collect_sdtm_source_terms($metadata);
    my $mapping;

    if ( defined $converter->{mapping_file} && length $converter->{mapping_file} ) {
        my $schema_file = $converter->{schema_file}
          // catfile( dist_dir('Convert-Pheno'), 'schema', 'mapping-v2.json' );
        my $loaded = read_mapping_file(
            {
                mapping_file         => $converter->{mapping_file},
                self_validate_schema => $converter->{self_validate_schema},
                schema_file          => $schema_file,
            }
        );
        $mapping = compile_mapping(
            $loaded,
            source_profile => 'sdtm',
            headers        => sdtm_source_fields($metadata),
        );

        my @unsupported = sort grep { !$SUPPORTED_FIELD{$_} }
          keys %{ $mapping->{terminology} || {} };
        die "SDTM terminology mapping references fields that do not produce BFF ontology terms: <"
          . join( '>, <', @unsupported ) . ">.\n"
          if @unsupported;
    }

    my $requires_sqlite = scalar grep {
        my $term = $_;
        ref($term) eq 'HASH' && defined $term->{id} && length $term->{id}
    } map { values %{$_} } values %{$source_terms};
    if ($mapping) {
        $requires_sqlite ||= scalar grep {
            exists $mapping->{terminology}{$_}{query}
        } keys %{ $mapping->{terminology} || {} };
    }

    return {
        mapping         => $mapping,
        source_terms    => $source_terms,
        requires_sqlite => $requires_sqlite ? 1 : 0,
    };
}

sub resolve_sdtm_term {
    my ($arg) = @_;
    my $self = $arg->{self};
    my $domain = uc( $arg->{domain} // q{} );
    my $field  = uc( $arg->{field}  // q{} );
    my $source_field = "$domain.$field";
    my $source_value = $arg->{value};
    my $fallback = dclone( $arg->{fallback} );
    my $source_metadata = $self->{sdtm_source_terms}{$source_field}{$source_value};
    my $source_label = ref($source_metadata) eq 'HASH'
      ? ( $source_metadata->{label} // $arg->{label} // $source_value )
      : ( $arg->{label} // $source_value );
    $fallback->{label} = $source_label
      if ref($fallback) eq 'HASH'
      && defined $source_label
      && length $source_label;
    my $rule = $self->{sdtm_terminology_mapping}{terminology}{$source_field};

    if ( ref($rule) eq 'HASH' && exists $rule->{term} ) {
        return _configured_term(
            $self,
            $rule->{term},
            $source_field,
            $source_value,
            $source_label,
            $arg->{source_record},
            $rule->{ontology} // $self->{sdtm_terminology_mapping}{defaults}{ontology},
        );
    }

    if ( ref($rule) eq 'HASH' && ref( $rule->{terms} ) eq 'HASH' ) {
        my $term_key = exists $rule->{terms}{$source_label}
          ? $source_label
          : $source_value;
        if ( exists $rule->{terms}{$term_key} ) {
            return _configured_term(
                $self,
                $rule->{terms}{$term_key},
                $source_field,
                $source_value,
                $source_label,
                $arg->{source_record},
                $rule->{ontology} // $self->{sdtm_terminology_mapping}{defaults}{ontology},
            );
        }
    }

    if ( ref($source_metadata) eq 'HASH' && defined $source_metadata->{id} ) {
        my $id = $source_metadata->{id};
        $id =~ s/^NCIT://i;
        return _lookup_or_fallback(
            self          => $self,
            ontology      => 'ncit',
            query         => $id,
            column        => 'id',
            source_field  => $source_field,
            source_value  => $source_value,
            source_label  => $source_label,
            source_record => $arg->{source_record},
            match_source  => 'define_xml',
            fallback      => $fallback,
        );
    }

    if ( ref($rule) eq 'HASH' && ref( $rule->{query} ) eq 'HASH' ) {
        my $query_rule = $rule->{query};
        my $query;
        if ( exists $query_rule->{literal} ) {
            $query = $query_rule->{literal};
        }
        elsif ( ( $query_rule->{from} // q{} ) eq 'field' ) {
            $query = $field;
        }
        elsif ( ( $query_rule->{from} // q{} ) eq 'fieldNote' ) {
            $query = $arg->{field_label} // $field;
        }
        else {
            $query = $source_label;
        }

        if ( ref( $query_rule->{aliases} ) eq 'HASH' ) {
            my $alias_key = exists $query_rule->{aliases}{$source_label}
              ? $source_label
              : $source_value;
            $query = $query_rule->{aliases}{$alias_key}
              if exists $query_rule->{aliases}{$alias_key};
        }

        return _lookup_or_fallback(
            self          => $self,
            ontology      => $rule->{ontology}
              // $self->{sdtm_terminology_mapping}{defaults}{ontology},
            query         => $query,
            column        => 'label',
            source_field  => $source_field,
            source_value  => $source_value,
            source_label  => $source_label,
            source_record => $arg->{source_record},
            match_source  => 'db',
            fallback      => $fallback,
        );
    }

    record_term_audit(
        {
            self              => $self,
            source_record     => $arg->{source_record},
            source_field      => $source_field,
            source_value      => $source_value,
            source_label      => $source_label,
            ontology          => 'cdisc',
            term              => $fallback,
            match_status      => 'not_searched',
            match_source      => 'source_fallback',
            lookup_resolution => 'fallback_source',
            fallback_action   => 'source_term',
        }
    );
    return $fallback;
}

sub _configured_term {
    my ( $self, $term, $source_field, $source_value, $source_label, $source_record, $ontology ) = @_;
    my $resolved = dclone($term);
    record_term_audit(
        {
            self              => $self,
            source_record     => $source_record,
            source_field      => $source_field,
            source_value      => $source_value,
            source_label      => $source_label,
            ontology          => $ontology,
            term              => $resolved,
            match_status      => 'configured',
            match_source      => 'mapping',
            lookup_resolution => 'direct_term',
            fallback_action   => 'none',
        }
    );
    return $resolved;
}

sub _lookup_or_fallback {
    my (%arg) = @_;
    my $result = map_ontology_term(
        {
            self            => $arg{self},
            ontology        => $arg{ontology},
            query           => $arg{query},
            column          => $arg{column},
            audit           => 0,
            return_metadata => 1,
        }
    );

    my $match_source = $arg{match_source};
    if ( !_not_found($result) && $arg{ontology} eq 'cdisc' ) {
        my $nci_id = $result->{id};
        $nci_id =~ s/^NCIT://;
        $result = map_ontology_term(
            {
                self            => $arg{self},
                ontology        => 'ncit',
                query           => $nci_id,
                column          => 'id',
                audit           => 0,
                return_metadata => 1,
            }
        );
        $match_source = 'cdisc_to_ncit';
    }

    my $matched = !_not_found($result);
    my $term = $matched
      ? { id => $result->{id}, label => $result->{label} }
      : dclone( $arg{fallback} );
    my $reported_match_source = $match_source;
    if ( $matched
        && $match_source ne 'define_xml'
        && $match_source ne 'cdisc_to_ncit' )
    {
        $reported_match_source = $result->{match_source} // $match_source;
    }
    record_term_audit(
        {
            self                  => $arg{self},
            source_record         => $arg{source_record},
            source_field          => $arg{source_field},
            source_value          => $arg{source_value},
            source_label          => $arg{source_label},
            lookup_query          => $arg{query},
            lookup_column         => $arg{column},
            ontology              => $matched && $arg{ontology} eq 'cdisc'
              ? 'ncit'
              : $arg{ontology},
            term                  => $term,
            effective_search_mode => $arg{column} eq 'id'
              ? 'exact'
              : $arg{self}{search},
            match_status      => $matched ? 'matched' : 'not_found',
            match_source      => $reported_match_source,
            lookup_resolution => $matched
              ? ( $result->{search_resolution} // 'exact' )
              : 'fallback_source',
            fallback_action => $matched ? 'none' : 'source_term',
        }
    );
    return $term;
}

sub _not_found {
    my ($term) = @_;
    return 1 unless ref($term) eq 'HASH' && defined $term->{id};
    return $term->{id} =~ /:NA0000\z/ ? 1 : 0;
}

1;
