package Convert::Pheno::IO;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Path::Tiny;
use File::Basename;
use List::Util qw(any);
use YAML::XS   qw(LoadFile DumpFile);
use JSON::XS;
use Sort::Naturally qw(nsort);
use Exporter 'import';
our @EXPORT = qw(read_json read_yaml io_yaml_or_json write_json write_yaml);

#########################
#########################
#  SUBROUTINES FOR I/O  #
#########################
#########################

sub read_json {

    my $str = path(shift)->slurp_utf8;
    return decode_json($str);    # Decode to Perl data structure
}

sub read_yaml {

    return LoadFile(shift);      # Decode to Perl data structure
}

sub io_yaml_or_json {

    my $arg  = shift;
    my $file = $arg->{filepath};
    my $mode = $arg->{mode};
    my $data = $mode eq 'write' ? $arg->{data} : undef;

    # Checking only for qw(.yaml .yml .json)
    my @exts = qw(.yaml .yml .json);
    my $msg  = qq(Can't recognize <$file> extension. Extensions allowed are: )
      . join ',', @exts;
    my ( undef, undef, $ext ) = fileparse( $file, @exts );
    die $msg unless any { $_ eq $ext } @exts;

    # To simplify return values, we create a hash
    $ext =~ tr/a.//d;    # Unify $ext (delete 'a' and '.')
    my $return = {
        read  => { json => \&read_json,  yml => \&read_yaml },
        write => { json => \&write_json, yml => \&write_yaml }
    };

    # We return according to the mode (read or write) and format
    return $mode eq 'read'
      ? $return->{$mode}{$ext}->($file)
      : $return->{$mode}{$ext}->( { filepath => $file, data => $data } );
}

sub write_json {

    my $arg        = shift;
    my $file       = $arg->{filepath};
    my $json_array = $arg->{data};
    my $json = JSON::XS->new->utf8->canonical->pretty->encode($json_array);
    path($file)->spew_utf8($json);
    return 1;
}

sub write_yaml {

    my $arg        = shift;
    my $file       = $arg->{filepath};
    my $json_array = $arg->{data};
    local $YAML::XS::Boolean = 'JSON::PP';
    DumpFile( $file, $json_array );
    return 1;
}
1;
