package Convert::Pheno::HTTP::Service;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
use JSON::XS;
use MIME::Base64 qw(encode_base64);
use Path::Tiny qw(path);
use Scalar::Util qw(blessed looks_like_number);
use Text::CSV_XS;

use Convert::Pheno;
use Convert::Pheno::DB::Bundle qw(bundled_database_path);
use Convert::Pheno::IO::CSVHandler qw(get_headers);
use Convert::Pheno::OMOP::Definitions qw($omop_headers);
use Convert::Pheno::Operations qw(
  conversion_spec
  is_http_conversion
  is_public_conversion
  public_conversions
  registry_metadata
);

use Exporter 'import';
our @EXPORT_OK = qw(catalog execute execute_files health is_service_error);

my $JSON = JSON::XS->new->canonical->pretty;

sub health {
    return {
        ok   => JSON::XS::true,
        data => {
            status => 'ok',
            engine => 'perl',
            version => $Convert::Pheno::VERSION,
        },
    };
}

sub catalog {
    my $metadata = registry_metadata();
    my @conversions;

    for my $name ( @{ public_conversions() } ) {
        next unless is_http_conversion($name);
        my $spec = conversion_spec($name);
        my $source = $metadata->{formats}{ $spec->{source} } || {};
        my $target = $metadata->{formats}{ $spec->{target} } || {};
        my @required = _required_resources( $name, $metadata );
        my ( $available, $reason ) = _availability( \@required, $metadata );
        my @option_names = _applicable_options( $name, $spec, $metadata );
        my $input = $metadata->{input_definitions}{ $spec->{source} }
          || { transports => ['json'], files => [] };
        my @options = map {
            +{ name => $_, %{ $metadata->{option_definitions}{$_} || {} } }
        } @option_names;

        push @conversions, {
            id          => $name,
            label       => ( $source->{label} || $spec->{source} ) . ' to '
              . ( $target->{label} || $spec->{target} ),
            source      => {
                id         => $spec->{source},
                label      => $source->{label} || $spec->{source},
                kind       => $source->{kind} || 'json',
                inputShape => $source->{inputShape} || 'A JSON object',
            },
            target      => {
                id    => $spec->{target},
                label => $target->{label} || $spec->{target},
                kind  => $target->{kind} || 'json',
            },
            maturity    => $metadata->{http_profiles}{maturity} || 'experimental',
            options     => \@options,
            input       => {
                transports => [ @{ $input->{transports} || ['json'] } ],
                files      => [ map { _public_file_definition($_) }
                    @{ $input->{files} || [] } ],
            },
            entities    => {
                default   => [ @{ $spec->{entities}{default} } ],
                supported => [ @{ $spec->{entities}{supported} } ],
            },
            resources   => \@required,
            available   => $available ? JSON::XS::true : JSON::XS::false,
            ( $reason ? ( unavailableReason => $reason ) : () ),
        };
    }

    return {
        ok   => JSON::XS::true,
        data => \@conversions,
        meta => { count => scalar @conversions },
    };
}

sub execute {
    my ( $conversion, $request ) = @_;

    my ( $spec, $metadata, $output, $options ) =
      _validate_request( $conversion, $request, allow_input => 1 );
    my $input = $request->{input};
    _throw( 422, 'invalid_request', "Request field 'input' must be an object" )
      unless ref($input) eq 'HASH';
    _throw( 422, 'invalid_request', "Request field 'input.data' is required" )
      unless exists $input->{data};
    for my $key ( keys %{$input} ) {
        _throw( 422, 'invalid_request', "Unsupported key '$key' in 'input'" )
          unless $key eq 'data';
    }
    _reject_path_values( $input->{data}, 'input.data' );
    _throw( 422, 'invalid_request',
        "Request field 'input.data' must be a JSON object or array" )
      unless ref( $input->{data} ) eq 'HASH' || ref( $input->{data} ) eq 'ARRAY';

    return _execute_arguments(
        $conversion, $spec, $metadata,
        { method => $conversion, data => $input->{data}, %{$output}, %{$options} },
        {},
    );
}

