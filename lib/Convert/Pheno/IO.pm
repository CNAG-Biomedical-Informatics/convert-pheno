package Convert::Pheno::IO;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Path::Tiny;
use File::Basename;
use YAML::XS qw(LoadFile DumpFile);
use JSON::XS;
use Sort::Naturally qw(nsort);
use Exporter 'import';
our @EXPORT = qw(read_json read_yaml is_it_yaml_or_json write_json write_yaml);

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

sub is_it_yaml_or_json {

    my $file = shift;
    my @exts = qw(.yaml .yml .json);
    my ( undef, undef, $ext ) = fileparse( $file, @exts );
    return
        ( $ext eq '.yaml' || $ext eq '.yml' ) ? read_yaml($file)
      : $ext eq '.json'                        ? read_json($file)
      : die
qq(Can't recognize <$file> extension. Please use a .yaml|.yml|.json file);
}

sub write_json {

    my $arg        = shift;
    my $file       = $arg->{filename};
    my $json_array = $arg->{data};
    my $json = JSON::XS->new->utf8->canonical->pretty->encode($json_array);
    path($file)->spew_utf8($json);
    return 1;
}

sub write_yaml {

    my $arg        = shift;
    my $file       = $arg->{filename};
    my $json_array = $arg->{data};
    DumpFile( $file, $json_array );
    return 1;
}
1;
