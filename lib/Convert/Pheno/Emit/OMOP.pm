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

1;
