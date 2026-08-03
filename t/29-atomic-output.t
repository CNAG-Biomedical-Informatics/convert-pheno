use strict;
use warnings;
use lib qw(./lib ../lib t/lib);

use File::Spec::Functions qw(catfile);
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Test::Exception;
use Test::More;
use Test::ConvertPheno qw(run_command_capture);

use Convert::Pheno::IO::Atomic qw(
  commit_staged_path
  create_staged_path
  discard_staged_path
  write_atomically
);

my $tmpdir = tempdir( CLEANUP => 1 );
my $target = catfile( $tmpdir, 'individuals.json' );
path($target)->spew_raw("old output\n");

throws_ok(
    sub { create_staged_path() },
    qr/Atomic output target is required/,
    'staging requires an output target',
);
throws_ok(
    sub { write_atomically( $target, 'not-a-writer' ) },
    qr/Atomic output writer must be a code reference/,
    'atomic writes require a writer callback',
);
throws_ok(
    sub { commit_staged_path( catfile( $tmpdir, 'missing.json' ), $target ) },
    qr/Staged output file is missing/,
    'committing requires an existing staged file',
);
ok( discard_staged_path(), 'discarding an absent staged path is harmless' );

throws_ok(
    sub {
        write_atomically(
            $target,
            sub {
                my ($staged) = @_;
                path($staged)->spew_raw("partial output\n");
                die "conversion failed\n";
            }
        );
    },
    qr/conversion failed/,
    'atomic writer preserves conversion failures'
);
is( path($target)->slurp_raw, "old output\n", 'failed writes preserve existing output' );

chmod 0640, $target or die "Could not set test output permissions: $!";
write_atomically(
    $target,
    sub {
        my ($staged) = @_;
        path($staged)->spew_raw("new output\n");
    }
);
is( path($target)->slurp_raw, "new output\n", 'successful writes replace existing output' );
is( ( stat $target )[2] & 07777, 0640, 'successful replacement preserves existing permissions' );

my $staged = create_staged_path( catfile( $tmpdir, 'blocked.json' ) );
path($staged)->spew_raw("staged output\n");
throws_ok(
    sub { commit_staged_path( $staged, $tmpdir ) },
    qr/Could not replace output/,
    'a failed portable rename reports the target error',
);
ok( -f $staged, 'a failed direct commit leaves the staged file recoverable' );
ok( discard_staged_path($staged), 'the caller can discard a failed staged commit' );

throws_ok(
    sub {
        write_atomically(
            $tmpdir,
            sub {
                my ($temporary) = @_;
                path($temporary)->spew_raw("cannot replace a directory\n");
            }
        );
    },
    qr/Could not replace output/,
    'write_atomically propagates commit failures',
);

my $invalid_input = catfile( $tmpdir, 'invalid-pxf.json' );
path($invalid_input)->spew_raw("{\n");
path($target)->spew_raw("existing CLI output\n");
my ( $exit, undef, undef ) = run_command_capture(
    command => [
        $^X,
        catfile( 'bin', 'convert-pheno' ),
        '-ipxf',
        $invalid_input,
        '-obff',
        $target,
        '-O',
    ],
);

isnt( $exit, 0, 'CLI reports a failed conversion' );
is(
    path($target)->slurp_raw,
    "existing CLI output\n",
    'CLI conversion failures preserve an existing output file'
);

opendir( my $dir, $tmpdir );
my @staged = grep { /^\.convert-pheno-/ } readdir $dir;
closedir($dir);
is_deeply( \@staged, [], 'atomic writes leave no staged files behind' );

done_testing;
