#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Spec;

# Execute probe code from a file: Windows process argument quoting can alter
# embedded quotes in a Perl -e program, even with list-form system().
if ( @ARGV && $ARGV[0] eq '--probe' ) {
    no warnings 'once'; # Package variables belong to modules loaded below.
    $| = 1;
    # Load SSL first, before Mojolicious can catch and hide its load error.
    for my $module (qw(
        IO::Socket::SSL Convert::Pheno Config Mojolicious::Lite DBD::SQLite
        Excel::Writer::XLSX JSONLD Text::Levenshtein::XS XML::Fast YAML::XS
    )) {
        print "Loading $module\n";
        ( my $file = "$module.pm" ) =~ s{::}{/}g;
        require $file;
    }
    die "Runtime is not relocatable\n"
      if $^O ne 'MSWin32' && !$Config::Config{userelocatableinc};
    my $registry = File::Spec->catfile(
        $Convert::Pheno::share_dir, 'schema', 'public-conversions.json' );
    die "Share lookup failed: $registry\n" unless -f $registry;
    print "$Convert::Pheno::VERSION\n";
    exit 0;
}

my $engine = abs_path( shift // die "Usage: $0 ENGINE_DIRECTORY\n" )
  or die "Cannot resolve engine directory\n";
my $perl = File::Spec->catfile( $engine, 'runtime', 'bin',
    $^O eq 'MSWin32' ? 'perl.exe' : 'perl' );
die "Staged Perl executable is missing\n" unless -f $perl;

local %ENV = (
    (
        $^O eq 'MSWin32'
        ? ( SystemRoot => $ENV{SystemRoot}, WINDIR => $ENV{WINDIR},
            PATH => File::Spec->catdir( $engine, 'runtime', 'bin' ) )
        : ( HOME       => $ENV{HOME} || '/tmp' )
    ),
    CONVERT_PHENO_SHARE_DIR => File::Spec->catdir( $engine, 'share' ),
    ( $^O eq 'linux' ? ( LD_LIBRARY_PATH => File::Spec->catdir( $engine, 'runtime', 'lib' ) ) : () ),
    # On macOS, test the embedded @rpath library references without overriding
    # the loader environment, just as the installed desktop application does.
);
my @command = (
    $perl,
    '-I' . File::Spec->catdir( $engine, 'lib' ),
    abs_path(__FILE__),
    '--probe',
);
system @command;
die "Cannot start relocated Perl: $!\n" if $? == -1;
die sprintf("The relocated desktop engine failed its module smoke test (status %d)\n", $?)
  if $? != 0;
