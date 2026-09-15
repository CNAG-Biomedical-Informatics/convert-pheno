use strict;
use warnings;
use Path::Tiny qw(path);
# Intentionally idle worker for deterministic queue-control tests only.
path($ARGV[0], 'worker-ready')->spew_raw('ready');
sleep 60;
