package Convert::Pheno::IO::Atomic;

use strict;
use warnings;

use Exporter 'import';
use File::Basename qw(dirname);
use File::Temp qw(tempfile);

our @EXPORT_OK = qw(
  commit_staged_path
  create_staged_path
  discard_staged_path
  write_atomically
);

sub create_staged_path {
    my ($target) = @_;
    die "Atomic output target is required\n"
      unless defined $target && length $target;

    my $suffix = $target =~ /(\.[A-Za-z0-9]+(?:\.gz)?)\z/ ? $1 : '.tmp';
    my ( $fh, $staged ) = tempfile(
        '.convert-pheno-XXXXXX',
        DIR    => dirname($target),
        SUFFIX => $suffix,
        UNLINK => 0,
    );
    close $fh or die "Could not close staged output <$staged>: $!\n";

    my $mode = 0666 & ~umask();
    if ( -e $target ) {
        my @stat = stat $target;
        $mode = $stat[2] & 07777 if @stat;
    }
    unless ( chmod $mode, $staged ) {
        my $error = $!;
        unlink $staged;
        die "Could not set permissions on staged output <$staged>: $error\n";
    }
    return $staged;
}

sub discard_staged_path {
    my ($staged) = @_;
    return 1 unless defined $staged && -e $staged;
    unlink $staged or die "Could not remove staged output <$staged>: $!\n";
    return 1;
}

sub commit_staged_path {
    my ( $staged, $target ) = @_;
    die "Staged output file is missing\n"
      unless defined $staged && -f $staged;

    return 1 if rename $staged, $target;
    my $rename_error = $!;

    # Windows cannot replace an existing path with rename(). Keep a recoverable
    # backup until the fully written staged file has taken its place.
    if ( $^O eq 'MSWin32' && -e $target ) {
        my $backup = create_staged_path($target);
        unlink $backup
          or die "Could not prepare backup path for <$target>: $!\n";
        rename $target, $backup
          or die "Could not preserve existing output <$target>: $!\n";

        if ( rename $staged, $target ) {
            warn "Could not remove output backup <$backup>: $!\n"
              unless unlink $backup;
            return 1;
        }

        my $replacement_error = $!;
        rename $backup, $target
          or die "Could not replace <$target> ($replacement_error) or restore it ($!)\n";
        die "Could not replace output <$target>: $replacement_error\n";
    }

    die "Could not replace output <$target>: $rename_error\n";
}

sub write_atomically {
    my ( $target, $writer ) = @_;
    die "Atomic output writer must be a code reference\n"
      unless ref($writer) eq 'CODE';

    my $staged = create_staged_path($target);
    my $ok = eval {
        $writer->($staged);
        1;
    };
    unless ($ok) {
        my $error = $@;
        discard_staged_path($staged);
        die $error;
    }

    my $committed = eval {
        commit_staged_path( $staged, $target );
        1;
    };
    unless ($committed) {
        my $error = $@;
        discard_staged_path($staged);
        die $error;
    }

    return 1;
}

1;
