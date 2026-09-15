#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path remove_tree);
use File::Spec;
use Getopt::Long qw(GetOptions);
use JSON::PP;

my ( $root, $destination, $perl_prefix, $compiler_bin );
GetOptions(
    'root=s'         => \$root,
    'destination=s'  => \$destination,
    'perl-prefix=s'  => \$perl_prefix,
    'compiler-bin=s' => \$compiler_bin,
) or die "Invalid arguments\n";

$root = abs_path( $root // '.' ) or die "Cannot resolve repository root\n";
$perl_prefix = abs_path( $perl_prefix // die "Provide --perl-prefix\n" )
  or die "Cannot resolve Perl prefix\n";
$destination = File::Spec->rel2abs(
    $destination // File::Spec->catdir( $root, 'app', 'src-tauri', 'engine' ) );

my $expected = File::Spec->catdir( $root, 'app', 'src-tauri', 'engine' );
die "Destination must be app/src-tauri/engine\n"
  unless File::Spec->canonpath($destination) eq File::Spec->canonpath($expected);
die "Refusing to package a system Perl prefix\n"
  if $perl_prefix eq File::Spec->rootdir || $perl_prefix eq '/usr' || $perl_prefix eq '/usr/local';

remove_tree($destination) if -e $destination;
make_path($destination);

sub copy_tree {
    my ( $source, $target, $include ) = @_;
    die "Missing package source <$source>\n" unless -e $source;
    my $source_abs = abs_path($source) || $source;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                my $relative = File::Spec->abs2rel( $path, $source_abs );
                return if $relative eq '.';
                my $is_dir = -d $path && !-l $path;
                unless ( $include->( $relative, $is_dir ) ) {
                    $File::Find::prune = 1 if $is_dir;
                    return;
                }
                my $output = File::Spec->catfile( $target, $relative );
                if ($is_dir) {
                    make_path($output);
                    return;
                }
                make_path( dirname($output) );
                if ( -l $path ) {
                    my $link = readlink($path);
                    die "Absolute link in runtime: $path\n"
                      if File::Spec->file_name_is_absolute($link);
                    symlink $link, $output or die "Cannot copy link <$path>: $!\n";
                    return;
                }
                copy( $path, $output ) or die "Cannot copy <$path>: $!\n";
                chmod( ( stat($path) )[2] & 07777, $output ) unless $^O eq 'MSWin32';
            },
        },
        $source_abs,
    );
}

my $all = sub {1};
for my $directory (qw(bin lib)) {
    copy_tree(
        File::Spec->catdir( $perl_prefix, $directory ),
        File::Spec->catdir( $destination, 'runtime', $directory ),
        $all,
    );
}

# Strawberry Perl keeps compiler-runtime DLLs beside, rather than inside, its
# Perl prefix. Keeping them beside perl.exe makes XS modules self-contained.
if ( defined $compiler_bin && -d $compiler_bin ) {
    for my $dll ( glob File::Spec->catfile( $compiler_bin, '*.dll' ) ) {
        copy( $dll, File::Spec->catdir( $destination, 'runtime', 'bin' ) )
          or die "Cannot copy <$dll>: $!\n";
    }
}

copy_tree(
    File::Spec->catdir( $root, 'api', 'perl' ),
    File::Spec->catdir( $destination, 'api', 'perl' ),
    sub {
        my ($relative) = @_;
        return $relative !~ m{(?:^|[\\/])t(?:[\\/]|$)};
    },
);
copy_tree( File::Spec->catdir( $root, 'lib' ),
    File::Spec->catdir( $destination, 'lib' ), $all );
copy_tree(
    File::Spec->catdir( $root, 'share' ),
    File::Spec->catdir( $destination, 'share' ),
    sub {
        my ($relative) = @_;
        return $relative !~ m{(?:^|[\\/])ohdsi\.db\z}i;
    },
);
make_path( File::Spec->catdir( $destination, 'bin' ) );
copy( File::Spec->catfile( $root, 'bin', 'convert-pheno' ),
    File::Spec->catfile( $destination, 'bin', 'convert-pheno' ) )
  or die "Cannot copy convert-pheno: $!\n";
copy( File::Spec->catfile( $root, 'LICENSE' ),
    File::Spec->catfile( $destination, 'LICENSE' ) )
  or die "Cannot copy license: $!\n";

# Desktop examples remain the same synthetic inputs exercised by the test suite.
# Output fixtures and test programs are deliberately excluded from installers.
copy_tree(
    File::Spec->catdir( $root, 't' ),
    File::Spec->catdir( $destination, 't' ),
    sub {
        my ( $relative, $is_dir ) = @_;
        my @parts = File::Spec->splitdir($relative);
        return 1 if $is_dir && @parts <= 2;
        return 1 if grep { $_ eq 'in' } @parts;
        return 1 if $relative =~ m{^fixtures[\\/]http-omop-request\.json\z};
        return 0;
    },
);

my $perl = File::Spec->catfile( $destination, 'runtime', 'bin',
    $^O eq 'MSWin32' ? 'perl.exe' : 'perl' );
die "Staged Perl executable is missing\n"
  unless -x $perl || ( $^O eq 'MSWin32' && -f $perl );

my $manifest = {
    format        => 'convert-pheno-desktop-engine',
    formatVersion => 1,
    perlVersion   => 0 + $],
    platform      => $^O,
};
open my $fh, '>:raw', File::Spec->catfile( $destination, 'engine-manifest.json' )
  or die "Cannot write engine manifest: $!\n";
print {$fh} JSON::PP->new->canonical->pretty->encode($manifest);
close $fh or die "Cannot close engine manifest: $!\n";

print "$destination\n";
