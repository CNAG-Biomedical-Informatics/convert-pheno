package Convert::Pheno::Emit::OMOP;

use strict;
use warnings;
use autodie;
use feature qw(say);

use Exporter 'import';
use JSON::XS;
use Convert::Pheno::IO::Atomic qw(
  commit_staged_path
  create_staged_path
  discard_staged_path
);

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

    my $ok = eval {
        for my $entity (@entities) {
            my $path   = _stream_output_path( $self, $entity );
            my $staged = create_staged_path($path);
            my $fh     = Convert::Pheno::open_filehandle( $staged, 'w' );
            $targets{$entity} = {
                fh     => $fh,
                path   => $path,
                staged => $staged,
            };
        }
        1;
    };

    unless ($ok) {
        my $error = $@;
        for my $target ( values %targets ) {
            eval { close $target->{fh} if defined fileno( $target->{fh} ) };
            eval { discard_staged_path( $target->{staged} ) };
        }
        die $error;
    }

    $self->{_omop_stream_targets} = \%targets;
    $self->{_omop_stream_seen}    = {};
    return $self->{_omop_stream_targets};
}

sub omop_stream_targets_write {
    my ( $self, $result ) = @_;
    my $targets = omop_stream_targets_open($self);
    my $json    = JSON::XS->new->canonical;
    my $seen    = $self->{_omop_stream_seen} ||= {};

    if ( ref($result) && $result->can('entities') ) {
        for my $entity ( keys %{$targets} ) {
            for my $entry ( @{ $result->entities($entity) } ) {
                next if _stream_entity_entry_seen( $seen, $entity, $entry );
                print { $targets->{$entity}{fh} } $json->encode($entry), "\n";
            }
        }
        return 1;
    }

    return 1 unless defined $result;
    return 1 unless exists $targets->{individuals};
    return 1 if _stream_entity_entry_seen( $seen, 'individuals', $result );

    print { $targets->{individuals}{fh} } $json->encode($result), "\n";
    return 1;
}

sub omop_stream_targets_finalize {
    my ( $self, $commit ) = @_;
    $commit = 1 unless defined $commit;
    return 1 unless exists $self->{_omop_stream_targets};

    my @errors;
    for my $entity ( keys %{ $self->{_omop_stream_targets} } ) {
        my $target = $self->{_omop_stream_targets}{$entity};
        my $ok = eval {
            close $target->{fh} if defined fileno( $target->{fh} );
            1;
        };
        push @errors, $@ unless $ok;
    }

    $commit = 0 if @errors;
    for my $entity ( sort keys %{ $self->{_omop_stream_targets} } ) {
        my $target = $self->{_omop_stream_targets}{$entity};
        if ($commit) {
            my $ok = eval {
                commit_staged_path( $target->{staged}, $target->{path} );
                1;
            };
            unless ($ok) {
                push @errors, $@;
                my $discarded = eval {
                    discard_staged_path( $target->{staged} );
                    1;
                };
                push @errors, $@ unless $discarded;
                $commit = 0;
            }
        }
        else {
            my $ok = eval {
                discard_staged_path( $target->{staged} );
                1;
            };
            push @errors, $@ unless $ok;
        }
    }

    delete $self->{_omop_stream_targets};
    delete $self->{_omop_stream_seen};

    die join q{}, @errors if @errors;
    return 1;
}

sub _stream_entity_entry_seen {
    my ( $seen, $entity, $entry ) = @_;
    return 0
      unless $entity eq 'individuals'
      && ref($entry) eq 'HASH'
      && exists $entry->{id}
      && defined $entry->{id};

    return 1 if $seen->{$entity}{ $entry->{id} }++;
    return 0;
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

    if ( exists $self->{output_name_overrides}
        && exists $self->{output_name_overrides}{$entity} )
    {
        return $self->{output_name_overrides}{$entity};
    }

    return $self->{out_dir} . q{/} . $entity . '.json';
}

1;
