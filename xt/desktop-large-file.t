use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use Path::Tiny qw(path);
use JSON::XS qw(decode_json encode_json);
use Time::HiRes qw(time sleep);
use Convert::Pheno::HTTP::Jobs;

# Generate larger input at runtime, without adding or changing reference fixtures.
my $root = tempdir(CLEANUP => 1);
my $count = $ENV{CONVERT_PHENO_LARGE_TEST_RECORDS} || 1000;
die 'Invalid record count' unless $count =~ /\A[1-9][0-9]*\z/ && $count <= 100000;
my $record = decode_json(path('t/pxf2bff/in/pxf.json')->slurp_raw)->[0];
my $source = path($root, 'synthetic.json');
open my $fh, '>:raw', $source or die $!;
print {$fh} '[';
for my $i (1..$count) {
    $record->{id} = "synthetic-packet-$i";
    $record->{subject}{id} = "synthetic-person-$i";
    print {$fh} ($i > 1 ? ',' : ''), encode_json($record);
}
print {$fh} ']'; close $fh;
my $jobs = Convert::Pheno::HTTP::Jobs->new(root => "$root/runs", worker => abs_path('api/perl/worker.pl'));
END { $jobs->shutdown if $jobs }
my $grant = $jobs->register_file("$source");
my $start = time;
my $run = $jobs->submit({conversion => 'pxf2bff', input => {files => {source => [$grant->{id}]}},
    options => {test => JSON::XS::true}, output => {entities => ['individuals']}});
my $deadline = time + 180;
my $polls = 0;
while ($jobs->status($run->{id})->{status} =~ /\A(?:queued|running)\z/) {
    die 'Large conversion timed out' if time > $deadline;
    $jobs->poll; $jobs->list; $polls++; sleep .05;
}
my $status = $jobs->status($run->{id});
is($status->{status}, 'completed', 'larger native file conversion completes') or diag explain $status;
ok($polls, 'supervisor remains available while child converts');
if ($status->{status} eq 'completed') {
    my ($output) = $jobs->artifact($run->{id}, 'individuals');
    my $records = decode_json($output->slurp_raw);
    is(scalar @$records, $count, 'all synthetic people are emitted');
    is($records->[0]{id}, 'synthetic-person-1', 'first person retained');
    is($records->[-1]{id}, "synthetic-person-$count", 'last person retained');
    ok(!exists $status->{result}{artifacts}[0]{content}, 'job response does not embed large output');
    ok($jobs->preview($run->{id}, 'individuals')->{truncated}, 'output preview stays bounded');
}
diag sprintf('Synthetic input: %.1f MiB; records: %d; elapsed: %.2fs', (-s $source) / 1048576, $count, time - $start);
$jobs->shutdown;
done_testing;
