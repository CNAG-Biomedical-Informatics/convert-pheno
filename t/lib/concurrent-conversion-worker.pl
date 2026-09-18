use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../../lib";
use Path::Tiny qw(path);
use Time::HiRes qw(time sleep);
use File::Spec;

# A test-only gate proves workers overlap even when fixtures convert quickly.
# Releasing a worker runs the real conversion and publication implementation.
my $dir = path($ARGV[0]);
$dir->child('worker-ready')->spew_raw("$$");
my $deadline = time + 60;
until (-f $dir->child('release')) {
    die "Test worker gate timed out\n" if time > $deadline;
    sleep .02;
}
exit 7 if -f $dir->child('fail');
open STDOUT, '>', File::Spec->devnull or die $!;
open STDERR, '>', File::Spec->devnull or die $!;
require Convert::Pheno::HTTP::Jobs;
exit(Convert::Pheno::HTTP::Jobs->perform("$dir") ? 0 : 1);
