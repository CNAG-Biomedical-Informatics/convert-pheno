#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../../lib";
use File::Spec;
# Conversion warnings are collected by the shared service. Never send clinical
# payloads or verbose converter output to the supervisor's operational logs.
open STDOUT, '>', File::Spec->devnull or die 'Cannot isolate worker output';
open STDERR, '>', File::Spec->devnull or die 'Cannot isolate worker errors';
use Convert::Pheno::HTTP::Jobs;
exit(Convert::Pheno::HTTP::Jobs->perform($ARGV[0]) ? 0 : 1);
