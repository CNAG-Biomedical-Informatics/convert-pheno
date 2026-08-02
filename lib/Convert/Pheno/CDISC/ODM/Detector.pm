package Convert::Pheno::CDISC::ODM::Detector;

use strict;
use warnings;

use Exporter 'import';

our @EXPORT_OK = qw(
  attribute_by_namespace
  detect_odm_document
);

my %SUPPORTED = (
    'http://www.cdisc.org/ns/odm/v1.3' => {
        adapter  => 'v1',
        versions => { map { $_ => 1 } qw(1.3.1 1.3.2) },
    },
    'http://www.cdisc.org/ns/odm/v2.0' => {
        adapter  => 'v2',
        versions => { '2.0' => 1, '2.0.0' => 1 },
    },
);

sub detect_odm_document {
    my ($document) = @_;
    die "CDISC-ODM input must contain one ODM root element\n"
      unless ref($document) eq 'HASH';

    my ( $root_key, $root ) = _root_element($document);
    die "CDISC-ODM input must contain one ODM root element\n"
      unless defined $root_key && ref($root) eq 'HASH';

    my $namespace = $root->{'-xmlns'};
    if ( !defined $namespace && $root_key =~ /\A([^:]+):ODM\z/ ) {
        $namespace = $root->{ '-xmlns:' . $1 };
    }
    die "CDISC-ODM root is missing its ODM namespace\n"
      unless defined $namespace && length $namespace;

    my $supported = $SUPPORTED{$namespace};
    die "Unsupported CDISC-ODM namespace <$namespace>\n" unless $supported;

    my $version = $root->{'-ODMVersion'};
    die "CDISC-ODM root is missing <ODMVersion>\n"
      unless defined $version && length $version;
    die "CDISC-ODM namespace/version mismatch: namespace <$namespace> does not support <ODMVersion=$version>\n"
      unless $supported->{versions}{$version};

    my $file_type = $root->{'-FileType'} // q{};
    die "Unsupported CDISC-ODM FileType <$file_type>; only Snapshot input is supported\n"
      unless lc($file_type) eq 'snapshot';

    my $namespaces = _namespace_map($root);
    my $source_system = $root->{'-SourceSystem'} // q{};
    my $vendor = _detect_vendor( $source_system, $namespaces );

    return {
        adapter        => $supported->{adapter},
        namespace      => $namespace,
        namespaces     => $namespaces,
        odmVersion     => $version,
        recordProfile  => $vendor eq 'redcap' ? 'redcap' : 'cdisc-odm',
        root            => $root,
        sourceSystem    => $source_system,
        vendor          => $vendor,
    };
}

sub attribute_by_namespace {
    my ( $node, $namespaces, $namespace_match, $local_name ) = @_;
    return unless ref($node) eq 'HASH';

    for my $key ( keys %{$node} ) {
        next unless $key =~ /\A-([^:]+):\Q$local_name\E\z/;
        my $uri = $namespaces->{$1};
        next unless defined $uri;
        return $node->{$key} if _namespace_matches( $uri, $namespace_match );
    }
    return;
}

sub _root_element {
    my ($document) = @_;
    my @keys = grep { $_ eq 'ODM' || /:ODM\z/ } keys %{$document};
    return if @keys != 1;
    return ( $keys[0], $document->{ $keys[0] } );
}

sub _namespace_map {
    my ($root) = @_;
    my %namespaces;
    for my $key ( keys %{$root} ) {
        next unless $key =~ /\A-xmlns(?::(.+))?\z/;
        $namespaces{ defined $1 ? $1 : q{} } = $root->{$key};
    }
    return \%namespaces;
}

sub _detect_vendor {
    my ( $source_system, $namespaces ) = @_;
    return 'redcap' if $source_system =~ /redcap/i;
    return 'openclinica' if $source_system =~ /openclinica/i;

    for my $uri ( values %{$namespaces} ) {
        return 'redcap' if $uri =~ m{\Ahttps?://(?:www\.)?projectredcap\.org/?\z}i;
        return 'openclinica' if $uri =~ /openclinica/i;
    }
    return 'standard';
}

sub _namespace_matches {
    my ( $uri, $match ) = @_;
    return $uri eq $match unless ref($match) eq 'Regexp';
    return $uri =~ $match ? 1 : 0;
}

1;
