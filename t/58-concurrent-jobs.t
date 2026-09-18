use strict;
use warnings;
use lib 'lib';
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use Path::Tiny qw(path);
use Time::HiRes qw(time sleep);
use JSON::XS qw(decode_json);
use POSIX qw(WNOHANG);
use Convert::Pheno::HTTP::Jobs;
use Convert::Pheno::HTTP::Service qw(execute);

my $jobs;
local $ENV{CONVERT_PHENO_JOB_LIMIT} = 4;
END { $jobs->shutdown if $jobs }
my $source = 't/pxf2bff/in/pxf.json';
my $worker = abs_path('t/lib/concurrent-conversion-worker.pl');
my $options = {test => JSON::XS::true};
my $output = {entities => ['individuals', 'biosamples']};
my $expected = execute('pxf2bff', {input => {data => decode_json(path($source)->slurp_raw)},
    options => $options, output => $output});

sub until_ready {
    my ($condition) = @_;
    my $deadline = time + 45;
    until ($condition->()) {
        die "Concurrent worker test timed out\n" if time > $deadline;
        $jobs->poll;
        sleep .02;
    }
}

for my $limit (1..4) {
    subtest "$limit concurrent conversion workers" => sub {
        my $root = tempdir(CLEANUP => 1);
        my $destination = tempdir(CLEANUP => 1);
        $jobs = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => $worker);
        is($jobs->settings->{maxConcurrentJobs}, 1, 'default is conservative');
        $jobs->update_settings({maxConcurrentJobs => $limit});
        my $input = $jobs->register_file($source);
        my $target = $jobs->register_file($destination);
        my @runs = map {$jobs->submit({conversion => 'pxf2bff',
            input => {files => {source => [$input->{id}]}}, destination => $target->{id},
            options => $options, output => $output})} 1..($limit + 1);
        until_ready(sub { !grep { !-f path($root, $_->{id}, 'worker-ready') } @runs[0..$limit-1] });
        my %pids = map {path($root, $_->{id}, 'worker-ready')->slurp_raw => 1} @runs[0..$limit-1];
        is(scalar keys %pids, $limit, 'distinct live worker processes overlap');
        is(scalar keys %{$jobs->{active}}, $limit, 'scheduler fills exactly the configured slots');
        is($jobs->status($runs[-1]{id})->{status}, 'queued', 'extra conversion waits');
        ok(!-f path($root, $runs[-1]{id}, 'worker-ready'), 'queued worker has not started');
        path($root, $_->{id}, 'release')->touch for @runs[0..$limit-1];
        until_ready(sub { -f path($root, $runs[-1]{id}, 'worker-ready') });
        ok(keys(%{$jobs->{active}}) <= $limit, 'starting queued work respects limit');
        path($root, $runs[-1]{id}, 'release')->touch;
        until_ready(sub { !keys %{$jobs->{active}} });
        my %folders;
        for my $run (@runs) {
            my $status = $jobs->status($run->{id});
            is($status->{status}, 'completed', 'real fixture conversion completes') or diag explain $status;
            $folders{$status->{directory}}++;
            for my $artifact (@{$expected->{artifacts}}) {
                my ($file) = $jobs->artifact($run->{id}, $artifact->{id});
                is_deeply(decode_json(path($file)->slurp_raw), decode_json($artifact->{content}),
                    "$artifact->{id} matches the existing synchronous conversion");
            }
            ok(!-f path($root, $run->{id}, 'publication.json'), 'publication journal is cleared');
        }
        is(scalar keys %folders, scalar @runs, 'same destination parent has isolated output folders');
        $jobs->shutdown;
    };
}

subtest 'live limits, cancellation, failure and shutdown' => sub {
    my $root = tempdir(CLEANUP => 1);
    $jobs = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => $worker);
    for my $bad (undef, 0, -1, 1.5, 5, 17, 'four', [], JSON::XS::true) {
        ok(!eval {$jobs->update_settings({maxConcurrentJobs => $bad}); 1}, 'invalid limit rejected');
    }
    ok(!eval {$jobs->update_settings({maxConcurrentJobs => 4, unknown => 1}); 1}, 'unknown setting rejected');
    $jobs->update_settings({maxConcurrentJobs => 4});
    my $input = $jobs->register_file($source);
    my @runs = map {$jobs->submit({conversion => 'pxf2bff', input => {files => {source => [$input->{id}]}},
        options => $options, output => $output})} 1..7;
    until_ready(sub { !grep {!-f path($root, $_->{id}, 'worker-ready')} @runs[0..3] });
    $jobs->update_settings({maxConcurrentJobs => 2});
    is(scalar keys %{$jobs->{active}}, 4, 'lowering limit leaves existing jobs alive');
    $jobs->cancel($runs[0]{id});
    until_ready(sub { $jobs->status($runs[0]{id})->{status} eq 'cancelled' });
    is(scalar keys %{$jobs->{active}}, 3, 'cancelling one job does not cancel others or fill slots above new limit');
    path($root, $runs[1]{id}, 'fail')->touch;
    path($root, $runs[1]{id}, 'release')->touch;
    until_ready(sub { $jobs->status($runs[1]{id})->{status} eq 'failed' });
    is(scalar keys %{$jobs->{active}}, 2, 'worker failure is isolated');
    is($jobs->status($runs[4]{id})->{status}, 'queued', 'queue waits while at lowered limit');
    $jobs->update_settings({maxConcurrentJobs => 3});
    until_ready(sub { -f path($root, $runs[4]{id}, 'worker-ready') });
    is(scalar keys %{$jobs->{active}}, 3, 'raising limit starts queued work immediately');
    $jobs->cancel($runs[5]{id});
    is($jobs->status($runs[5]{id})->{status}, 'cancelled', 'queued cancellation is independent');
    my @pids = map {$_->{pid}} values %{$jobs->{active}};
    $jobs->shutdown;
    is($jobs->status($runs[6]{id})->{status}, 'cancelled', 'shutdown cancels queued work');
    ok(!-f path($root, $runs[6]{id}, 'worker-ready'), 'shutdown does not launch queued work');
    is(scalar keys %{$jobs->{active}}, 0, 'shutdown clears all workers');
    is(waitpid($_, WNOHANG), -1, 'worker was reaped') for @pids;
    is($jobs->status($runs[$_]{id})->{status}, 'cancelled', 'active job is cancelled on shutdown') for (2, 3, 4);
    $jobs = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => $worker);
    is($jobs->settings->{maxConcurrentJobs}, 3, 'preference survives service restart');
    $jobs->shutdown;
};
subtest 'saved settings adapt to a smaller machine' => sub {
    my $root = tempdir(CLEANUP => 1);
    $jobs = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => $worker);
    $jobs->update_settings({maxConcurrentJobs => 4});
    $jobs->shutdown;
    local $ENV{CONVERT_PHENO_JOB_LIMIT} = 2;
    $jobs = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => $worker);
    is_deeply($jobs->settings, {maxConcurrentJobs => 2, maxAllowedConcurrentJobs => 2},
        'saved preference is capped to the available limit');
    ok(!eval {$jobs->update_settings({maxConcurrentJobs => 3}); 1}, 'API enforces machine limit');
    $jobs->shutdown;
    delete $ENV{CONVERT_PHENO_JOB_LIMIT};
    $jobs = Convert::Pheno::HTTP::Jobs->new(root => $root, worker => $worker);
    is($jobs->settings->{maxConcurrentJobs}, 1, 'missing detection falls back safely to one');
    $jobs->shutdown;
};
done_testing;
