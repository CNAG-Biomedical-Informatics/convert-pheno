package Convert::Pheno::IO::FileIO;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Path::Tiny;
use File::Basename;
use List::Util qw(any);
use YAML::XS qw(LoadFile DumpFile);
$YAML::XS::Boolean = 'JSON::PP';    # use JSON::PP::Boolean objects
use JSON::XS;
use Sort::Naturally qw(nsort);
use Data::Leaf::Walker;
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

    my $data = LoadFile(shift);    # Decode to Perl data structure
    traverse_yaml_data_to_coerce_numbers($data)
      ;    # revert floatings getting stringified by YAML::XS
    return $data;
}

sub io_yaml_or_json {

    my $arg  = shift;
    my $file = $arg->{filepath};
    my $mode = $arg->{mode};
    my $data = $mode eq 'write' ? $arg->{data} : undef;

    # Checking for the below extension
    my @exts = qw(.yaml .yml .json .jsonld .ymlld .yamlld);
    my $msg  = qq(Can't recognize <$file> extension. Extensions allowed are: )
      . ( join ',', @exts ) . "\n";
    my ( undef, undef, $ext ) = fileparse( $file, @exts );
    die $msg unless any { $_ eq $ext } @exts;

    # To simplify return values, we create a hash
    $ext =~ tr/a.//d;    # Unify $ext (delete 'a' and '.')
    $ext =~ s/ld$//;     # delete ending ld
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

    my $arg       = shift;
    my $file      = $arg->{filepath};
    my $json_data = $arg->{data};
    my $json      = JSON::XS->new->utf8->canonical->pretty->encode($json_data);
    path($file)->spew_utf8($json);
    return 1;
}

sub write_yaml {

    my $arg       = shift;
    my $file      = $arg->{filepath};
    my $json_data = $arg->{data};
    DumpFile( $file, $json_data );
    return 1;
}

sub traverse_yaml_data_to_coerce_numbers {

    my $data = shift;

    # Traversing the data to force numbers to be numbers
    # NB: Changing the original data structure
    my $walker = Data::Leaf::Walker->new($data);
    while ( my ( $key_path, $value ) = $walker->each ) {
        $walker->store( $key_path, $value + 0 )
          if Scalar::Util::looks_like_number $value;
    }
}

1;
