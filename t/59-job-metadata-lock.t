use strict;
use warnings;
use lib qw(lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Test::ConvertPheno qw(run_command_capture);
use Convert::Pheno::HTTP::Jobs;

my $root = tempdir(CLEANUP => 1);
my $file = path($root, 'status.json');
my $lockfile = path($root, '.metadata.lock');

# Probe from a separate process: Windows and Unix differ in how locks held by
# another handle in the same process interact.
sub probe_lock {
    my ($expected, $message, $shared) = @_;
    my ($exit, $out, $err) = run_command_capture(command => [
        $^X, '-MFcntl=:flock', '-e',
        'open my $fh, ">>", $ARGV[0] or die $!; print flock($fh, ($ARGV[1] ? LOCK_SH : LOCK_EX) | LOCK_NB) ? "free" : "held";',
        "$lockfile", $shared ? 1 : 0,
    ]);
    is($exit, 0, "$message: probe runs") or diag $err;
    is($out, $expected, $message);
}

{
    no warnings 'redefine';
    my $write = \&Convert::Pheno::HTTP::Jobs::write_atomically;
    local *Convert::Pheno::HTTP::Jobs::write_atomically = sub {
        probe_lock('held', 'metadata replacement excludes other processes');
        probe_lock('held', 'metadata replacement excludes readers', 1);
        return $write->(@_);
    };
    Convert::Pheno::HTTP::Jobs::_write($file, {status => 'running'});
}
probe_lock('free', 'writer releases lock after publication');
{
    no warnings 'redefine';
    my $read = \&Path::Tiny::slurp_raw;
    local *Path::Tiny::slurp_raw = sub {
        probe_lock('held', 'metadata read excludes concurrent replacement');
        probe_lock('free', 'concurrent metadata readers can share the lock', 1);
        return $read->(@_);
    };
    is_deeply(Convert::Pheno::HTTP::Jobs::_read($file), {status => 'running'},
        'reader returns complete metadata');
}
probe_lock('free', 'reader releases lock after reading');

$file->spew_raw('{broken');
eval { Convert::Pheno::HTTP::Jobs::_read($file) };
ok($@, 'malformed JSON is not hidden');
probe_lock('free', 'failed read releases lock');
{
    no warnings 'redefine';
    local *Convert::Pheno::HTTP::Jobs::write_atomically = sub { die "write failed\n" };
    eval { Convert::Pheno::HTTP::Jobs::_write($file, {}) };
    like($@, qr/write failed/, 'write errors are propagated');
}
probe_lock('free', 'failed write releases lock');
unlink $file or die $!;
eval { Convert::Pheno::HTTP::Jobs::_read($file) };
ok($@, 'missing metadata is not hidden');
probe_lock('free', 'missing-file failure releases lock');
ok(-f $lockfile, 'stable lock file is retained for subsequent operations');

done_testing;