sub execute_files {
    my ( $conversion, $request, $files, $arg ) = @_;
    $request ||= {};
    $arg     ||= {};
    my ( $spec, $metadata, $output, $options ) =
      _validate_request( $conversion, $request, allow_input => 0 );
    _throw( 422, 'invalid_request', 'Uploaded files must be grouped by role' )
      unless ref($files) eq 'HASH';

    my $definition = $metadata->{input_definitions}{ $spec->{source} } || {};
    _throw( 422, 'invalid_request', "Conversion <$conversion> does not accept file uploads" )
      unless grep { $_ eq 'multipart' } @{ $definition->{transports} || [] };

    my %known = map { $_->{name} => $_ } @{ $definition->{files} || [] };
    for my $role ( keys %{$files} ) {
        _throw( 422, 'invalid_request', "Unsupported upload role '$role' for conversion <$conversion>" )
          unless $known{$role};
        _throw( 422, 'invalid_request', "Upload role '$role' must contain an array" )
          unless ref( $files->{$role} ) eq 'ARRAY';
    }

    my ( %file_arguments, %display_paths );
    for my $role_definition ( @{ $definition->{files} || [] } ) {
        my $role    = $role_definition->{name};
        my $uploads = $files->{$role} || [];
        _throw( 422, 'invalid_request', "Required upload role '$role' is missing" )
          if $role_definition->{required} && !@{$uploads};
        my $maximum = $role_definition->{maximum} || ( $role_definition->{multiple} ? 128 : 1 );
        _throw( 422, 'invalid_request', "Upload role '$role' accepts at most $maximum file(s)" )
          if @{$uploads} > $maximum;

        for my $upload ( @{$uploads} ) {
            _throw( 422, 'invalid_request', "Upload role '$role' contains an invalid file" )
              unless ref($upload) eq 'HASH'
              && defined $upload->{path} && -f $upload->{path}
              && defined $upload->{filename} && !ref( $upload->{filename} );
            _throw( 422, 'invalid_request', "File <$upload->{filename}> is not accepted for upload role '$role'" )
              unless _accepted_filename( $upload->{filename}, $role_definition->{accept} );
            $display_paths{ $upload->{path} } = $upload->{filename};
        }

        next unless @{$uploads};
        my $argument = $role_definition->{argument};
        if ( $role_definition->{multiple} ) {
            $file_arguments{$argument} = [ map { $_->{path} } @{$uploads} ];
        }
        else {
            $file_arguments{$argument} = $uploads->[0]{path};
        }
    }

    my %normalized_options = %{$options};
    $normalized_options{sep} = delete $normalized_options{separator}
      if exists $normalized_options{separator};
    my $audit = delete $normalized_options{term_audit};
    if ( defined $audit && $audit ne 'none' ) {
        my $workspace = $arg->{workspace};
        _throw( 500, 'infrastructure_error', 'The upload workspace is unavailable' )
          unless defined $workspace && -d $workspace;
        $normalized_options{term_audit_file} = "$workspace/term-audit.$audit";
    }
    $normalized_options{schema_file} =
      catfile( $Convert::Pheno::share_dir, 'schema', 'mapping-v2.json' )
      if $file_arguments{mapping_file};

    return _execute_arguments(
        $conversion, $spec, $metadata,
        {
            method      => $conversion,
            in_textfile => 1,
            %file_arguments,
            %{$output},
            %normalized_options,
        },
        \%display_paths,
    );
}

