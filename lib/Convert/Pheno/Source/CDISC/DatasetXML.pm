package Convert::Pheno::Source::CDISC::DatasetXML;

use strict;
use warnings;

use JSON::PP ();
use Path::Tiny qw(path);
use Scalar::Util qw(looks_like_number);
use Storable qw(dclone);
use XML::Fast qw(xml2hash);

use Convert::Pheno::CDISC::DefineXML qw(
  load_define_catalog
  resolve_define_group
);
use Convert::Pheno::CDISC::ODM::Detector qw(
  attribute_by_namespace
  detect_odm_document
);
use Convert::Pheno::CDISC::ODM::Util qw(
  attr
  children
);
use Convert::Pheno::CDISC::SDTM::Normalizer qw(
  derive_sdtm_entity_overrides
  normalize_sdtm_datasets
);
use Convert::Pheno::CDISC::SDTM::Terminology qw(prepare_sdtm_terminology);
use Convert::Pheno::Mapping::Shared qw(get_info);
use Convert::Pheno::Source::Result;

my $DATASET_XML_NAMESPACE = 'http://www.cdisc.org/ns/Dataset-XML/v1.0';

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};
    my ( $define_input, @dataset_documents, @labels );

    if ( exists $converter->{data} ) {
        my $input = $converter->{data};
        die "In-memory Dataset-XML input must contain <define> and <datasets>\n"
          unless ref($input) eq 'HASH'
          && exists $input->{define}
          && ref( $input->{datasets} ) eq 'ARRAY';

        $define_input = _clone_input( $input->{define} );
        @dataset_documents = map {
            _xml_document( _clone_input($_), 'in-memory Dataset-XML' )
        } @{ $input->{datasets} };
        @labels = map { 'in-memory Dataset-XML dataset ' . ( $_ + 1 ) }
          0 .. $#dataset_documents;
    }
    else {
        my $define_file = $converter->{define_xml};
        die "Dataset-XML input requires --define-xml <file>\n"
          unless defined $define_file && length $define_file;
        die "Dataset-XML Define-XML file <$define_file> does not exist\n"
          unless -f $define_file;

        my @files = @{ $converter->{in_files} || [] };
        push @files, $converter->{in_file}
          if !@files && defined $converter->{in_file};
        die "Dataset-XML input requires at least one XML dataset file\n"
          unless @files;

        $define_input = $define_file;
        for my $file (@files) {
            die "Dataset-XML file <$file> does not exist\n" unless -f $file;
            push @dataset_documents, _read_xml_file($file);
            push @labels, $file;
        }
    }

    my $catalog = load_define_catalog( $define_input, 'Define-XML' );
    my @datasets;
    my $metadata_version_oid;
    for my $index ( 0 .. $#dataset_documents ) {
        my $dataset = _dataset_document(
            $dataset_documents[$index],
            $labels[$index],
            $catalog,
        );
        $metadata_version_oid //= $dataset->{metaDataVersionOID};
        die "Dataset-XML files contain inconsistent MetaDataVersionOID values <$metadata_version_oid> and <$dataset->{metaDataVersionOID}>\n"
          if $dataset->{metaDataVersionOID} ne $metadata_version_oid;
        push @datasets, $dataset;
    }

    my $normalized = normalize_sdtm_datasets(
        \@datasets,
        \@labels,
        format_name   => 'Dataset-XML',
        source_format => 'dataset-xml',
        version_key   => 'datasetXMLVersion',
        subject_metadata_fields => [
            qw(defineXMLVersion metaDataVersionOID metaDataRef originator sourceSystem)
        ],
    );
    my $terminology = prepare_sdtm_terminology(
        $converter,
        $normalized->{metadata},
    );

    return Convert::Pheno::Source::Result->new(
        {
            data  => $normalized->{subjects},
            owned => 1,
            artifacts => {
                dataset_metadata            => $normalized->{metadata},
                subject_independent_domains => $normalized->{subject_independent},
                terminology_mapping         => $terminology->{mapping},
                source_terminology          => $terminology->{source_terms},
                terminology_requires_sqlite => $terminology->{requires_sqlite},
                derived_entity_overrides    => derive_sdtm_entity_overrides(
                    $converter,
                    $normalized->{metadata},
                    $normalized->{subject_independent},
                    format_label   => 'Dataset-XML',
                    provenance_key => 'datasetXml',
                ),
            },
        }
    );
}

