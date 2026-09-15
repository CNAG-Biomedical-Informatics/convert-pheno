#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Spec;

my $engine = abs_path( shift // die "Usage: $0 ENGINE_DIRECTORY\n" )
  or die "Cannot resolve engine directory\n";
my $perl = File::Spec->catfile( $engine, 'runtime', 'bin',
    $^O eq 'MSWin32' ? 'perl.exe' : 'perl' );
die "Staged Perl executable is missing\n" unless -f $perl;

local %ENV = (
    (
        $^O eq 'MSWin32'
        ? ( SystemRoot => $ENV{SystemRoot}, WINDIR => $ENV{WINDIR} )
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
    '-MConvert::Pheno',
    '-MConfig',
    '-MMojolicious::Lite',
    '-MDBD::SQLite',
    '-MIO::Socket::SSL',
    '-MExcel::Writer::XLSX',
    '-MJSONLD',
    '-MText::Levenshtein::XS',
    '-MXML::Fast',
    '-MYAML::XS',
    '-e',
    'die "runtime is not relocatable" if $^O ne "MSWin32" && !$Config{userelocatableinc}; die "share lookup failed" unless -f "$Convert::Pheno::share_dir/schema/public-conversions.json"; print "$Convert::Pheno::VERSION\n"',
);
system @command;
die "The relocated desktop engine failed its module smoke test\n" if $? != 0;
