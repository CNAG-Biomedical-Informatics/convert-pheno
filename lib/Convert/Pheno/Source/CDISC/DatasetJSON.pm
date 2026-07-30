package Convert::Pheno::Source::CDISC::DatasetJSON;

use strict;
use warnings;

use File::ShareDir::ProjectDistDir qw(dist_dir);
use File::Spec::Functions qw(catfile);
use JSON::Validator;
use Scalar::Util qw(blessed looks_like_number);
use Storable qw(dclone);

use Convert::Pheno::IO::FileIO qw(read_json);
use Convert::Pheno::Source::Result;

my $SCHEMA_FILE =
  catfile( dist_dir('Convert-Pheno'), 'schema', 'dataset-json-1.1.json' );

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};

    my ( @datasets, @labels );
    if ( exists $converter->{data} ) {
        my $data = $converter->{data};
        @datasets = ref($data) eq 'ARRAY' ? @{$data} : ($data);
        @datasets = map { dclone($_) } @datasets;
        @labels   = map { 'in-memory dataset ' . ( $_ + 1 ) } 0 .. $#datasets;
    }
    else {
        my @files = @{ $converter->{in_files} || [] };
        push @files, $converter->{in_file}
          if !@files && defined $converter->{in_file};
        die "Dataset-JSON input requires at least one JSON file\n" unless @files;

        for my $file (@files) {
            push @datasets, read_json($file);
            push @labels,   $file;
        }
    }

    my $normalized = _normalize_datasets( \@datasets, \@labels );

    return Convert::Pheno::Source::Result->new(
        {
            data  => $normalized->{subjects},
            owned => 1,
            artifacts => {
                dataset_metadata            => $normalized->{metadata},
                subject_independent_domains => $normalized->{subject_independent},
                derived_entity_overrides    => _derived_entity_overrides(
                    $converter,
                    $normalized->{metadata},
                    $normalized->{subject_independent},
                ),
            },
        }
    );
}

sub _normalize_datasets {
    my ( $datasets, $labels ) = @_;
    die "Dataset-JSON input does not contain any datasets\n" unless @{$datasets};

    my $validator = JSON::Validator->new;
    $validator->schema( read_json($SCHEMA_FILE) );

    my %documents;
    my @domain_order;
    my $study_oid;

    for my $index ( 0 .. $#{$datasets} ) {
        my $dataset = $datasets->[$index];
        my $label   = $labels->[$index];

        die "Dataset-JSON input <$label> must contain a JSON object\n"
          unless ref($dataset) eq 'HASH';

        my @errors = $validator->validate($dataset);
        if (@errors) {
            die "Dataset-JSON schema validation failed for <$label>:\n"
              . join( q{}, map { "  $_\n" } @errors );
        }

        my $domain = _trim( $dataset->{name} );
        $domain = uc $domain;
        die "Dataset-JSON input <$label> has an invalid SDTM domain name <$domain>\n"
          unless $domain =~ /\A[A-Z][A-Z0-9]{0,7}\z/;
        die "Dataset-JSON domain <$domain> was supplied more than once\n"
          if exists $documents{$domain};

        my $current_study = _trim( $dataset->{studyOID} );
        if ( defined $current_study && length $current_study ) {
            $study_oid //= $current_study;
            die "Dataset-JSON files contain inconsistent studyOID values <$study_oid> and <$current_study>\n"
              if $current_study ne $study_oid;
        }

        my $decoded = _decode_dataset( $dataset, $domain, $label );
        $documents{$domain} = {
            dataset => $dataset,
            rows    => $decoded,
            label   => $label,
        };
        push @domain_order, $domain;
    }

    die "Dataset-JSON SDTM input requires exactly one <DM> dataset\n"
      unless exists $documents{DM};

    my ( %subjects, @subject_order );
    for my $row ( @{ $documents{DM}{rows} } ) {
        my $subject_id = _required_subject_id( $row, 'DM', $documents{DM}{label} );
        die "Dataset-JSON DM contains duplicate USUBJID <$subject_id>\n"
          if exists $subjects{$subject_id};

        $subjects{$subject_id} = {
            id       => $subject_id,
            domains  => { DM => [$row] },
            metadata => {
                datasetJSONVersion => $documents{DM}{dataset}{datasetJSONVersion},
            },
        };
        $subjects{$subject_id}{metadata}{studyOID} = $study_oid
          if defined $study_oid;
        push @subject_order, $subject_id;
    }

    die "Dataset-JSON DM does not contain any participant records\n"
      unless @subject_order;

    my %subject_independent;
    for my $domain (@domain_order) {
        next if $domain eq 'DM';

        my $document = $documents{$domain};
        my $has_usubjid = scalar grep { $_ eq 'USUBJID' }
          map { uc $_->{name} } @{ $document->{dataset}{columns} };

        if ( !$has_usubjid ) {
            $subject_independent{$domain} = $document->{rows};
            next;
        }

        for my $row ( @{ $document->{rows} } ) {
            my $subject_id = _required_subject_id( $row, $domain, $document->{label} );
            die "Dataset-JSON domain <$domain> references unknown USUBJID <$subject_id>\n"
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
            columns      => [ map { +{ %{$_} } } @{ $dataset->{columns} } ],
        }
    } @domain_order;

    my $metadata = {
        datasetJSONVersion => $documents{DM}{dataset}{datasetJSONVersion},
        domains            => \@metadata_domains,
    };
    $metadata->{studyOID} = $study_oid if defined $study_oid;

    for my $field (qw(originator sourceSystem metaDataRef metaDataVersionOID)) {
        $metadata->{$field} = dclone( $documents{DM}{dataset}{$field} )
          if exists $documents{DM}{dataset}{$field};
    }

    return {
        subjects            => [ map { $subjects{$_} } @subject_order ],
        metadata            => $metadata,
        subject_independent => \%subject_independent,
    };
}

