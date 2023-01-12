#!/usr/bin/env perl
use strict;
use warnings;
use YAML::XS 'LoadFile';
use Data::Dumper;
    
my $config = LoadFile('redcap_3tr_config.yaml');

print Dumper $config;