sub _validate_request {
    my ( $conversion, $request, %arg ) = @_;
    _throw( 404, 'unknown_conversion', "Unknown conversion <$conversion>" )
      unless is_public_conversion($conversion) && is_http_conversion($conversion);
    _throw( 422, 'invalid_request', 'Request body must be a JSON object' )
      unless ref($request) eq 'HASH';

    my %root_allowed = map { $_ => 1 } qw(output options);
    $root_allowed{input} = 1 if $arg{allow_input};
    for my $key ( keys %{$request} ) {
        _throw( 422, 'invalid_request', "Unsupported request field '$key'" )
          unless $root_allowed{$key};
    }

    my $output  = exists $request->{output}  ? $request->{output}  : {};
    my $options = exists $request->{options} ? $request->{options} : {};
    _throw( 422, 'invalid_request', "Request field 'output' must be an object" )
      unless ref($output) eq 'HASH';
    _throw( 422, 'invalid_request', "Request field 'options' must be an object" )
      unless ref($options) eq 'HASH';

    my $spec     = conversion_spec($conversion);
    my $metadata = registry_metadata();
    my %allowed_output = $spec->{target} eq 'beacon'
      ? map { $_ => 1 } qw(entities derived_entity_overrides)
      : ();
    for my $key ( keys %{$output} ) {
        _throw( 422, 'invalid_request',
            "Option '$key' is not applicable to conversion <$conversion>" )
          unless $allowed_output{$key};
    }
    if ( $spec->{target} eq 'beacon' ) {
        if ( exists $output->{entities} ) {
            _throw( 422, 'invalid_request', "Output field 'entities' must be an array" )
              unless ref( $output->{entities} ) eq 'ARRAY';
            my %supported = map { $_ => 1 } @{ $spec->{entities}{supported} };
            for my $entity ( @{ $output->{entities} } ) {
                _throw( 422, 'invalid_request', "Unsupported BFF entity '$entity' for conversion <$conversion>" )
                  unless defined $entity && !ref($entity) && $supported{$entity};
            }
            _throw( 422, 'invalid_request', "At least one BFF entity must be requested" )
              unless @{ $output->{entities} };
        }
        if ( exists $output->{derived_entity_overrides} ) {
            _throw( 422, 'invalid_request',
                "Output field 'derived_entity_overrides' must be an object" )
              unless ref( $output->{derived_entity_overrides} ) eq 'HASH';
        }
    }

    my %allowed_options = map { $_ => 1 }
      _applicable_options( $conversion, $spec, $metadata );
    $allowed_options{test} = 1; # deterministic fixture mode; not advertised by the UI catalog
    for my $key ( keys %{$options} ) {
        _throw( 422, 'invalid_request',
            "Option '$key' is not applicable to conversion <$conversion>" )
          unless $allowed_options{$key};
        _validate_option( $key, $options->{$key}, $metadata );
    }

    my @required = _required_resources( $conversion, $metadata );
    my ( $available, $reason, $resource_paths ) =
      _availability( \@required, $metadata );
    _throw( 503, 'resource_unavailable', $reason ) unless $available;

    return ( $spec, $metadata, $output, $options );
}

sub _execute_arguments {
    my ( $conversion, $spec, $metadata, $arguments, $display_paths ) = @_;
    my @required = _required_resources( $conversion, $metadata );
    my ( $available, $reason, $resource_paths ) =
      _availability( \@required, $metadata );
    _throw( 503, 'resource_unavailable', $reason ) unless $available;

    if ( $resource_paths->{ohdsi} ) {
        $arguments->{ohdsi_db} = 1;
        $arguments->{path_to_ohdsi_db} = dirname( $resource_paths->{ohdsi} );
    }
    if ( $spec->{source} eq 'omop' ) {
        $arguments->{max_archive_uncompressed_bytes} =
          $ENV{CONVERT_PHENO_HTTP_MAX_ARCHIVE_BYTES} || 1024 * 1024 * 1024;
    }

    my @warnings;
    my ( $result, $artifacts, $audit_review );
    my $ok = eval {
        local $SIG{__WARN__} = sub {
            my ($warning) = @_;
            chomp $warning;
            push @warnings, $warning if length $warning;
        };
        my $convert = Convert::Pheno->new($arguments);
        if ( $spec->{target} eq 'beacon' ) {
            my $entities = $arguments->{entities} || $spec->{entities}{default};
            $arguments->{entities} = $entities;
            $convert = Convert::Pheno->new($arguments);
            my $bundle = $convert->_run_bundle_view;
            $artifacts = [ map {
                _json_artifact( $_, "$_.json", 'application/json', 'json',
                    $bundle->entities($_) )
            } @{$entities} ];
        }
        else {
            $result = $convert->$conversion();
            $artifacts = _artifacts_for_result( $conversion, $spec, $result );
        }
        $audit_review = $convert->term_audit_review;
        1;
    };
    unless ($ok) {
        my $message = $@ || 'Conversion failed';
        chomp $message;
        $message = _display_message( $message, $display_paths );
        _throw( 422, 'conversion_error', $message );
    }

    if ( $arguments->{term_audit_file} && -f $arguments->{term_audit_file} ) {
        push @{$artifacts}, _audit_artifact( $arguments->{term_audit_file} );
    }
    @warnings = map { _display_message( $_, $display_paths ) } @warnings;

    my %meta = ( conversion => $conversion );
    $meta{terminologyAudit} = _public_audit_review($audit_review)
      if $audit_review;

    return {
        ok        => JSON::XS::true,
        artifacts => $artifacts,
        warnings  => \@warnings,
        meta      => \%meta,
    };
}

sub _public_audit_review {
    my ($review) = @_;
    my $settings = $review->{settings} || {};
    return {
        totalDecisions => $review->{total_decisions},
        counts         => { %{ $review->{counts} || {} } },
        rows            => [ @{ $review->{rows} || [] } ],
        previewRows     => $review->{preview_rows},
        previewLimitPerAction => $review->{preview_limit_per_action},
        truncated => $review->{truncated} ? JSON::XS::true : JSON::XS::false,
        reportArtifactId => 'term-audit',
        settings => {
            configuredSearchMode   => $settings->{search},
            textSimilarityMethod   => $settings->{text_similarity_method},
            minTextSimilarityScore => $settings->{min_text_similarity_score},
            levenshteinWeight      => $settings->{levenshtein_weight},
        },
    };
}

