#!/usr/bin/env perl
use strict;
use warnings;
use lib ('./lib', '../lib');
use feature qw(say);
use Data::Dumper;
use Convert::Pheno;
use Test::More tests => 2;
use File::Compare;

use_ok( 'Convert::Pheno' ) or exit;

my $input = {
    bff2pxf => {
        in_file           => 't/bff2pxf/in/individuals.json',
        out               => 't/bff2pxf/out/pxf.json'
    }
};

#for my $method (qw/redcap2bff/){
for my $method ( sort keys %{$input} ) {

    #say "################";
    my $convert = Convert::Pheno->new(
        {
            in_file  => $input->{$method}{in_file},
            in_textfile       => 1,
            test              => 1,
            debug             => 5,
            method            => $method
        }
    );
    io_yaml_or_json(
        {
            filename => 't/test.json',
            data     => $convert->$method,
            mode   => 'write'
        }
    );
    ok( compare( $input->{$method}{out}, 't/test.json' ) == 0 , $method);
}
