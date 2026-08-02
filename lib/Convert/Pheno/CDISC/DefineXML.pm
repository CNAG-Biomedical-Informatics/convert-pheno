package Convert::Pheno::CDISC::DefineXML;

use strict;
use warnings;

use Exporter 'import';
use Path::Tiny qw(path);
use Storable qw(dclone);
use XML::Fast qw(xml2hash);

use Convert::Pheno::CDISC::ODM::Detector qw(
  attribute_by_namespace
  detect_odm_document
);
use Convert::Pheno::CDISC::ODM::Util qw(
  attr
  child
  children
  element_text
);

our @EXPORT_OK = qw(
  enrich_dataset_from_define
  load_define_catalog
  resolve_define_group
);

my $DEFINE_XML_NAMESPACE = qr{\Ahttp://www\.cdisc\.org/ns/def/v2\.[01]\z};

sub load_define_catalog {
    my ( $input, $label ) = @_;
    $label ||= 'Define-XML';
    my $document = _xml_document( $input, $label );
    my $descriptor = detect_odm_document($document);
    die "$label must use the ODM 1.3 namespace\n"
      unless $descriptor->{adapter} eq 'v1';

    my %seen_namespace;
    my @define_namespaces = grep {
        $_ =~ $DEFINE_XML_NAMESPACE && !$seen_namespace{$_}++
    } values %{ $descriptor->{namespaces} };
    die "$label is missing a supported Define-XML v2.0 or v2.1 namespace\n"
      unless @define_namespaces == 1;
    my $define_namespace = $define_namespaces[0];

    my %providers;
    for my $study ( @{ children( $descriptor->{root}, 'Study' ) } ) {
        my $study_oid = attr( $study, 'OID' );
        next unless defined $study_oid && length $study_oid;

        for my $version ( @{ children( $study, 'MetaDataVersion' ) } ) {
            my $version_oid = attr( $version, 'OID' );
            next unless defined $version_oid && length $version_oid;
            die "$label contains duplicate metadata <StudyOID=$study_oid, MetaDataVersionOID=$version_oid>\n"
              if exists $providers{$study_oid}{$version_oid};

            my $define_version = attribute_by_namespace(
                $version,
                $descriptor->{namespaces},
                $define_namespace,
                'DefineVersion',
            );
            $define_version //= $define_namespace =~ /v2\.1\z/ ? '2.1' : '2.0';

            my %code_lists;
            for my $code_list ( @{ children( $version, 'CodeList' ) } ) {
                my $oid = attr( $code_list, 'OID' );
                next unless defined $oid && length $oid;
                die "$label metadata <$study_oid/$version_oid> contains duplicate CodeList <$oid>\n"
                  if exists $code_lists{$oid};

                my %terms;
                for my $item (
                    @{ children( $code_list, 'CodeListItem' ) },
                    @{ children( $code_list, 'EnumeratedItem' ) }
                  )
                {
                    my $code = attr( $item, 'CodedValue' );
                    next unless defined $code && length $code;
                    die "$label CodeList <$oid> contains duplicate CodedValue <$code>\n"
                      if exists $terms{$code};

                    my $decode = child( $item, 'Decode' );
                    my $term = {
                        label => _translated_text($decode)
                          // attr( $item, 'Name' )
                          // $code,
                    };
                    my $nci_id = _nci_ext_code_id( $item, $label, $oid, $code );
                    $term->{id} = $nci_id if defined $nci_id;
                    $terms{$code} = $term;
                }
                $code_lists{$oid} = \%terms;
            }

            my %items;
            for my $item ( @{ children( $version, 'ItemDef' ) } ) {
                my $oid = attr( $item, 'OID' );
                next unless defined $oid && length $oid;
                die "$label metadata <$study_oid/$version_oid> contains duplicate ItemDef <$oid>\n"
                  if exists $items{$oid};

                my $name = attr( $item, 'Name' );
                die "$label ItemDef <$oid> is missing Name\n"
                  unless defined $name && length $name;
                my @code_list_refs = @{ children( $item, 'CodeListRef' ) };
                die "$label ItemDef <$oid> has multiple CodeListRef elements\n"
                  if @code_list_refs > 1;

                my $item_metadata = {
                    itemOID => $oid,
                    name    => $name,
                    label   => _description($item) // $name,
                    dataType => lc( attr( $item, 'DataType' ) // 'text' ),
                };
                if (@code_list_refs) {
                    my $code_list_oid = attr( $code_list_refs[0], 'CodeListOID' );
                    die "$label ItemDef <$oid> contains CodeListRef without CodeListOID\n"
                      unless defined $code_list_oid && length $code_list_oid;
                    die "$label ItemDef <$oid> references missing CodeList <$code_list_oid>\n"
                      unless exists $code_lists{$code_list_oid};
                    $item_metadata->{codeListOID} = $code_list_oid;
                    $item_metadata->{controlledTerms} =
                      dclone( $code_lists{$code_list_oid} );
                }
                $items{$oid} = $item_metadata;
            }

            my %groups;
            for my $group ( @{ children( $version, 'ItemGroupDef' ) } ) {
                my $oid = attr( $group, 'OID' );
                next unless defined $oid && length $oid;
                die "$label metadata <$study_oid/$version_oid> contains duplicate ItemGroupDef <$oid>\n"
                  if exists $groups{$oid};

                my @references = @{ children( $group, 'ItemRef' ) };
                die "$label ItemGroupDef <$oid> does not reference any columns\n"
                  unless @references;

                my ( @columns, %column_oid, %column_name );
                for my $reference (@references) {
                    my $item_oid = attr( $reference, 'ItemOID' );
                    die "$label ItemGroupDef <$oid> contains ItemRef without ItemOID\n"
                      unless defined $item_oid && length $item_oid;
                    die "$label ItemGroupDef <$oid> references missing ItemDef <$item_oid>\n"
                      unless exists $items{$item_oid};
                    die "$label ItemGroupDef <$oid> references ItemDef <$item_oid> more than once\n"
                      if $column_oid{$item_oid}++;

                    my $column = dclone( $items{$item_oid} );
                    my $name = uc $column->{name};
                    die "$label ItemGroupDef <$oid> contains duplicate column name <$name>\n"
                      if $column_name{$name}++;
                    push @columns, $column;
                }

                my $domain = attr( $group, 'Domain' ) // attr( $group, 'Name' );
                die "$label ItemGroupDef <$oid> is missing Domain and Name\n"
                  unless defined $domain && length $domain;
                $groups{$oid} = {
                    itemGroupOID => $oid,
                    name         => uc($domain),
                    label        => _description($group)
                      // attr( $group, 'Name' )
                      // $domain,
                    columns => \@columns,
                };
            }

            $providers{$study_oid}{$version_oid} = {
                defineXMLVersion  => $define_version,
                studyOID          => $study_oid,
                metaDataVersionOID => $version_oid,
                groups            => \%groups,
            };
        }
    }

    die "$label does not contain usable Study metadata\n"
      unless keys %providers;
    return {
        fileOID   => attr( $descriptor->{root}, 'FileOID' ),
        providers => \%providers,
    };
}

sub resolve_define_group {
    my ( $catalog, $study_oid, $version_oid, $group_oid, $label ) = @_;
    $label ||= 'Dataset';
    die "$label is missing StudyOID\n"
      unless defined $study_oid && length $study_oid;
    die "$label is missing ItemGroupOID\n"
      unless defined $group_oid && length $group_oid;

    my $study_providers = $catalog->{providers}{$study_oid};
    die "$label references missing Define-XML StudyOID <$study_oid>\n"
      unless ref($study_providers) eq 'HASH';

    my $provider;
    if ( defined $version_oid && length $version_oid ) {
        $provider = $study_providers->{$version_oid};
        die "$label references missing Define-XML metadata <StudyOID=$study_oid, MetaDataVersionOID=$version_oid>\n"
          unless $provider;
    }
    else {
        my @versions = sort keys %{$study_providers};
        die "$label does not declare MetaDataVersionOID and Define-XML contains multiple versions for StudyOID <$study_oid>\n"
          unless @versions == 1;
        $version_oid = $versions[0];
        $provider = $study_providers->{$version_oid};
    }

    my $group = $provider->{groups}{$group_oid};
    die "$label references missing Define-XML ItemGroupDef <$group_oid>\n"
      unless $group;
    return ( $provider, $group );
}

sub enrich_dataset_from_define {
    my ( $dataset, $catalog, $label ) = @_;
    $label ||= 'Dataset';
    my ( $provider, $group ) = resolve_define_group(
        $catalog,
        $dataset->{studyOID},
        $dataset->{metaDataVersionOID},
        $dataset->{itemGroupOID},
        $label,
    );

    my %define_column = map { $_->{itemOID} => $_ } @{ $group->{columns} };
    for my $column ( @{ $dataset->{columns} || [] } ) {
        my $item_oid = $column->{itemOID};
        next unless defined $item_oid && exists $define_column{$item_oid};
        my $defined = $define_column{$item_oid};
        $column->{codeListOID} = $defined->{codeListOID}
          if exists $defined->{codeListOID};
        $column->{controlledTerms} = dclone( $defined->{controlledTerms} )
          if exists $defined->{controlledTerms};
    }

    $dataset->{metaDataVersionOID} = $provider->{metaDataVersionOID};
    $dataset->{defineXMLVersion}   = $provider->{defineXMLVersion};
    return $dataset;
}

sub _xml_document {
    my ( $input, $label ) = @_;
    return dclone($input) if ref($input) eq 'HASH';
    die "XML input <$label> must contain a file path, XML string, or parsed object\n"
      if ref($input) || !defined $input;

    my $xml = $input !~ /[<\r\n]/ && -f $input
      ? path($input)->slurp_utf8
      : $input;
    my $document = eval { xml2hash $xml, attr => '-', text => '~' };
    die "Could not parse XML input <$label>: $@" if $@;
    return $document;
}

sub _nci_ext_code_id {
    my ( $item, $label, $code_list_oid, $code ) = @_;
    my %ids;
    for my $alias ( @{ children( $item, 'Alias' ) } ) {
        my $context = lc( attr( $alias, 'Context' ) // q{} );
        next unless $context eq 'nci:extcodeid';
        my $name = attr( $alias, 'Name' );
        next unless defined $name;
        $name =~ s/^NCIT://i;
        next unless $name =~ /\AC\d+\z/i;
        $ids{uc $name} = 1;
    }

    my @ids = sort keys %ids;
    die "$label CodeList <$code_list_oid> CodedValue <$code> contains conflicting nci:ExtCodeID aliases\n"
      if @ids > 1;
    return $ids[0];
}

sub _description {
    my ($node) = @_;
    return _translated_text( child( $node, 'Description' ) );
}

sub _translated_text {
    my ($node) = @_;
    return unless defined $node;
    my $translated = child( $node, 'TranslatedText' );
    return element_text($translated) if defined $translated;
    return element_text($node);
}

1;
