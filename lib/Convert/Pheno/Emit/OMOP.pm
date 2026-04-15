package Convert::Pheno::Emit::OMOP;

use strict;
use warnings;
use autodie;
use feature qw(say);

use Exporter 'import';
use JSON::XS;

our @EXPORT_OK = qw(
  dispatcher_open_stream_out
  transform_item
  finalize_stream_out
  omop_dispatcher
  omop_stream_targets_open
  omop_stream_targets_write
  omop_stream_targets_finalize
  omop_streams_multiple_entities
);

sub dispatcher_open_stream_out {
    my ($self) = @_;
    return unless ( $self->{method} eq 'omop2bff' && $self->{omop_cli} );

    my $fh = Convert::Pheno::open_filehandle( $self->{out_file}, 'a' );
    say $fh "[";
    return { fh => $fh, first => 1 };
}

sub transform_item {
    my ( $self, $method_result, $fh_out, $is_last_item, $json ) = @_;

    $json //= JSON::XS->new->canonical->pretty;

    my $out;

    if ( $self->{method_ori} && $self->{method_ori} eq 'omop2pxf' ) {
        my $pxf = Convert::Pheno::do_bff2pxf( $self, $method_result );
        $out = $json->encode($pxf);
    }
    else {
        $out = $json->encode($method_result);
    }

    chomp $out;
    print $fh_out $out;

    return 1;
}

sub finalize_stream_out {
    my ($stream) = @_;
    say { $stream->{fh} } "\n]";
    close $stream->{fh};
    return 1;
}

sub omop_dispatcher {
    my ( $self, $method_result, $json ) = @_;

    $json //= JSON::XS->new->canonical->pretty;

    my $out;

    if ( $self->{method_ori} ne 'omop2pxf' ) {
        $out = $json->encode($method_result);
    }
    else {
        my $pxf = Convert::Pheno::do_bff2pxf( $self, $method_result );
        $out = $json->encode($pxf);
    }
    chomp $out;
    return \$out;
}

sub omop_streams_multiple_entities {
    my ($self) = @_;
    my @entities = @{ $self->{entities} || ['individuals'] };
    return @entities != 1 || $entities[0] ne 'individuals';
}

sub omop_stream_targets_open {
    my ($self) = @_;
    return $self->{_omop_stream_targets}
      if exists $self->{_omop_stream_targets};

    my @entities = @{ $self->{entities} || ['individuals'] };
    my %targets;

    for my $entity (@entities) {
        my $path = _stream_output_path( $self, $entity );
        my $fh   = Convert::Pheno::open_filehandle( $path, 'w' );
        $targets{$entity} = {
            fh   => $fh,
            path => $path,
        };
    }

    $self->{_omop_stream_targets} = \%targets;
    return $self->{_omop_stream_targets};
}

sub omop_stream_targets_write {
    my ( $self, $result ) = @_;
    my $targets = omop_stream_targets_open($self);
    my $json    = JSON::XS->new->canonical;

    if ( ref($result) && $result->can('entities') ) {
        for my $entity ( keys %{$targets} ) {
            for my $entry ( @{ $result->entities($entity) } ) {
                print { $targets->{$entity}{fh} } $json->encode($entry), "\n";
            }
        }
        return 1;
    }

    return 1 unless defined $result;
    return 1 unless exists $targets->{individuals};

    print { $targets->{individuals}{fh} } $json->encode($result), "\n";
    return 1;
}

sub omop_stream_targets_finalize {
    my ($self) = @_;
    return 1 unless exists $self->{_omop_stream_targets};

    for my $entity ( keys %{ $self->{_omop_stream_targets} } ) {
        close $self->{_omop_stream_targets}{$entity}{fh};
    }

    delete $self->{_omop_stream_targets};
    return 1;
}

sub _stream_output_path {
    my ( $self, $entity ) = @_;

    if ( !omop_streams_multiple_entities($self)
        && $entity eq 'individuals'
        && defined $self->{out_file}
        && length $self->{out_file} )
    {
        return $self->{out_file};
    }

    if ( exists $self->{entity_output_files}
        && exists $self->{entity_output_files}{$entity} )
    {
        return $self->{entity_output_files}{$entity};
    }

    return $self->{out_dir} . q{/} . $entity . '.json';
}

1;
