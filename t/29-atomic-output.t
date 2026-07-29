use strict;
use warnings;
use lib qw(./lib ../lib t/lib);

use File::Spec::Functions qw(catfile);
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use Test::Exception;
use Test::More;
use Test::ConvertPheno qw(run_command_capture);

use Convert::Pheno::IO::Atomic qw(write_atomically);

my $tmpdir = tempdir( CLEANUP => 1 );
my $target = catfile( $tmpdir, 'individuals.json' );
path($target)->spew_raw("old output\n");

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

write_atomically(
    $target,
    sub {
        my ($staged) = @_;
        path($staged)->spew_raw("new output\n");
    }
);
is( path($target)->slurp_raw, "new output\n", 'successful writes replace existing output' );

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
