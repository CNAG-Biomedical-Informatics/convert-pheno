package Convert::Pheno::CDISC::SDTM::Normalizer;

use strict;
use warnings;

use Exporter 'import';
use Scalar::Util qw(blessed looks_like_number);
use Storable qw(dclone);

our @EXPORT_OK = qw(
  collect_sdtm_source_terms
  derive_sdtm_entity_overrides
  normalize_sdtm_datasets
  sdtm_source_fields
);

sub normalize_sdtm_datasets {
    my ( $datasets, $labels, %option ) = @_;
    my $format_name   = $option{format_name}   || 'Dataset-JSON';
    my $version_key   = $option{version_key}   || 'datasetJSONVersion';
    my $source_format = $option{source_format} || 'dataset-json';
    my $validate      = $option{validate};
    my $subject_metadata_fields = $option{subject_metadata_fields} || [];

    die "$format_name input does not contain any datasets\n"
      unless @{$datasets};

    my %documents;
    my @domain_order;
    my $study_oid;

    for my $index ( 0 .. $#{$datasets} ) {
        my $dataset = $datasets->[$index];
        my $label   = $labels->[$index];

        die "$format_name input <$label> must contain an object\n"
          unless ref($dataset) eq 'HASH';
        $validate->( $dataset, $label ) if $validate;

        my $domain = uc( _trim( $dataset->{name} ) // q{} );
        die "$format_name input <$label> has an invalid SDTM domain name <$domain>\n"
          unless $domain =~ /\A[A-Z][A-Z0-9]{0,7}\z/;
        die "$format_name domain <$domain> was supplied more than once\n"
          if exists $documents{$domain};

        my $current_study = _trim( $dataset->{studyOID} );
        if ( defined $current_study && length $current_study ) {
            $study_oid //= $current_study;
            die "$format_name files contain inconsistent studyOID values <$study_oid> and <$current_study>\n"
              if $current_study ne $study_oid;
        }

        my $decoded = _decode_dataset(
            $dataset,
            $domain,
            $label,
            $format_name,
        );
        $documents{$domain} = {
            dataset => $dataset,
            rows    => $decoded,
            label   => $label,
        };
        push @domain_order, $domain;
    }

    die "$format_name SDTM input requires exactly one <DM> dataset\n"
      unless exists $documents{DM};

    my ( %subjects, @subject_order );
    for my $row ( @{ $documents{DM}{rows} } ) {
        my $subject_id = _required_subject_id(
            $row,
            'DM',
            $documents{DM}{label},
            $format_name,
        );
        die "$format_name DM contains duplicate USUBJID <$subject_id>\n"
          if exists $subjects{$subject_id};

        $subjects{$subject_id} = {
            id           => $subject_id,
            sourceFormat => $source_format,
            domains      => { DM => [$row] },
            metadata     => {
                $version_key => $documents{DM}{dataset}{$version_key},
            },
        };
        $subjects{$subject_id}{metadata}{studyOID} = $study_oid
          if defined $study_oid;
        for my $field ( @{$subject_metadata_fields} ) {
            next unless exists $documents{DM}{dataset}{$field};
            my $value = $documents{DM}{dataset}{$field};
            $subjects{$subject_id}{metadata}{$field} =
              ref($value) ? dclone($value) : $value;
        }
        push @subject_order, $subject_id;
    }

    die "$format_name DM does not contain any participant records\n"
      unless @subject_order;

    my %subject_independent;
    for my $domain (@domain_order) {
        next if $domain eq 'DM';

        my $document = $documents{$domain};
        my $has_usubjid = scalar grep { uc( $_->{name} ) eq 'USUBJID' }
          @{ $document->{dataset}{columns} };

        if ( !$has_usubjid ) {
            $subject_independent{$domain} = $document->{rows};
            next;
        }

        for my $row ( @{ $document->{rows} } ) {
            my $subject_id = _required_subject_id(
                $row,
                $domain,
                $document->{label},
                $format_name,
            );
            die "$format_name domain <$domain> references unknown USUBJID <$subject_id>\n"
              unless exists $subjects{$subject_id};
            push @{ $subjects{$subject_id}{domains}{$domain} }, $row;
        }
    }

    my @metadata_domains = map {
        my $dataset = $documents{$_}{dataset};
        +{
            name         => $_,
            label        => $dataset->{label},
            itemGroupOID => $dataset->{itemGroupOID},
            records      => $dataset->{records},
            columns      => dclone( $dataset->{columns} ),
        }
    } @domain_order;

    my $metadata = {
        $version_key => $documents{DM}{dataset}{$version_key},
        domains      => \@metadata_domains,
    };
    $metadata->{studyOID} = $study_oid if defined $study_oid;

    for my $field (
        qw(originator sourceSystem metaDataRef metaDataVersionOID defineXMLVersion)
      )
    {
        if ( exists $documents{DM}{dataset}{$field} ) {
            my $value = $documents{DM}{dataset}{$field};
            $metadata->{$field} = ref($value) ? dclone($value) : $value;
        }
    }

    return {
        subjects            => [ map { $subjects{$_} } @subject_order ],
        metadata            => $metadata,
        subject_independent => \%subject_independent,
    };
}

sub sdtm_source_fields {
    my ($metadata) = @_;
    my @fields;
    for my $domain ( @{ $metadata->{domains} || [] } ) {
        my $domain_name = uc( _trim( $domain->{name} ) // q{} );
        next unless length $domain_name;
        for my $column ( @{ $domain->{columns} || [] } ) {
            my $field = uc( _trim( $column->{name} ) // q{} );
            push @fields, "$domain_name.$field" if length $field;
        }
    }
    return \@fields;
}

sub collect_sdtm_source_terms {
    my ($metadata) = @_;
    my %terms;
    for my $domain ( @{ $metadata->{domains} || [] } ) {
        my $domain_name = uc( _trim( $domain->{name} ) // q{} );
        next unless length $domain_name;
        for my $column ( @{ $domain->{columns} || [] } ) {
            next unless ref( $column->{controlledTerms} ) eq 'HASH';
            my $field = uc( _trim( $column->{name} ) // q{} );
            next unless length $field;
            $terms{"$domain_name.$field"} = dclone( $column->{controlledTerms} );
        }
    }
    return \%terms;
}

sub derive_sdtm_entity_overrides {
    my ( $converter, $metadata, $subject_independent, %option ) = @_;
    my $study_oid = $metadata->{studyOID};
    return {} unless defined $study_oid && length $study_oid;

    my $study_name = $study_oid;
    for my $row ( @{ $subject_independent->{TS} || [] } ) {
        next unless uc( _trim( $row->{TSPARMCD} ) // q{} ) eq 'TITLE';
        my $title = _trim( $row->{TSVAL} );
        $study_name = $title if defined $title && length $title;
        last;
    }

    my $format_label = $option{format_label} || 'Dataset-JSON';
    my $provenance_key = $option{provenance_key} || 'datasetJson';
    my $overrides = {
        datasets => {
            id          => $study_oid,
            name        => $study_name,
            description => "CDISC $format_label study $study_oid.",
        },
        cohorts => {
            id         => $study_oid . '-cohort',
            name       => $study_name,
            cohortType => 'study-defined',
        },
    };

    if ( $converter->{source_info} // 1 ) {
        $overrides->{datasets}{info}{$provenance_key} = dclone($metadata);
        if ( keys %{$subject_independent} ) {
            $overrides->{datasets}{info}{$provenance_key}
              {subjectIndependentDomains} = dclone($subject_independent);
        }
    }

    return $overrides;
}

sub _decode_dataset {
    my ( $dataset, $domain, $label, $format_name ) = @_;
    my $columns = $dataset->{columns};
    die "$format_name domain <$domain> does not define any columns\n"
      unless ref($columns) eq 'ARRAY' && @{$columns};

    my ( %seen, @names );
    for my $column ( @{$columns} ) {
        my $name = uc( _trim( $column->{name} ) // q{} );
        die "$format_name domain <$domain> contains an empty column name\n"
          unless length $name;
        die "$format_name domain <$domain> contains duplicate column <$name>\n"
          if $seen{$name}++;
        push @names, $name;
    }

    my $rows = $dataset->{rows} || [];
    die "$format_name domain <$domain> declares $dataset->{records} records but contains "
      . scalar( @{$rows} ) . " rows\n"
      unless $dataset->{records} == @{$rows};

    my @decoded;
    for my $row_index ( 0 .. $#{$rows} ) {
        my $row = $rows->[$row_index];
        my $number = $row_index + 1;
        die "$format_name domain <$domain> row $number must contain an array\n"
          unless ref($row) eq 'ARRAY';
        die "$format_name domain <$domain> row $number has " . scalar( @{$row} )
          . ' values but ' . scalar(@names) . " columns are defined\n"
          unless @{$row} == @names;

        my %record;
        for my $column_index ( 0 .. $#names ) {
            my $value  = $row->[$column_index];
            my $column = $columns->[$column_index];
            _validate_value_type(
                $value,
                $column->{dataType},
                "$domain row $number column $names[$column_index]",
                $format_name,
            );
            $record{ $names[$column_index] } = $value;
        }

        if ( exists $record{DOMAIN}
            && defined $record{DOMAIN}
            && length( _trim( $record{DOMAIN} ) // q{} )
            && uc( _trim( $record{DOMAIN} ) ) ne $domain )
        {
            die "$format_name domain <$domain> row $number contains DOMAIN <$record{DOMAIN}>\n";
        }

        push @decoded, \%record;
    }

    return \@decoded;
}

sub _validate_value_type {
    my ( $value, $type, $where, $format_name ) = @_;

    return 1 if !defined $value || ( !ref($value) && $value eq q{} );

    if ( $type eq 'integer' ) {
        die "$format_name $where must contain an integer\n"
          unless !ref($value) && looks_like_number($value) && int($value) == $value;
        return 1;
    }

    if ( $type eq 'decimal' || $type eq 'float' || $type eq 'double' ) {
        die "$format_name $where must contain a number\n"
          unless !ref($value) && looks_like_number($value);
        return 1;
    }

    if ( $type eq 'boolean' ) {
        die "$format_name $where must contain a JSON boolean\n"
          unless blessed($value) && $value->isa('JSON::PP::Boolean');
        return 1;
    }

    die "$format_name $where must contain a string\n" if ref($value);
    return 1;
}

sub _required_subject_id {
    my ( $row, $domain, $label, $format_name ) = @_;
    my $subject_id = _trim( $row->{USUBJID} );
    die "$format_name domain <$domain> in <$label> contains a row without USUBJID\n"
      unless defined $subject_id && length $subject_id;
    return $subject_id;
}

sub _trim {
    my ($value) = @_;
    return unless defined $value;
    return $value if ref($value);
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

1;