sub _clone_input {
    my ($input) = @_;
    return ref($input) ? dclone($input) : $input;
}

sub _read_xml_file {
    my ($file) = @_;
    return _xml_document( path($file)->slurp_utf8, $file );
}

sub _xml_document {
    my ( $input, $label ) = @_;
    return $input if ref($input) eq 'HASH';
    die "XML input <$label> must contain an XML string or parsed object\n"
      if ref($input) || !defined $input;

    my $document = eval { xml2hash $input, attr => '-', text => '~' };
    die "Could not parse XML input <$label>: $@" if $@;
    return $document;
}

sub _dataset_document {
    my ( $document, $label, $catalog ) = @_;
    my $descriptor = detect_odm_document($document);
    die "Dataset-XML input <$label> must use the ODM 1.3 namespace\n"
      unless $descriptor->{adapter} eq 'v1';

    my %seen_namespace;
    my @dataset_namespaces = grep {
        $_ eq $DATASET_XML_NAMESPACE && !$seen_namespace{$_}++
    } values %{ $descriptor->{namespaces} };
    die "Dataset-XML input <$label> is missing the Dataset-XML v1.0 namespace\n"
      unless @dataset_namespaces == 1;
    my $dataset_version = attribute_by_namespace(
        $descriptor->{root},
        $descriptor->{namespaces},
        $DATASET_XML_NAMESPACE,
        'DatasetXMLVersion',
    );
    die "Dataset-XML input <$label> is missing DatasetXMLVersion\n"
      unless defined $dataset_version && length $dataset_version;
    die "Unsupported Dataset-XML version <$dataset_version> in <$label>; expected 1.0.0\n"
      unless $dataset_version eq '1.0.0';

    my @containers = (
        @{ children( $descriptor->{root}, 'ClinicalData' ) },
        @{ children( $descriptor->{root}, 'ReferenceData' ) },
    );
    die "Dataset-XML input <$label> must contain exactly one ClinicalData or ReferenceData element\n"
      unless @containers == 1;
    my $container = $containers[0];
    my $study_oid = attr( $container, 'StudyOID' );
    my $version_oid = attr( $container, 'MetaDataVersionOID' );
    die "Dataset-XML input <$label> is missing StudyOID or MetaDataVersionOID\n"
      unless defined $study_oid && length $study_oid
      && defined $version_oid && length $version_oid;

    my @groups = @{ children( $container, 'ItemGroupData' ) };
    die "Dataset-XML input <$label> does not contain any ItemGroupData rows\n"
      unless @groups;
    my $group_oid = attr( $groups[0], 'ItemGroupOID' );
    die "Dataset-XML input <$label> contains an ItemGroupData row without ItemGroupOID\n"
      unless defined $group_oid && length $group_oid;
    my ( $provider, $group ) = resolve_define_group(
        $catalog,
        $study_oid,
        $version_oid,
        $group_oid,
        "Dataset-XML input <$label>",
    );

    my %column_by_oid = map { $_->{itemOID} => $_ } @{ $group->{columns} };
    my ( @rows, %sequence );
    for my $row_index ( 0 .. $#groups ) {
        my $row = $groups[$row_index];
        my $current_group_oid = attr( $row, 'ItemGroupOID' );
        die "Dataset-XML input <$label> contains multiple ItemGroupOID values <$group_oid> and <$current_group_oid>\n"
          unless defined $current_group_oid && $current_group_oid eq $group_oid;

        my $sequence = attribute_by_namespace(
            $row,
            $descriptor->{namespaces},
            $DATASET_XML_NAMESPACE,
            'ItemGroupDataSeq',
        );
        die "Dataset-XML input <$label> row " . ( $row_index + 1 )
          . " is missing ItemGroupDataSeq\n"
          unless defined $sequence && length $sequence;
        die "Dataset-XML input <$label> contains duplicate ItemGroupDataSeq <$sequence>\n"
          if $sequence{$sequence}++;

        my %values;
        for my $item ( @{ children( $row, 'ItemData' ) } ) {
            my $item_oid = attr( $item, 'ItemOID' );
            die "Dataset-XML input <$label> row $sequence contains ItemData without ItemOID\n"
              unless defined $item_oid && length $item_oid;
            die "Dataset-XML input <$label> row $sequence contains ItemOID <$item_oid> outside ItemGroupDef <$group_oid>\n"
              unless exists $column_by_oid{$item_oid};
            die "Dataset-XML input <$label> row $sequence contains duplicate ItemOID <$item_oid>\n"
              if exists $values{$item_oid};

            my $value = attr( $item, 'Value' );
            die "Dataset-XML input <$label> row $sequence ItemOID <$item_oid> is missing Value; omit ItemData for a missing value\n"
              unless defined $value;
            $values{$item_oid} = _coerce_value(
                $value,
                $column_by_oid{$item_oid}{dataType},
            );
        }

        push @rows,
          [
            map {
                exists $values{ $_->{itemOID} }
                  ? $values{ $_->{itemOID} }
                  : undef
            } @{ $group->{columns} }
          ];
    }

    my $root = $descriptor->{root};
    my $prior_file_oid = attr( $root, 'PriorFileOID' );
    die "Dataset-XML input <$label> links to Define-XML <$prior_file_oid>, but the supplied Define-XML FileOID is <$catalog->{fileOID}>\n"
      if defined $prior_file_oid
      && defined $catalog->{fileOID}
      && $prior_file_oid ne $catalog->{fileOID};

    my $dataset = {
        datasetXMLVersion => $dataset_version,
        defineXMLVersion  => $provider->{defineXMLVersion},
        studyOID          => $study_oid,
        metaDataVersionOID => $version_oid,
        name              => $group->{name},
        label             => $group->{label},
        itemGroupOID      => $group_oid,
        records           => scalar(@rows),
        columns           => dclone( $group->{columns} ),
        rows              => \@rows,
    };
    $dataset->{originator} = attr( $root, 'Originator' )
      if defined attr( $root, 'Originator' );
    $dataset->{sourceSystem} = attr( $root, 'SourceSystem' )
      if defined attr( $root, 'SourceSystem' );
    $dataset->{metaDataRef} = $prior_file_oid if defined $prior_file_oid;
    return $dataset;
}

