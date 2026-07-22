package Convert::Pheno::Operations;

use strict;
use warnings;

use Exporter 'import';
use File::ShareDir::ProjectDistDir qw(dist_dir);
use File::Spec::Functions qw(catfile);
use JSON::XS qw(decode_json);
use Path::Tiny qw(path);

our @EXPORT_OK = qw(is_public_conversion public_conversions);

my $registry_file =
  catfile( dist_dir('Convert-Pheno'), 'schema', 'public-conversions.json' );
my $registry = decode_json( path($registry_file)->slurp_raw );
die "Public conversion registry <$registry_file> must contain an array\n"
  unless ref($registry) eq 'ARRAY';

my %PUBLIC_CONVERSION = map { $_ => 1 } @{$registry};

sub is_public_conversion {
    my ($conversion) = @_;
    return 0 unless defined $conversion && !ref($conversion);
    return exists $PUBLIC_CONVERSION{$conversion} ? 1 : 0;
}

sub public_conversions {
    return [ sort keys %PUBLIC_CONVERSION ];
}

1;
