use strict;
use warnings;
use lib 'lib';
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Cwd qw(abs_path);
use Path::Tiny qw(path);
use Time::HiRes qw(time sleep);
use Convert::Pheno::HTTP::Jobs;

my $root = tempdir(CLEANUP => 1);
my $jobs = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => abs_path('t/lib/queue-blocking-worker.pl'));
END { $jobs->shutdown if $jobs }
my $source = $jobs->register_file('t/pxf2bff/in/pxf.json');
sub enqueue {
    return $jobs->submit({ conversion => 'pxf2bff', input => {files => {source => [$source->{id}]}},
        output => {entities => ['individuals']}, options => {} });
}
my $active = enqueue();
my $deadline = time + 10;
until (-f path($root, $active->{id}, 'worker-ready')) {
    die 'Test worker did not start' if time > $deadline;
    sleep .02;
}
my @pending = map { enqueue() } 1..3;
my %positions = map { $_->{id} => $_->{queuePosition} } @{$jobs->list};
is_deeply([map {$positions{$_->{id}}} @pending], [1,2,3], 'queue positions follow submission order');
is($jobs->status($active->{id})->{status}, 'running', 'one active worker');
ok(!eval { $jobs->delete_history($active->{id}); 1 }, 'cannot delete an active run');
ok(!eval { $jobs->delete_history($pending[0]{id}); 1 }, 'cannot delete a queued run');
is($jobs->status($pending[0]{id})->{status}, 'queued', 'additional runs are queued');
is($pending[0]{outputDirectory}, File::Spec->catdir(abs_path($root), $pending[0]{id}, 'outputs'), 'exact planned output location is recorded at submission');
is($jobs->cancel($pending[1]{id})->{status}, 'cancelled', 'a specific queued run can be removed');
is($jobs->status($active->{id})->{status}, 'running', 'removing queued work does not cancel the active run');
ok(!-e path($root, $pending[1]{id}, 'request.json'), 'removed request payload is deleted');
is(scalar @{$jobs->cancel_pending}, 2, 'bulk action cancels only remaining queued runs');
is($jobs->status($active->{id})->{status}, 'running', 'bulk pending cancellation leaves active conversion alone');
is($jobs->cancel($active->{id})->{status}, 'cancelling', 'active cancellation has its own state');
$deadline = time + 10;
while ($jobs->status($active->{id})->{status} eq 'cancelling') {
    die 'Cancellation timed out' if time > $deadline;
    $jobs->poll; sleep .02;
}
is($jobs->status($active->{id})->{status}, 'cancelled', 'active worker stops');
ok(!-e path($root, $active->{id}, 'request.json'), 'cancelled worker payload is deleted');
is($jobs->cancel($active->{id})->{status}, 'cancelled', 'repeated cancellation is safe');
is(scalar @{$jobs->cancel_pending}, 0, 'empty pending queue is safe');
$jobs->shutdown;
my $outputs = path($root, $active->{id}, 'outputs');
$outputs->mkpath;
$outputs->child('synthetic.json')->spew_utf8('[]');
$jobs->delete_history($active->{id});
ok(!grep($_->{id} eq $active->{id}, @{$jobs->list}), 'deleted run is absent from history');
is($outputs->child('synthetic.json')->slurp_utf8, '[]', 'deleting history preserves default output files');
ok(-f $jobs->resolve_grant($source->{id}), 'source file remains available');
my $reopened = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => abs_path('t/lib/queue-blocking-worker.pl'));
ok(!grep($_->{id} eq $active->{id}, @{$reopened->list}), 'history deletion survives restart');
ok(!eval { $jobs->delete_history('../elsewhere'); 1 }, 'invalid run paths are rejected');
done_testing;
