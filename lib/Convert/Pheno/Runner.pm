package Convert::Pheno::Runner;

use strict;
use warnings;
use autodie;
use feature qw(say);

use JSON::XS;
use Convert::Pheno::BFF::DerivedEntities qw(
  execution_entities
  synthesize_bundle_entities
);
use Convert::Pheno::Context;
use Convert::Pheno::ConversionRequest;
use Convert::Pheno::CDISC::SDTM::ToBFF qw(run_sdtm_to_bundle);
use Convert::Pheno::ExecutionContext;
use Convert::Pheno::Model::Bundle;
use Convert::Pheno::Operations qw(conversion_spec);
use Convert::Pheno::Tabular::ToBFF qw(run_tabular_to_bundle);
use Exporter 'import';

our @EXPORT_OK = qw(resolve_operation run_operation);

my %DIRECT_OPERATIONS = (
    bff2pxf    => \&Convert::Pheno::do_bff2pxf,
    bff2csv    => \&Convert::Pheno::do_bff2csv,
    bff2jsonf  => \&Convert::Pheno::do_bff2csv,
    bff2jsonld => \&Convert::Pheno::do_bff2jsonld,
    bff2omop   => \&Convert::Pheno::do_bff2omop,
    pxf2csv    => \&Convert::Pheno::do_pxf2csv,
    pxf2jsonf  => \&Convert::Pheno::do_pxf2csv,
    pxf2jsonld => \&Convert::Pheno::do_pxf2jsonld,
);

sub resolve_operation {
    my ($self) = @_;
    my $spec = conversion_spec( $self->{method} )
      or die "Unsupported method <$self->{method}> in runner\n";

    return _bundle_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input, $context ) = @_;
            return run_tabular_to_bundle( $convert, $input, $context );
        },
    ) if $self->{method} eq 'redcap2bff';

    return _bundle_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input, $context ) = @_;
            return run_tabular_to_bundle( $convert, $input, $context );
        },
    ) if $self->{method} eq 'cdiscodm2bff';

    return _bundle_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input, $context ) = @_;
            return run_sdtm_to_bundle( $convert, $input, $context );
        },
    ) if $self->{method} eq 'datasetjson2bff';

    return _bundle_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input, $context ) = @_;
            return run_tabular_to_bundle( $convert, $input, $context );
        },
    ) if $self->{method} eq 'csv2bff';

    return _bundle_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input, $context ) = @_;
            return Convert::Pheno::OMOP::ToBFF::run_omop_to_bundle(
                $convert, $input, $context
            );
        },
    ) if $self->{method} eq 'omop2bff';

    return _bundle_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input, $context ) = @_;
            return Convert::Pheno::PXF::ToBFF::run_pxf_to_bundle(
                $convert, $input, $context
            );
        },
    ) if $self->{method} eq 'pxf2bff';

    return _bundle_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input, $context ) = @_;
            return Convert::Pheno::OpenEHR::ToBFF::run_openehr_to_bundle(
                $convert, $input, $context
            );
        },
    ) if $self->{method} eq 'openehr2bff';

    return _direct_operation(
        spec => $spec,
        run  => sub {
            my ( $convert, $input ) = @_;
            return $DIRECT_OPERATIONS{ $convert->{method} }->( $convert, $input );
        },
    ) if exists $DIRECT_OPERATIONS{ $self->{method} };

    die "Unsupported method <$self->{method}> in runner\n";
}

sub run_operation {
    my ( $self, $input, %arg ) = @_;

    my $operation = $arg{operation} || resolve_operation($self);
    my $view      = $arg{view} || 'primary';
    my $operation_name = $operation->{name} || $self->{method};
    my $request = $arg{request}
      || Convert::Pheno::ConversionRequest->from_converter($self);
    my $execution = $arg{execution_context}
      || Convert::Pheno::ExecutionContext->new(
        {
            request => $request,
            stages  => [$operation_name],
        }
      );
    my ($execution_stage) = $execution->begin_next_stage;
    die "Execution stage <$execution_stage> does not match operation <$operation_name>\n"
      unless $execution_stage eq $operation_name;

    die "Unsupported runner view <$view>\n"
      unless $view eq 'primary' || $view eq 'bundle';

    if ( $view eq 'bundle' && $operation->{type} ne 'bundle' ) {
        die "Method <$self->{method}> does not support bundle dispatch\n";
    }

    my $context = _resolve_context( $self, $operation );
    my $stream  = $view eq 'primary'
      ? Convert::Pheno::_dispatcher_open_stream_out($self)
      : undef;
    my $json = $stream ? JSON::XS->new->canonical->pretty : undef;

    my $out_data =
      $view eq 'bundle'
      ? Convert::Pheno::Model::Bundle->new(
        {
            context  => $context,
            entities => $context->entities,
        }
      )
      : undef;

    my $connections_open = 0;
    my ( $ok, $error );

    $ok = eval {
        if ( $operation->{requires_sqlite} ) {
            Convert::Pheno::open_connections_SQLite($self);
            $connections_open = 1;
            $execution->set_resource( sqlite_open => 1 );
        }

        $out_data = _process_operation_items(
            $self,
            $input,
            $operation,
            $context,
            $view,
            $stream,
            $json,
            $out_data,
            $execution,
        );
        1;
    };
    $error = $@ unless $ok;

    my @cleanup_errors;
    _run_cleanup(
        \@cleanup_errors,
        'closing SQLite connections',
        sub { Convert::Pheno::close_connections_SQLite($self) },
      )
      if $connections_open;
    $execution->set_resource( sqlite_open => 0 ) if $connections_open;
    _run_cleanup(
        \@cleanup_errors,
        'closing the search audit',
        sub { Convert::Pheno::finalize_search_audit($self) },
    );
    delete $self->{current_row};
    $execution->clear_current_row;

    if ($stream) {
        if ( $ok && !@cleanup_errors ) {
            _run_cleanup(
                \@cleanup_errors,
                'finalizing streamed output',
                sub { Convert::Pheno::finalize_stream_out($stream) },
            );
        }
        else {
            _run_cleanup(
                \@cleanup_errors,
                'closing failed streamed output',
                sub {
                    close $stream->{fh}
                      if $stream->{fh} && defined fileno( $stream->{fh} );
                    return 1;
                },
            );
        }
    }

    _throw_run_failure( $error, \@cleanup_errors )
      if !$ok || @cleanup_errors;

    my $result = $stream ? 1 : $out_data;
    $execution->complete_stage($result);
    return $result;
}

