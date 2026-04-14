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
use Convert::Pheno::Model::Bundle;
use Exporter 'import';

our @EXPORT_OK = qw(resolve_operation run_operation);

my %DIRECT_OPERATIONS = (
    csv2pxf    => \&Convert::Pheno::do_csv2pxf,
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

    return _bundle_operation(
        name             => 'redcap2bff',
        source_format    => 'redcap',
        target_format    => 'beacon',
        default_entities => ['individuals'],
        primary_entity   => 'individuals',
        run              => sub {
            my ( $convert, $input, $context ) = @_;
            return _wrap_individual_in_bundle(
                $context,
                Convert::Pheno::do_redcap2bff( $convert, $input )
            );
        },
    ) if $self->{method} eq 'redcap2bff';

    return _bundle_operation(
        name             => 'cdisc2bff',
        source_format    => 'cdisc',
        target_format    => 'beacon',
        default_entities => ['individuals'],
        primary_entity   => 'individuals',
        run              => sub {
            my ( $convert, $input, $context ) = @_;
            return _wrap_individual_in_bundle(
                $context,
                Convert::Pheno::do_cdisc2bff( $convert, $input )
            );
        },
    ) if $self->{method} eq 'cdisc2bff';

    return _bundle_operation(
        name             => 'csv2bff',
        source_format    => 'csv',
        target_format    => 'beacon',
        default_entities => ['individuals'],
        primary_entity   => 'individuals',
        run              => sub {
            my ( $convert, $input, $context ) = @_;
            return _wrap_individual_in_bundle(
                $context,
                Convert::Pheno::do_csv2bff( $convert, $input )
            );
        },
    ) if $self->{method} eq 'csv2bff';

    return _bundle_operation(
        name             => 'omop2bff',
        source_format    => 'omop',
        target_format    => 'beacon',
        default_entities => ['individuals'],
        primary_entity   => 'individuals',
        run              => sub {
            my ( $convert, $input, $context ) = @_;
            return Convert::Pheno::OMOP::ToBFF::run_omop_to_bundle(
                $convert, $input, $context
            );
        },
    ) if $self->{method} eq 'omop2bff';

    return _bundle_operation(
        name             => 'pxf2bff',
        source_format    => 'pxf',
        target_format    => 'beacon',
        default_entities => ['individuals'],
        primary_entity   => 'individuals',
        run              => sub {
            my ( $convert, $input, $context ) = @_;
            return Convert::Pheno::PXF::ToBFF::run_pxf_to_bundle(
                $convert, $input, $context
            );
        },
    ) if $self->{method} eq 'pxf2bff';

    return _direct_operation(
        name => $self->{method},
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

    Convert::Pheno::open_connections_SQLite($self)
      if $self->{method} ne 'bff2pxf';

    my $is_array = ref($input) eq 'ARRAY';
    my @items    = $is_array ? @{$input} : ($input);

    if ( $view eq 'primary' && $is_array ) {
        $out_data = [];
    }

    my $total = 0;
    for ( my $i = 0; $i < @items; $i++ ) {
        my $count = $i + 1;
        my $item  = $items[$i];

        $self->{current_row} = $count;

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
        @{$input} = ();
        if ( $self->{verbose} && $self->{method} eq 'omop2bff' && $view eq 'primary' ) {
            say "==============\nIndividuals total:     $total\n";
        }
    }

    synthesize_bundle_entities( $self, $out_data, $context )
      if $view eq 'bundle';

    Convert::Pheno::close_connections_SQLite($self)
      unless $self->{method} eq 'bff2pxf';
    Convert::Pheno::finalize_search_audit($self);
    delete $self->{current_row};

    if ($stream) {
        Convert::Pheno::finalize_stream_out($stream);
        return 1;
    }

    return $out_data if $view eq 'bundle';
    return $is_array ? $out_data : $out_data;
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
    return {
        type             => 'bundle',
        name             => $arg{name},
        source_format    => $arg{source_format},
        target_format    => $arg{target_format},
        default_entities => $arg{default_entities},
        primary_entity   => $arg{primary_entity},
        run              => $arg{run},
    };
}

sub _direct_operation {
    my (%arg) = @_;
    return {
        type => 'direct',
        name => $arg{name},
        run  => $arg{run},
    };
}

sub _wrap_individual_in_bundle {
    my ( $context, $individual ) = @_;

    my $bundle = Convert::Pheno::Model::Bundle->new(
        {
            context  => $context,
            entities => $context->entities,
        }
    );

    $bundle->add_entity( individuals => $individual );

    return $bundle;
}

1;
