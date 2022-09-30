#!/usr/bin/env perl
use strict;
use warnings;
use lib './lib';
use feature qw(say);
use Data::Dumper;
use Convert::Pheno;
use Test::Simple tests => 3;
use File::Compare;

my $input = {
    pxf2bff => {
        in_file           => 't/pxf2bff/in/all.json',
        redcap_dictionary => 'undef',
        out               => 't/pxf2bff/out/individuals.json'
    },
    redcap2bff => {
        in_file           => 't/redcap2bff/in/Data_table_3TR_IBD_dummydata.csv',
        redcap_dictionary => 't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        out               => 't/redcap2bff/out/individuals.json'
    },
    redcap2pxf => {
        in_file           => 't/redcap2bff/in/Data_table_3TR_IBD_dummydata.csv',
        redcap_dictionary =>
't/redcap2bff/in/3TRKielTemplateExport01072022_DataDictionary_2022-07-03.csv',
        out => 't/redcap2pxf/out/pxf.json'
    }
};

#for my $method (qw/redcap2bff/){
for my $method (sort keys %{$input}) {

    say "################";
    say "Testing $method ... ";
    my $convert = Convert::Pheno->new(
        {
            'in_file'           => $input->{$method}{in_file},
            'redcap_dictionary' => $input->{$method}{redcap_dictionary},
            'in_textfile'       => 1,
	    'test'              => 1,
            'method'            => $method
        }
    );

    dump_file(
        {
            filename => 't/test.json',
            data     => $convert->$method,
            format   => 'json'
        }
    );
    ok( compare( 't/test.json', $input->{$method}{out}) == 0 );
}

#########
sub dump_file {

    my $arg = shift;
    if ( $arg->{format} eq 'json' ) {
        write_json( { filename => $arg->{filename}, data => $arg->{data} } );
    }
    else {
        write_yaml( { filename => $arg->{filename}, data => $arg->{data} } );
    }
    return 1;
}
