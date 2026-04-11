package Convert::Pheno::IO::FileIO;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Path::Tiny;
use File::Basename;
use List::Util qw(any);
use YAML::XS qw(Load Dump);
$YAML::XS::Boolean = 'JSON::PP';    # use JSON::PP::Boolean objects
use JSON::XS;
use IO::Compress::Gzip     qw($GzipError);
use IO::Uncompress::Gunzip qw($GunzipError);
use Sort::Naturally qw(nsort);
use Data::Leaf::Walker;
use Exporter 'import';
our @EXPORT = qw(read_json read_yaml io_yaml_or_json write_json write_yaml);

#########################
#########################
#  SUBROUTINES FOR I/O  #
#########################
#########################

sub _slurp_text {
    my ($file) = @_;

    if ( $file =~ /\.gz$/ ) {
        # Gzipped text has to be decoded explicitly because Path::Tiny only
        # covers plain files. Keep this logic isolated so plain-file semantics
        # stay unchanged elsewhere.
        my $fh = IO::Uncompress::Gunzip->new( $file, MultiStream => 1 )
          or die "Cannot gunzip <$file>: $GunzipError";
        binmode( $fh, ':encoding(UTF-8)' );
        return do { local $/; <$fh> };
    }

    return path($file)->slurp_utf8;
}

sub _slurp_raw {
    my ($file) = @_;

    if ( $file =~ /\.gz$/ ) {
        # JSON::XS and YAML::XS do not want the same thing:
        # JSON decoding expects UTF-8 bytes, while some YAML paths are safer
        # when delegated to YAML::XS file APIs. This helper is only for cases
        # where raw bytes are the correct boundary.
        my $fh = IO::Uncompress::Gunzip->new( $file, MultiStream => 1 )
          or die "Cannot gunzip <$file>: $GunzipError";
        return do { local $/; <$fh> };
    }

    return path($file)->slurp_raw;
}

sub _spew_text {
    my ( $file, $text ) = @_;

    if ( $file =~ /\.gz$/ ) {
        # JSON strings produced without ->utf8 are Perl text and should be
        # encoded exactly once at the filehandle boundary.
        my $fh = IO::Compress::Gzip->new($file)
          or die "Cannot gzip <$file>: $GzipError";
        binmode( $fh, ':encoding(UTF-8)' );
        print {$fh} $text;
        close $fh;
        return 1;
    }

    path($file)->spew_utf8($text);
    return 1;
}

sub _spew_raw {
    my ( $file, $text ) = @_;

    if ( $file =~ /\.gz$/ ) {
        # Keep a raw gzip path for payloads already serialized by another
        # library. Re-encoding here caused the mojibake regressions we saw in
        # the fixtures.
        my $fh = IO::Compress::Gzip->new($file)
          or die "Cannot gzip <$file>: $GzipError";
        print {$fh} $text;
        close $fh;
        return 1;
    }

    path($file)->spew_raw($text);
    return 1;
}

sub read_json {
    my $str = _slurp_raw(shift);
    return decode_json($str);    # Decode to Perl data structure
}

sub read_yaml {
    my $file = shift;
    my $data =
      $file =~ /\.gz$/
      ? Load( _slurp_raw($file) )
      : YAML::XS::LoadFile($file);    # preserve legacy plain-file behavior
    # Do not replace the plain-file branch with slurp+Load. LoadFile and
    # Path::Tiny had stable semantics here and changing that broke fixtures
    # containing non-ASCII text.
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
    my @exts = map { $_, $_ . '.gz' } qw(.yaml .yml .json .jsonld .ymlld .yamlld);
    my $msg  = qq(Can't recognize <$file> extension. Extensions allowed are: )
      . ( join ',', @exts ) . "\n";
    my ( undef, undef, $ext ) = fileparse( $file, @exts );
    die $msg unless any { $_ eq $ext } @exts;

    # To simplify return values, we create a hash
    $ext =~ s/\.gz$//;
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
    # Intentionally omit ->utf8 here. We want a Perl character string for
    # plain files and let the writer encode once at the boundary.
    my $json = JSON::XS->new->canonical->pretty->encode($json_data);
    return _spew_text( $file, $json );
}

sub write_yaml {
    my $arg       = shift;
    my $file      = $arg->{filepath};
    my $json_data = $arg->{data};
    # Keep YAML::XS::DumpFile for plain files to match the historical
    # behavior. Gzip is the only special case that needs a manual writer.
    return _spew_raw( $file, Dump($json_data) ) if $file =~ /\.gz$/;

    YAML::XS::DumpFile( $file, $json_data );
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