sub _decode_dataset {
    my ( $dataset, $domain, $label ) = @_;
    my $columns = $dataset->{columns};
    die "Dataset-JSON domain <$domain> does not define any columns\n"
      unless @{$columns};

    my ( %seen, @names );
    for my $column ( @{$columns} ) {
        my $name = uc _trim( $column->{name} );
        die "Dataset-JSON domain <$domain> contains an empty column name\n"
          unless length $name;
        die "Dataset-JSON domain <$domain> contains duplicate column <$name>\n"
          if $seen{$name}++;
        push @names, $name;
    }

    my $rows = $dataset->{rows} || [];
    die "Dataset-JSON domain <$domain> declares $dataset->{records} records but contains "
      . scalar( @{$rows} ) . " rows\n"
      unless $dataset->{records} == @{$rows};

    my @decoded;
    for my $row_index ( 0 .. $#{$rows} ) {
        my $row = $rows->[$row_index];
        my $number = $row_index + 1;
        die "Dataset-JSON domain <$domain> row $number must contain an array\n"
          unless ref($row) eq 'ARRAY';
        die "Dataset-JSON domain <$domain> row $number has " . scalar( @{$row} )
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
            );
            $record{ $names[$column_index] } = $value;
        }

        if ( exists $record{DOMAIN}
            && defined $record{DOMAIN}
            && length _trim( $record{DOMAIN} )
            && uc( _trim( $record{DOMAIN} ) ) ne $domain )
        {
            die "Dataset-JSON domain <$domain> row $number contains DOMAIN <$record{DOMAIN}>\n";
        }

        push @decoded, \%record;
    }

    return \@decoded;
}

sub _validate_value_type {
    my ( $value, $type, $where ) = @_;

    return 1 if !defined $value || ( !ref($value) && $value eq q{} );

    if ( $type eq 'integer' ) {
        die "Dataset-JSON $where must contain an integer\n"
          unless !ref($value) && looks_like_number($value) && int($value) == $value;
        return 1;
    }

    if ( $type eq 'decimal' || $type eq 'float' || $type eq 'double' ) {
        die "Dataset-JSON $where must contain a number\n"
          unless !ref($value) && looks_like_number($value);
        return 1;
    }

    if ( $type eq 'boolean' ) {
        die "Dataset-JSON $where must contain a JSON boolean\n"
          unless blessed($value) && $value->isa('JSON::PP::Boolean');
        return 1;
    }

    die "Dataset-JSON $where must contain a string\n" if ref($value);
    return 1;
}

sub _required_subject_id {
    my ( $row, $domain, $label ) = @_;
    my $subject_id = _trim( $row->{USUBJID} );
    die "Dataset-JSON domain <$domain> in <$label> contains a row without USUBJID\n"
      unless defined $subject_id && length $subject_id;
    return $subject_id;
}

sub _derived_entity_overrides {
    my ( $converter, $metadata, $subject_independent ) = @_;
    my $study_oid = $metadata->{studyOID};
    return {} unless defined $study_oid && length $study_oid;

    my $study_name = $study_oid;
    for my $row ( @{ $subject_independent->{TS} || [] } ) {
        next unless uc( _trim( $row->{TSPARMCD} ) // q{} ) eq 'TITLE';
        my $title = _trim( $row->{TSVAL} );
        $study_name = $title if defined $title && length $title;
        last;
    }

    my $overrides = {
        datasets => {
            id          => $study_oid,
            name        => $study_name,
            description => "CDISC Dataset-JSON study $study_oid.",
        },
        cohorts => {
            id         => $study_oid . '-cohort',
            name       => $study_name,
            cohortType => 'study-defined',
        },
    };

    if ( $converter->{source_info} // 1 ) {
        $overrides->{datasets}{info}{datasetJson} = dclone($metadata);
        if ( keys %{$subject_independent} ) {
            $overrides->{datasets}{info}{datasetJson}{subjectIndependentDomains} =
              dclone($subject_independent);
        }
    }

    return $overrides;
}

sub _trim {
    my ($value) = @_;
    return unless defined $value;
    return $value if ref($value);
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

1;