sub _process_operation_items {
    my (
        $self,      $input,   $operation, $context,
        $view,      $stream,  $json,      $out_data, $execution,
    ) = @_;

    my $is_array = ref($input) eq 'ARRAY';
    my $item_count = $is_array ? scalar @{$input} : 1;

    if ( $view eq 'primary' && $is_array ) {
        $out_data = [];
    }

    my $total = 0;
    for ( my $i = 0; $i < $item_count; $i++ ) {
        my $count = $i + 1;
        my $item  = $is_array ? $input->[$i] : $input;

        $self->{current_row} = $count;
        $execution->set_current_row($count);

        my $raw = _execute_operation_raw( $self, $operation, $item, $context );
        next unless defined $raw;

        if ( $view eq 'bundle' ) {
            _merge_bundle(
                $out_data,
                $raw,
                $context->entities,
            );
            next;
        }

        my $result = _primary_result( $operation, $raw );
        next unless defined $result;

        $total++;

        if ($stream) {
            print { $stream->{fh} } ",\n" unless $stream->{first};
            Convert::Pheno::_transform_item(
                $self,
                $result,
                $stream->{fh},
                1,
                $json
            );
            $stream->{first} = 0;
        }
        elsif ($is_array) {
            push @{$out_data}, $result;
        }
        else {
            $out_data = $result;
        }

        last if ( $self->{method} eq 'omop2bff'
               && $self->{max_lines_sql}
               && $total >= $self->{max_lines_sql} );
    }

    if ($is_array) {
        if ( $self->{verbose} && $self->{method} eq 'omop2bff' && $view eq 'primary' ) {
            say "==============\nIndividuals total:     $total\n";
        }
    }

    synthesize_bundle_entities( $self, $out_data, $context )
      if $view eq 'bundle';

    return $out_data;
}

sub _run_cleanup {
    my ( $errors, $label, $code ) = @_;
    my $ok = eval {
        $code->();
        1;
    };
    return 1 if $ok;

    my $error = $@ || 'unknown cleanup error';
    chomp $error;
    push @{$errors}, "$label: $error";
    return;
}

sub _throw_run_failure {
    my ( $error, $cleanup_errors ) = @_;
    my $message = defined $error ? $error : q{};
    $message .= "\n" if length($message) && $message !~ /\n\z/;

    if ( @{$cleanup_errors} ) {
        $message .= "Conversion cleanup failed:\n" unless length $message;
        $message .= join q{}, map { "  $_\n" } @{$cleanup_errors};
    }

    die $message;
}

sub _resolve_context {
    my ( $self, $operation ) = @_;

    return $self->{conversion_context}
      if $operation->{type} eq 'bundle'
      && $self->{conversion_context};

    return Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => $operation->{source_format},
            target_format => $operation->{target_format},
            entities      => execution_entities(
                $self->{entities} || $operation->{default_entities}
            ),
        }
    ) if $operation->{type} eq 'bundle';

    return undef;
}

sub _execute_operation_raw {
    my ( $self, $operation, $input, $context ) = @_;
    return $operation->{run}->( $self, $input, $context );
}

sub _primary_result {
    my ( $operation, $result ) = @_;
    return $result unless $operation->{type} eq 'bundle';
    return $result->primary_entity( $operation->{primary_entity} );
}

sub _merge_bundle {
    my ( $aggregate, $item_bundle, $entities ) = @_;
    for my $entity ( @{$entities} ) {
        for my $entry ( @{ $item_bundle->entities($entity) } ) {
            $aggregate->add_entity( $entity => $entry );
        }
    }
    return 1;
}

sub _bundle_operation {
    my (%arg) = @_;
    my $spec = $arg{spec};
    die "Conversion <$spec->{name}> is not a bundle operation\n"
      unless $spec->{operation} eq 'bundle';

    return {
        type             => 'bundle',
        name             => $spec->{name},
        source_format    => $spec->{source},
        target_format    => $spec->{target},
        requires_sqlite  => $spec->{resources}{sqlite} ? 1 : 0,
        default_entities => $spec->{entities}{default},
        primary_entity   => $spec->{entities}{primary},
        run              => $arg{run},
    };
}

sub _direct_operation {
    my (%arg) = @_;
    my $spec = $arg{spec};
    die "Conversion <$spec->{name}> is not a direct operation\n"
      unless $spec->{operation} eq 'direct';

    return {
        type            => 'direct',
        name            => $spec->{name},
        requires_sqlite => $spec->{resources}{sqlite} ? 1 : 0,
        run             => $arg{run},
    };
}

1;
