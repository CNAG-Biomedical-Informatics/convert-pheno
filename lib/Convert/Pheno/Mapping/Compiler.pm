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
    my $record_profile = $arg{record_profile} // $profile;
    die "A record profile is required to compile the mapping\n"
      unless defined $record_profile && length $record_profile;

    _validate_target($mapping);
    _validate_source_profile( $mapping, $record_profile );

    # Mapping files are intentionally concise. Compile their author-facing
    # rules into the explicit representation consumed by the mapper so that
    # execution code never needs to support shorthand or inheritance.
    my $compiled = _compile_authoring_mapping($mapping);
    $compiled->{_compiled} = {
        sourceProfile => $profile,
        recordProfile => $record_profile,
    };

    if ( exists $arg{headers} ) {
        _validate_source_fields( $compiled, $arg{headers}, $profile );
    }

    return $compiled;
}

sub _compile_authoring_mapping {
    my ($mapping) = @_;
    my $compiled = dclone($mapping);
    my $individuals = $compiled->{beacon}{individuals};

    $individuals->{id} = _compile_id_mapping( $individuals->{id} );

    for my $property (qw(sex ethnicity geographicOrigin)) {
        next unless exists $individuals->{$property};
        $individuals->{$property} = _compile_scalar_term(
            $individuals->{$property},
            "beacon.individuals.$property",
        );
    }

    if ( exists $individuals->{karyotypicSex} ) {
        $individuals->{karyotypicSex} = _compile_scalar_value(
            $individuals->{karyotypicSex},
            'beacon.individuals.karyotypicSex',
        );
    }

    $individuals->{info} = _compile_info_mapping( $individuals->{info} )
      if exists $individuals->{info};

    my %collection_kind = (
        diseases                  => 'disease',
        exposures                 => 'exposure',
        interventionsOrProcedures => 'procedure',
        measures                  => 'measure',
        phenotypicFeatures        => 'phenotypicFeature',
        treatments                => 'treatment',
    );
    for my $property ( keys %collection_kind ) {
        next unless exists $individuals->{$property};
        $individuals->{$property} = _compile_collection(
            $individuals->{$property},
            $collection_kind{$property},
            "beacon.individuals.$property",
        );
    }

    if ( exists $compiled->{beacon}{biosamples} ) {
        $compiled->{beacon}{biosamples} = {
            mappings => _compile_collection(
                $compiled->{beacon}{biosamples},
                'biosample',
                'beacon.biosamples',
            ),
        };
    }

    return $compiled;
}

sub _compile_id_mapping {
    my ($config) = @_;
    die "<beacon.individuals.id> must be an object\n"
      unless ref($config) eq 'HASH';

    my $compiled = {
        source => {
            fields     => dclone( $config->{sourceFields} ),
            primaryKey => $config->{primaryKey},
        },
    };
    $compiled->{separator} = $config->{separator}
      if exists $config->{separator};
    $compiled->{missingValue} = $config->{missingValue}
      if exists $config->{missingValue};
    return $compiled;
}

sub _compile_scalar_term {
    my ( $config, $path ) = @_;
    my ( $source, $target ) = _split_rule( $config, $path );
    return {
        source => $source,
        target => _normalize_term_target($target),
    };
}

sub _compile_scalar_value {
    my ( $config, $path ) = @_;
    my $source = _source_selector( $config, $path );
    return {
        source => $source,
        target => dclone( $config->{value} ),
    };
}

sub _compile_info_mapping {
    my ($config) = @_;
    my $compiled = {
        source => { fields => dclone( $config->{sourceFields} ) },
    };
    $compiled->{target}{ageRange} = dclone( $config->{ageRange} )
      if exists $config->{ageRange};
    return $compiled;
}

sub _compile_collection {
    my ( $config, $kind, $path ) = @_;
    die "<$path> must be an object with a <rules> array\n"
      unless ref($config) eq 'HASH' && ref( $config->{rules} ) eq 'ARRAY';

    my $defaults = $config->{defaults} || {};
    my @compiled;
    for my $index ( 0 .. $#{ $config->{rules} } ) {
        my $rule = $config->{rules}[$index];
        my $rule_path = "$path.rules[$index]";
        my ( $source, $target ) = _split_rule( $rule, $rule_path );
        $target = _deep_merge( $defaults, $target );
        $target = _normalize_target( $target, $kind, $rule_path );
        push @compiled, { source => $source, target => $target };
    }
    return \@compiled;
}

sub _split_rule {
    my ( $rule, $path ) = @_;
    my $source = _source_selector( $rule, $path );
    my %target = map { $_ => _clone( $rule->{$_} ) }
      grep { $_ ne 'sourceField' && $_ ne 'optional' && $_ ne 'when' }
      keys %{$rule};
    return ( $source, \%target );
}

