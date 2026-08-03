package Convert::Pheno::DB::Bundle;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use File::Spec::Functions qw(catdir catfile);
use JSON::XS qw(decode_json);

our @EXPORT_OK = qw(
  bundle_manifest
  bundled_database_path
  current_bundle_dir
);

use constant BUNDLE_FORMAT         => 'convert-pheno-sqlite-bundle';
use constant BUNDLE_FORMAT_VERSION => 1;

sub bundle_manifest {
    my ($share_dir) = @_;
    die "Database bundle lookup requires the distribution share directory\n"
      unless defined $share_dir && length $share_dir;

    my $manifest_file = catfile( $share_dir, 'db', 'manifest.json' );
    die "Database bundle manifest not found: $manifest_file\n"
      unless -f $manifest_file;

    open my $fh, '<:raw', $manifest_file;
    local $/;
    my $json = <$fh>;
    close $fh;

    my $manifest = eval { decode_json($json) };
    die "Invalid database bundle manifest <$manifest_file>: $@"
      unless ref $manifest eq 'HASH';

    die "Unsupported database bundle format in <$manifest_file>\n"
      unless ( $manifest->{format} // q{} ) eq BUNDLE_FORMAT
      && ( $manifest->{formatVersion} // 0 ) == BUNDLE_FORMAT_VERSION;

    my $current = $manifest->{currentBundle} // q{};
    die "Database bundle manifest <$manifest_file> has no valid currentBundle\n"
      unless $current =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;

    if ( defined $manifest->{bundleVersion}
        && $manifest->{bundleVersion} ne $current )
    {
        die "Database bundle manifest <$manifest_file> points to <$current> "
          . "but describes <$manifest->{bundleVersion}>\n";
    }

    die "Database bundle manifest <$manifest_file> has no databases object\n"
      unless ref $manifest->{databases} eq 'HASH';

    return $manifest;
}

sub _current_bundle_dir {
    my ( $share_dir, $manifest ) = @_;
    my $directory =
      catdir( $share_dir, 'db', $manifest->{currentBundle} );

    die "Current database bundle directory not found: $directory\n"
      unless -d $directory;

    return $directory;
}

sub current_bundle_dir {
    my ($share_dir) = @_;
    return _current_bundle_dir( $share_dir, bundle_manifest($share_dir) );
}

sub bundled_database_path {
    my ( $share_dir, $ontology ) = @_;
    die "Database bundle lookup requires an ontology name\n"
      unless defined $ontology && $ontology =~ /\A[A-Za-z0-9_]+\z/;

    my $manifest = bundle_manifest($share_dir);
    my $entry    = $manifest->{databases}{$ontology};
    die "Database <$ontology> is not declared in the current bundle\n"
      unless ref $entry eq 'HASH';

    my $filename = $entry->{file} // q{};
    die "Database <$ontology> has an invalid bundle filename\n"
      unless $filename =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;

    return catfile( _current_bundle_dir( $share_dir, $manifest ), $filename );
}

1;
