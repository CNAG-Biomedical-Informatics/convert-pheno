package Convert::Pheno::Mapping::Compiler;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use IO::Uncompress::Gunzip qw($GunzipError);
use Path::Tiny qw(path);
use Storable qw(dclone);
use YAML::PP;

our @EXPORT_OK = qw(
  assert_mapping_version
  compile_mapping
  load_mapping_document
);

use constant MAPPING_VERSION       => 2;
use constant BEACON_SCHEMA_VERSION => '2.0.0';

sub load_mapping_document {
    my ($filepath) = @_;
    die "No mapping file was provided\n"
      unless defined $filepath && length $filepath;

    my $content;
    if ( $filepath =~ /\.gz\z/i ) {
        my $fh = IO::Uncompress::Gunzip->new($filepath)
          or die "Cannot open mapping file <$filepath>: $GunzipError\n";
        local $/;
        $content = <$fh>;
        close $fh;
        utf8::decode($content) unless utf8::is_utf8($content);
    }
    else {
        $content = path($filepath)->slurp_utf8;
    }

    # YAML::PP rejects duplicate mapping keys by default. This matters for
    # configuration: silently keeping the last duplicate can alter a clinical
    # mapping while leaving the file apparently valid to a reviewer.
    my $loader = YAML::PP->new(
        boolean        => 'JSON::PP',
        duplicate_keys => 0,
    );

    my $mapping = eval { $loader->load_string($content) };
    if ( my $error = $@ ) {
        chomp $error;
        die "Cannot parse mapping file <$filepath>: $error\n";
    }

    die "Mapping file <$filepath> must contain one object\n"
      unless ref($mapping) eq 'HASH';

    return $mapping;
}

sub assert_mapping_version {
    my ($mapping) = @_;
    die "Expected a mapping object\n" unless ref($mapping) eq 'HASH';

    if ( !exists $mapping->{mappingVersion} ) {
        die "This mapping uses the pre-v2 layout. Convert-Pheno requires <mappingVersion: 2>; migrate the mapping before retrying.\n";
    }

    die "Unsupported mappingVersion <$mapping->{mappingVersion}>; this Convert-Pheno release supports only <mappingVersion: 2>.\n"
      unless "$mapping->{mappingVersion}" eq MAPPING_VERSION;

    return 1;
}

sub compile_mapping {
    my ( $mapping, %arg ) = @_;
    assert_mapping_version($mapping);

    my $profile = $arg{source_profile};
    die "A source profile is required to compile the mapping\n"
      unless defined $profile && length $profile;

    _validate_target($mapping);
    _validate_source_profile( $mapping, $profile );

    my $compiled = dclone($mapping);
    $compiled->{_compiled} = {
        sourceProfile => $profile,
        recordProfile => $profile eq 'cdisc-odm' ? 'redcap' : $profile,
    };

    if ( exists $arg{headers} ) {
        _validate_source_fields( $compiled, $arg{headers}, $profile );
    }

    return $compiled;
}

sub _validate_target {
    my ($mapping) = @_;
    my $target = $mapping->{target};
    die "The mapping must declare <target.model: beacon> and <target.schemaVersion: 2.0.0>.\n"
      unless ref($target) eq 'HASH';

    die "Unsupported mapping target model <$target->{model}>; expected <beacon>.\n"
      unless defined $target->{model} && lc( $target->{model} ) eq 'beacon';

    die "Unsupported Beacon target schema version <$target->{schemaVersion}>; this release supports <2.0.0>.\n"
      unless defined $target->{schemaVersion}
      && "$target->{schemaVersion}" eq BEACON_SCHEMA_VERSION;

    return 1;
}

sub _validate_source_profile {
    my ( $mapping, $profile ) = @_;
    my $profiles = $mapping->{source}{profiles};
    die "The mapping must declare at least one <source.profiles> entry.\n"
      unless ref($profiles) eq 'ARRAY' && @{$profiles};

    return 1 if grep { $_ eq $profile } @{$profiles};

    die "Mapping source profile mismatch: route <$profile> is not listed in <source.profiles> ("
      . join( ', ', @{$profiles} ) . ").\n";
}

sub _validate_source_fields {
    my ( $mapping, $headers, $profile ) = @_;
    die "Expected source headers as an array reference\n"
      unless ref($headers) eq 'ARRAY';

    my %available = map { $_ => 1 } @{$headers};
    my %required;
    _collect_source_fields( $mapping, \%required );

    my @missing = sort grep { $required{$_} && !$available{$_} } keys %required;
    return 1 unless @missing;

    die "Mapping references source columns not present in the <$profile> input: <"
      . join( '>, <', @missing ) . ">.\n";
}

sub _collect_source_fields {
    my ( $node, $out, $optional ) = @_;
    return unless ref $node;

    if ( ref($node) eq 'ARRAY' ) {
        _collect_source_fields( $_, $out, $optional ) for @{$node};
        return;
    }

    return unless ref($node) eq 'HASH';

    my $node_optional = $optional ? 1 : 0;
    $node_optional = 1
      if exists $node->{source}
      && ref( $node->{source} ) eq 'HASH'
      && $node->{source}{optional};

    if ( exists $node->{sourceField} && !ref( $node->{sourceField} ) ) {
        _register_source_field( $out, $node->{sourceField}, $node_optional );
    }
    if ( exists $node->{sourceFields} && ref( $node->{sourceFields} ) eq 'ARRAY' ) {
        _register_source_field( $out, $_, $node_optional )
          for @{ $node->{sourceFields} };
    }

    if ( exists $node->{source} && ref( $node->{source} ) eq 'HASH' ) {
        my $source = $node->{source};
        _register_source_field( $out, $source->{field}, $node_optional )
          if exists $source->{field} && !ref( $source->{field} );
        _register_source_field( $out, $_, $node_optional )
          for @{ $source->{fields} || [] };
        _register_source_field( $out, $source->{primaryKey}, $node_optional )
          if exists $source->{primaryKey} && !ref( $source->{primaryKey} );
    }

    _collect_source_fields( $_, $out, $node_optional ) for values %{$node};
    return;
}

sub _register_source_field {
    my ( $out, $field, $optional ) = @_;
    return unless defined $field && length $field;
    $out->{$field} = 0 unless exists $out->{$field};
    $out->{$field} = 1 unless $optional;
    return;
}

1;