sub _source_selector {
    my ( $rule, $path ) = @_;
    die "<$path> must be an object\n" unless ref($rule) eq 'HASH';
    die "<$path.sourceField> is required\n"
      unless defined $rule->{sourceField} && length $rule->{sourceField};

    my $source = { field => $rule->{sourceField} };
    $source->{optional} = $rule->{optional} if exists $rule->{optional};
    $source->{when} = dclone( $rule->{when} ) if exists $rule->{when};
    return $source;
}

sub _deep_merge {
    my ( $defaults, $overrides ) = @_;
    my $merged = dclone($defaults);

    for my $key ( keys %{$overrides} ) {
        if ( !defined $overrides->{$key} ) {
            delete $merged->{$key};
        }
        elsif (
            ref( $merged->{$key} ) eq 'HASH'
            && ref( $overrides->{$key} ) eq 'HASH'
          )
        {
            $merged->{$key} = _deep_merge(
                $merged->{$key},
                $overrides->{$key},
            );
        }
        else {
            $merged->{$key} = _clone( $overrides->{$key} );
        }
    }
    return $merged;
}

sub _normalize_target {
    my ( $target, $kind, $path ) = @_;

    my %term_paths = (
        disease => [ [qw(diseaseCode)] ],
        exposure => [ [qw(exposureCode)], [qw(unit)] ],
        procedure => [ [qw(procedureCode)], [qw(bodySite)] ],
        measure => [
            [qw(assayCode)],
            [qw(measurementValue quantity unit)],
            [qw(procedure procedureCode)],
        ],
        phenotypicFeature => [ [qw(featureType)] ],
        treatment => [
            [qw(treatmentCode)],
            [qw(routeOfAdministration)],
            [qw(cumulativeDose unit)],
            [qw(doseIntervals quantity unit)],
        ],
        biosample => [
            [qw(biosampleStatus)],
            [qw(sampleOriginType)],
            [qw(sampleOriginDetail)],
            [qw(obtentionProcedure procedureCode)],
        ],
    );

    _normalize_term_at( $target, @{$_} ) for @{ $term_paths{$kind} || [] };

    if ( $kind eq 'biosample' && exists $target->{measurements} ) {
        $target->{measurements} = _compile_collection(
            $target->{measurements},
            'measure',
            "$path.measurements",
        );
    }

    my %required_paths = (
        disease           => [ [qw(diseaseCode)] ],
        exposure          => [ [qw(exposureCode)], [qw(unit)] ],
        procedure         => [ [qw(procedureCode)] ],
        measure           => [ [qw(assayCode)], [qw(measurementValue quantity unit)] ],
        phenotypicFeature => [ [qw(featureType)] ],
        treatment         => [ [qw(treatmentCode)] ],
        biosample         => [ [qw(id)], [qw(biosampleStatus)], [qw(sampleOriginType)] ],
    );
    _require_target_path( $target, $path, @{$_} )
      for @{ $required_paths{$kind} || [] };

    if ( $kind eq 'measure' && exists $target->{procedure} ) {
        _require_target_path( $target, $path, qw(procedure procedureCode) );
    }
    if ( $kind eq 'treatment' && exists $target->{cumulativeDose} ) {
        _require_target_path( $target, $path, qw(cumulativeDose unit) );
    }
    if ( $kind eq 'treatment' && exists $target->{doseIntervals} ) {
        _require_target_path(
            $target,
            $path,
            qw(doseIntervals quantity unit),
        );
    }
    if ( $kind eq 'biosample' && exists $target->{obtentionProcedure} ) {
        _require_target_path(
            $target,
            $path,
            qw(obtentionProcedure procedureCode),
        );
    }

    return $target;
}

sub _normalize_term_at {
    my ( $target, @path ) = @_;
    my $key = pop @path;
    my $node = $target;
    for my $part (@path) {
        return unless ref($node) eq 'HASH' && exists $node->{$part};
        $node = $node->{$part};
    }
    return unless ref($node) eq 'HASH' && exists $node->{$key};
    $node->{$key} = _normalize_term_target( $node->{$key} );
    return;
}

sub _normalize_term_target {
    my ($target) = @_;
    my $normalized = dclone($target);
    if ( exists $normalized->{query} && !ref( $normalized->{query} ) ) {
        $normalized->{query} = { literal => $normalized->{query} };
    }
    return $normalized;
}

sub _require_target_path {
    my ( $target, $rule_path, @path ) = @_;
    my $node = $target;
    for my $part (@path) {
        die "<$rule_path> must define target <" . join( '.', @path ) . ">\n"
          unless ref($node) eq 'HASH' && exists $node->{$part};
        $node = $node->{$part};
    }
    return 1;
}

sub _clone {
    my ($value) = @_;
    return ref($value) ? dclone($value) : $value;
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
    my ( $mapping, $expected_profile ) = @_;
    my $source = $mapping->{source};
    my $profile = ref($source) eq 'HASH' ? $source->{profile} : undef;
    die "The mapping must declare one <source.profile> value.\n"
      unless defined $profile && !ref($profile) && length $profile;

    return 1 if $profile eq $expected_profile;

    die "Mapping source profile mismatch: normalized route profile <$expected_profile> does not match <source.profile: $profile>.\n";
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