sub _public_file_definition {
    my ($definition) = @_;
    return { map { $_ => $definition->{$_} }
        grep { exists $definition->{$_} }
        qw(name label description required multiple maximum accept) };
}

sub _accepted_filename {
    my ( $filename, $accepted ) = @_;
    return 1 unless ref($accepted) eq 'ARRAY' && @{$accepted};
    my $lower = lc $filename;
    return scalar grep {
        my $extension = lc $_;
        length($lower) >= length($extension)
          && substr( $lower, -length($extension) ) eq $extension
    } @{$accepted};
}

sub _display_message {
    my ( $message, $display_paths ) = @_;
    for my $path ( sort { length($b) <=> length($a) } keys %{ $display_paths || {} } ) {
        my $filename = $display_paths->{$path};
        $message =~ s/\Q$path\E/$filename/g;
    }
    return $message;
}

sub _artifacts_for_result {
    my ( $conversion, $spec, $result ) = @_;
    my $target = $spec->{target};

    if ( $target eq 'omop' ) {
        _throw( 422, 'conversion_error', 'OMOP conversion did not return table data' )
          unless ref($result) eq 'HASH';
        return [ map {
            my $table = $_;
            _csv_artifact(
                lc($table), "$table.csv", $omop_headers->{$table},
                $result->{$table}, ';'
            )
        } sort keys %{$result} ];
    }

    if ( $target eq 'csv' ) {
        my $base = $spec->{source} eq 'beacon' ? 'individuals' : 'pxf';
        return [ _csv_artifact( $base, "$base.csv", get_headers($result), $result, ';' ) ];
    }

    my ( $id, $filename, $media_type, $kind ) =
        $target eq 'pxf'    ? ( 'pxf', 'pxf.json', 'application/json', 'json' )
      : $target eq 'jsonf'  ? ( $spec->{source},
            ( $spec->{source} eq 'beacon' ? 'individuals' : 'pxf' ) . '.fold.json',
            'application/json', 'json' )
      : $target eq 'jsonld' ? ( $spec->{source},
            ( $spec->{source} eq 'beacon' ? 'individuals' : 'pxf' ) . '.jsonld',
            'application/ld+json', 'jsonld' )
      :                         ( 'result', 'result.json', 'application/json', 'json' );

    return [ _json_artifact( $id, $filename, $media_type, $kind, $result ) ];
}

sub _json_artifact {
    my ( $id, $filename, $media_type, $kind, $data ) = @_;
    return {
        id        => $id,
        filename  => $filename,
        mediaType => $media_type,
        kind      => $kind,
        encoding  => 'utf-8',
        content   => $JSON->encode($data),
    };
}

sub _csv_artifact {
    my ( $id, $filename, $headers, $rows, $separator ) = @_;
    $rows = [$rows] if ref($rows) eq 'HASH';
    $rows ||= [];
    my $content = q{};
    open my $fh, '>:encoding(UTF-8)', \$content
      or die "Cannot create in-memory CSV artifact: $!";
    my $csv = Text::CSV_XS->new(
        { binary => 1, eol => "\n", sep_char => $separator }
    ) or die 'Cannot initialize in-memory CSV writer';
    $csv->print( $fh, $headers );
    for my $row ( @{$rows} ) {
        $csv->print( $fh,
            [ map { exists $row->{$_} ? $row->{$_} : undef } @{$headers} ] );
    }
    close $fh;
    return {
        id        => $id,
        filename  => $filename,
        mediaType => 'text/csv; charset=utf-8',
        kind      => 'csv',
        encoding  => 'utf-8',
        content   => $content,
    };
}

sub _audit_artifact {
    my ($file) = @_;
    if ( $file =~ /\.xlsx\z/i ) {
        return {
            id        => 'term-audit',
            filename  => 'term-audit.xlsx',
            mediaType => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            kind      => 'xlsx',
            encoding  => 'base64',
            content   => encode_base64( path($file)->slurp_raw, q{} ),
        };
    }
    return {
        id        => 'term-audit',
        filename  => 'term-audit.tsv',
        mediaType => 'text/tab-separated-values; charset=utf-8',
        kind      => 'tsv',
        encoding  => 'utf-8',
        content   => path($file)->slurp_utf8,
    };
}