sub _coerce_value {
    my ( $value, $type ) = @_;
    $type = lc( $type // q{} );

    return 0 + $value
      if $type =~ /\A(?:integer|float|double|decimal)\z/
      && looks_like_number($value);
    return JSON::PP::true()
      if $type eq 'boolean' && $value =~ /\A(?:true|1)\z/i;
    return JSON::PP::false()
      if $type eq 'boolean' && $value =~ /\A(?:false|0)\z/i;
    return $value;
}

sub prepare {
    my ($self) = @_;
    my $converter = $self->{converter};
    return 1 if $converter->{dataset_xml_input_prepared}
      && exists $converter->{data};

    $converter->{_dataset_xml_source_data} = $converter->{data}
      if exists $converter->{data}
      && !exists $converter->{_dataset_xml_source_data};
    $converter->{data} = $converter->{_dataset_xml_source_data}
      if !exists $converter->{data}
      && exists $converter->{_dataset_xml_source_data};

    my $source = $self->load;
    $source->apply_to($converter);
    $converter->{dataset_xml_metadata} =
      $source->artifact('dataset_metadata');
    $converter->{dataset_xml_subject_independent_domains} =
      $source->artifact('subject_independent_domains');
    $converter->{source_derived_entity_overrides} =
      $source->artifact('derived_entity_overrides') || {};
    $converter->{sdtm_terminology_mapping} =
      $source->artifact('terminology_mapping') || {};
    $converter->{sdtm_source_terms} =
      $source->artifact('source_terminology') || {};
    $converter->{terminology_lookup_required} =
      $source->artifact('terminology_requires_sqlite') ? 1 : 0;
    $converter->{convertPheno} ||= get_info($converter);
    $converter->{dataset_xml_input_prepared} = 1;
    return 1;
}

1;
