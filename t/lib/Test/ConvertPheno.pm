package Test::ConvertPheno;

use strict;
use warnings;

use Exporter 'import';
use Config;
use File::Compare qw(compare);
use File::Path qw(mkpath remove_tree);
use File::Spec;
use File::Temp qw(tempfile);
use FindBin qw($Bin);
use IO::Uncompress::Gunzip;
use JSON::XS qw(decode_json);
use Text::CSV_XS;
use lib qw(./lib ../lib);
use Convert::Pheno;
use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);

our @EXPORT_OK = qw(
  build_convert
  is_ld_arch
  is_windows
  has_ohdsi_db
  slurp_file
  load_json_file
  read_first_json_object
  temp_output_file
  json_files_match
  write_json_file
  csv_headers_from_file
  load_csv_table
  write_csv_rows
  load_data_file
  structured_files_match
  cli_script_path
  ensure_clean_dir
  remove_dir_if_exists
  csv_files_match
  gunzip_file_content
);

sub build_convert {
    my (%args) = @_;

    return Convert::Pheno->new(
        {
            in_files             => [],
            in_textfile          => 1,
            self_validate_schema => 0,
            schema_file          => 'share/schema/mapping.json',
            stream               => 0,
            omop_tables          => [],
            search               => 'exact',
            test                 => 1,
            %args,
        }
    );
}

sub is_ld_arch {
    return $Config{archname} =~ /-ld\b/ ? 1 : 0;
}

sub is_windows {
    return ( $^O eq 'MSWin32' || $^O eq 'cygwin' ) ? 1 : 0;
}

sub has_ohdsi_db {
    return -f 'share/db/ohdsi.db' ? 1 : 0;
}

sub slurp_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub load_json_file {
    my ($file) = @_;
    return decode_json( slurp_file($file) );
}

sub read_first_json_object {
    my ($file) = @_;
    my $json = load_json_file($file);
    die "Expected a JSON array in $file" unless ref $json eq 'ARRAY';
    return $json->[0];
}

sub temp_output_file {
    my (%args) = @_;
    my $suffix = exists $args{suffix} ? $args{suffix} : '.json';
    my $dir    = exists $args{dir}    ? $args{dir}    : 't';
    my ( undef, $file ) = tempfile( DIR => $dir, SUFFIX => $suffix, UNLINK => 1 );
    return $file;
}

sub json_files_match {
    my ( $expected, $got ) = @_;
    return compare( $expected, $got ) == 0 ? 1 : 0;
}

sub write_json_file {
    my ( $file, $data ) = @_;
    return io_yaml_or_json(
        {
            filepath => $file,
            mode     => 'write',
            data     => $data,
        }
    );
}

sub csv_headers_from_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    my $csv = Text::CSV_XS->new( { binary => 1, sep_char => ';' } );
    my $row = $csv->getline($fh);
    close $fh;
    return $row;
}

sub load_csv_table {
    my ($file) = @_;
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    my $csv = Text::CSV_XS->new( { binary => 1, sep_char => ';' } );
    my $headers = $csv->getline($fh);
    my @rows;
    while ( my $row = $csv->getline($fh) ) {
        my %item;
        @item{@$headers} = @$row;
        push @rows, \%item;
    }
    close $fh;
    return \@rows;
}

sub write_csv_rows {
    my ( $file, $headers, $rows ) = @_;
    open my $fh, '>', $file or die "Could not open file '$file': $!";
    my $csv = Text::CSV_XS->new( { binary => 1, eol => "\n", sep_char => ';' } );
    $csv->print( $fh, $headers );
    for my $row (@$rows) {
        $csv->print( $fh, [ map { $row->{$_} } @$headers ] );
    }
    close $fh;
    return 1;
}

sub load_data_file {
    my ($file) = @_;
    return io_yaml_or_json(
        {
            filepath => $file,
            mode     => 'read',
        }
    );
}

sub structured_files_match {
    my ( $expected, $got ) = @_;
    my $expected_data = load_data_file($expected);
    my $got_data      = load_data_file($got);
    my $json = JSON::XS->new->canonical;
    return $json->encode($expected_data) eq $json->encode($got_data) ? 1 : 0;
}

sub cli_script_path {
    return File::Spec->catfile( $Bin, '..', 'bin', 'convert-pheno' );
}

sub ensure_clean_dir {
    my ($dir) = @_;
    remove_tree($dir) if -d $dir;
    mkpath($dir);
    return $dir;
}

sub remove_dir_if_exists {
    my ($dir) = @_;
    remove_tree($dir) if -d $dir;
    return 1;
}

sub csv_files_match {
    my ( $expected, $got ) = @_;
    return compare( $expected, $got ) == 0 ? 1 : 0;
}

sub gunzip_file_content {
    my ($file) = @_;
    my $z = IO::Uncompress::Gunzip->new($file)
      or die "Cannot gunzip '$file': $IO::Uncompress::Gunzip::GunzipError";
    my $content = do { local $/; <$z> };
    $z->close();
    return $content;
}

1;