sub _applicable_options {
    my ( $name, $spec, $metadata ) = @_;
    my $profiles = $metadata->{http_profiles};
    my @names;
    push @names, @{ $profiles->{common_options} || [] }
      unless $spec->{operation} eq 'direct';
    push @names, @{ $profiles->{terminology_options} || [] }
      if $spec->{target} eq 'omop'
      || grep { $_ eq $spec->{source} } @{ $profiles->{terminology_sources} || [] };
    push @names, 'term_audit'
      if $spec->{target} eq 'omop'
      || grep { $_ eq $spec->{source} } @{ $profiles->{terminology_sources} || [] };
    push @names, 'separator'
      if grep { $_ eq $spec->{source} } @{ $profiles->{separator_sources} || [] };
    push @names, @{ $profiles->{omop_input_options} || [] }
      if $spec->{source} eq 'omop';
    push @names, @{ $profiles->{pxf_output_options} || [] }
      if $spec->{target} eq 'pxf';
    my %seen;
    return grep { !$seen{$_}++ } @names;
}

sub _validate_option {
    my ( $name, $value, $metadata ) = @_;
    return if $name eq 'test' && blessed($value) && $value->isa('JSON::PP::Boolean');
    my $definition = $metadata->{option_definitions}{$name} || {};
    my $kind = $definition->{kind} || q{};
    my $valid =
        $kind eq 'boolean' ? ( blessed($value) && $value->isa('JSON::PP::Boolean') )
      : $kind eq 'number'  ? ( !ref($value) && defined($value) && looks_like_number($value) )
      : $kind eq 'integer' ? ( !ref($value) && defined($value) && $value =~ /\A\d+\z/ )
      : $kind eq 'string'  ? ( !ref($value) && defined($value) )
      : $kind eq 'select'  ? ( !ref($value) && defined($value)
            && grep { $_ eq $value } @{ $definition->{values} || [] } )
      : 1;
    _throw( 422, 'invalid_request', "Invalid value for option '$name'" )
      unless $valid;

    if ( ( $kind eq 'number' || $kind eq 'integer' ) && defined $value ) {
        _throw( 422, 'invalid_request', "Option '$name' is below its minimum" )
          if defined $definition->{minimum} && $value < $definition->{minimum};
        _throw( 422, 'invalid_request', "Option '$name' is above its maximum" )
          if defined $definition->{maximum} && $value > $definition->{maximum};
    }
}

sub _required_resources {
    my ( $name, $metadata ) = @_;
    my $spec = conversion_spec($name);
    return ('ohdsi') if $spec && $spec->{target} eq 'omop';
    return ();
}

sub _availability {
    my ( $required, $metadata ) = @_;
    my %paths;
    for my $resource ( @{$required} ) {
        next unless $resource eq 'ohdsi';
        my $override = $ENV{CONVERT_PHENO_OHDSI_DB_DIR};
        my $path = defined $override && length $override
          ? "$override/ohdsi.db"
          : eval { bundled_database_path( $Convert::Pheno::share_dir, 'ohdsi' ) };
        unless ( defined $path && -f $path ) {
            my $description = $metadata->{resources}{$resource}{description}
              || 'A required runtime resource is missing.';
            return ( 0, $description, \%paths );
        }
        $paths{$resource} = $path;
    }
    return ( 1, undef, \%paths );
}

sub _reject_path_values {
    my ( $value, $location ) = @_;
    return unless !ref($value);
    return unless defined $value;
    # Input data may legitimately contain slashes and identifiers. Only reject
    # a scalar input that is itself shaped like a host path; structured JSON is safe.
    if ( $value =~ m{\A(?:/|[A-Za-z]:[\\/]|\.\.?[\\/]|~[\\/])} ) {
        _throw( 422, 'invalid_request',
            "Filesystem paths are not accepted in $location" );
    }
}

sub _throw {
    my ( $status, $code, $message ) = @_;
    die bless {
        status  => $status,
        code    => $code,
        message => $message,
    }, 'Convert::Pheno::HTTP::Service::Error';
}

sub is_service_error {
    my ($error) = @_;
    return ref($error) && eval { $error->isa('Convert::Pheno::HTTP::Service::Error') };
}

package Convert::Pheno::HTTP::Service::Error;

use overload q{""} => sub { return $_[0]->{message} }, fallback => 1;

sub status  { return $_[0]->{status} }
sub code    { return $_[0]->{code} }
sub message { return $_[0]->{message} }

1;
