use strict;
use warnings;
use Fcntl qw(:flock);
use Errno qw(EAGAIN EWOULDBLOCK EACCES);

# A script avoids Windows command-line quoting of inline Perl source.
my ($file, $shared) = @ARGV;
open my $fh, '>>', $file or die "Cannot open lock probe <$file>: $!\n";
if (flock($fh, ($shared ? LOCK_SH : LOCK_EX) | LOCK_NB)) {
    print 'free';
}
else {
    die "Cannot probe lock <$file>: $!\n"
      unless $! == EAGAIN || $! == EWOULDBLOCK || $! == EACCES;
    print 'held';
}
