use strict;
use warnings;
use lib 'lib';
use Test::More;
use Config;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use JSON::XS qw(decode_json);
use Time::HiRes qw(time sleep);

# Optional experiment, not a runtime dependency or a replacement for HTTP::Jobs.
plan skip_all => 'Minion and its SQLite backend are optional evaluation dependencies'
  unless eval { require Minion; require Minion::Backend::SQLite; 1 };
plan skip_all => 'Minion explicitly rejects this Perl fork emulation'
  if $Config{d_pseudofork};

use Convert::Pheno::HTTP::Service qw(execute);
my $root = tempdir(CLEANUP => 1);
my $database = path($root, 'queue.db');
my $fixture = 't/pxf2bff/in/pxf.json';
my $minion = Minion->new(SQLite => "$database");
diag "Evaluating Minion $Minion::VERSION / SQLite backend $Minion::Backend::SQLite::VERSION on $^O";
$minion->add_task(convert => sub {
    my ($job) = @_;
    my $result = execute('pxf2bff', {
        input => {data => decode_json(path($fixture)->slurp_raw)},
        output => {entities => ['individuals', 'biosamples']},
        options => {test => JSON::XS::true},
    });
    for my $artifact (@{$result->{artifacts}}) {
        path($root, $artifact->{filename})->spew_utf8($artifact->{content});
    }
    $job->finish({outputs => [map {$_->{filename}} @{$result->{artifacts}}]});
});
$minion->add_task(slow => sub { sleep 30 });
$minion->add_task(failure => sub { die "Synthetic failure\n" });

my ($worker, $active);
END {
    if ($active && $active->pid) {
        $active->stop;
        waitpid($active->pid, 0);
    }
    $worker->unregister if $worker && $worker->id;
}
sub finish_active {
    my $deadline = time + 15;
    until ($active->is_finished) {
        die "Evaluation worker timed out\n" if time > $deadline;
        sleep .02;
    }
    undef $active;
}

my $conversion = $minion->enqueue(convert => [] => {attempts => 1});
is($minion->job($conversion)->info->{state}, 'inactive', 'submission queues without executing');
my $reopened = Minion->new(SQLite => "$database");
is($reopened->job($conversion)->info->{state}, 'inactive', 'pending job survives a new connection');
$worker = $minion->worker->register;
$active = $worker->dequeue(0)->start;
is($minion->job($conversion)->info->{state}, 'active', 'conversion executes in a child process');
finish_active();
is($minion->job($conversion)->info->{state}, 'finished', 'real conversion completes');
my $expected = execute('pxf2bff', {
    input => {data => decode_json(path($fixture)->slurp_raw)},
    output => {entities => ['individuals', 'biosamples']}, options => {test => JSON::XS::true},
});
for my $artifact (@{$expected->{artifacts}}) {
    is_deeply(decode_json(path($root, $artifact->{filename})->slurp_raw), decode_json($artifact->{content}),
        "$artifact->{id} agrees with the existing conversion");
}
my $slow = $minion->enqueue(slow => [] => {attempts => 1});
$active = $worker->dequeue(0)->start;
my $cancelled_at = time;
$active->stop;
finish_active();
cmp_ok(time - $cancelled_at, '<', 5, 'active worker can be cancelled promptly');
is($minion->job($slow)->info->{state}, 'failed', 'Minion reports cancellation as failure, requiring API translation');
my $failure = $minion->enqueue(failure => [] => {attempts => 1});
$active = $worker->dequeue(0)->start;
finish_active();
is($minion->job($failure)->info->{state}, 'failed', 'task errors are recorded');
is($minion->job($failure)->info->{retries}, 0, 'no automatic retries with attempts set to one');

my $pending = $minion->enqueue(convert => [] => {attempts => 1});
$worker->unregister;
is($reopened->job($pending)->info->{state}, 'inactive', 'pending work survives idle worker shutdown');
$worker = $minion->worker->register;
$active = $worker->dequeue(0)->start;
finish_active();
is($reopened->job($pending)->info->{state}, 'finished', 'replacement worker can consume persisted work');

{
    # This checks the rejection branch, NOT execution on a real Windows host.
    my %emulated = (d_pseudofork => 'define');
    no warnings 'once';
    local *Minion::Config = \%emulated;
    eval { $minion->worker };
    like($@, qr/do not support fork emulation/, 'fork-emulation guard blocks native Windows worker strategy');
}
$worker->unregister;
done_testing;
