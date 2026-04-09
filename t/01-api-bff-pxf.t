#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno qw(
  build_convert
  read_first_json_object
  temp_output_file
  write_json_file
  csv_headers_from_file
  write_csv_rows
  structured_files_match
);

my @cases = (
    {
        name     => 'bff2pxf',
        method   => 'bff2pxf',
        in_file  => 't/bff2pxf/in/individuals.json',
        out_file => 't/bff2pxf/out/pxf.json',
        writer   => 'json',
    },
    {
        name     => 'pxf2bff_json',
        method   => 'pxf2bff',
        in_file  => 't/pxf2bff/in/pxf.json',
        out_file => 't/pxf2bff/out/individuals.json',
        writer   => 'json',
    },
    {
        name     => 'pxf2bff_yaml',
        method   => 'pxf2bff',
        in_file  => 't/pxf2bff/in/pxf.yaml',
        out_file => 't/pxf2bff/out/individuals.yaml',
        writer   => 'json',
    },
    {
        name     => 'bff2csv',
        method   => 'bff2csv',
        in_file  => 't/bff2pxf/in/individuals.json',
        out_file => 't/bff2csv/out/individuals.csv',
        writer   => 'csv',
    },
    {
        name     => 'bff2jsonf',
        method   => 'bff2jsonf',
        in_file  => 't/bff2pxf/in/individuals.json',
        out_file => 't/bff2jsonf/out/individuals.fold.json',
        writer   => 'json',
    },
    {
        name     => 'pxf2csv',
        method   => 'pxf2csv',
        in_file  => 't/pxf2bff/in/pxf.json',
        out_file => 't/pxf2csv/out/pxf.csv',
        writer   => 'csv',
    },
    {
        name     => 'pxf2jsonf',
        method   => 'pxf2jsonf',
        in_file  => 't/pxf2bff/in/pxf.json',
        out_file => 't/pxf2jsonf/out/pxf.fold.json',
        writer   => 'json',
    },
);

for my $case (@cases) {
    my $tmp_file = temp_output_file(
        suffix => $case->{writer} eq 'csv' ? '.csv' : '.json'
    );

    my $convert = build_convert(
        in_file  => $case->{in_file},
        out_file => $tmp_file,
        method   => $case->{method},
    );

    if ( $case->{writer} eq 'csv' ) {
        my $data = $convert->${ \$case->{method} };
        my $headers = csv_headers_from_file( $case->{out_file} );
        write_csv_rows( $tmp_file, $headers, $data );
    }
    else {
        my $suffix = $case->{out_file} =~ /\.ya?ml$/ ? '.yaml' : '.json';
        $tmp_file =~ s/\.[^.]+$/$suffix/;
        write_json_file( $tmp_file, $convert->${ \$case->{method} } );
    }

    my $match =
      $case->{writer} eq 'csv'
      ? Test::ConvertPheno::json_files_match( $case->{out_file}, $tmp_file )
      : structured_files_match( $case->{out_file}, $tmp_file );
    ok( $match, $case->{name} );
}

{
    my $bff = read_first_json_object('t/bff2pxf/in/individuals.json');
    my $pxf = read_first_json_object('t/bff2pxf/out/pxf.json');

    $pxf->{$_} = undef for qw(id metaData);

    my $convert = build_convert(
        in_textfile => 0,
        data        => $bff,
        method      => 'bff2pxf',
    );

    my $got = $convert->bff2pxf;
    $got->{$_} = undef for qw(id metaData);

    is_deeply( $got, $pxf, 'bff2pxf module conversion matches fixture' );
}

done_testing();
