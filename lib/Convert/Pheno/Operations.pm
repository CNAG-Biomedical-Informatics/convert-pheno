package Convert::Pheno::Operations;

use strict;
use warnings;

use Exporter 'import';
use File::ShareDir::ProjectDistDir qw(dist_dir);
use File::Spec::Functions qw(catfile);
use JSON::XS qw(decode_json);
use Path::Tiny qw(path);
use Storable qw(dclone);

our @EXPORT_OK = qw(
  conversion_spec
  http_request_fields
  is_http_conversion
  is_public_conversion
  public_conversions
);

my $registry_file =
  catfile( dist_dir('Convert-Pheno'), 'schema', 'public-conversions.json' );
my $registry = decode_json( path($registry_file)->slurp_raw );
die "Public conversion registry <$registry_file> must contain an object\n"
  unless ref($registry) eq 'HASH';
die "Public conversion registry <$registry_file> has an unsupported schema version\n"
  unless $registry->{schema_version} && $registry->{schema_version} == 1;
die "Public conversion registry <$registry_file> must define conversions\n"
  unless ref( $registry->{conversions} ) eq 'HASH';
die "Public conversion registry <$registry_file> must define HTTP request fields\n"
  unless ref( $registry->{http_request_fields} ) eq 'HASH';

my %PUBLIC_CONVERSION = %{ $registry->{conversions} };

for my $name ( keys %PUBLIC_CONVERSION ) {
    my $spec = $PUBLIC_CONVERSION{$name};
    die "Conversion <$name> must contain an object specification\n"
      unless ref($spec) eq 'HASH';

    for my $field (qw(source target operation pipeline resources entities streaming http_enabled)) {
        die "Conversion <$name> is missing registry field <$field>\n"
          unless exists $spec->{$field};
    }

    die "Conversion <$name> has an invalid operation type\n"
      unless $spec->{operation} =~ /\A(?:bundle|direct|pipeline)\z/;
    die "Conversion <$name> must define a non-empty pipeline\n"
      unless ref( $spec->{pipeline} ) eq 'ARRAY' && @{ $spec->{pipeline} };
    die "Conversion <$name> must define SQLite resource requirements\n"
      unless ref( $spec->{resources} ) eq 'HASH'
      && exists $spec->{resources}{sqlite};
    die "Conversion <$name> must define entity capabilities\n"
      unless ref( $spec->{entities} ) eq 'HASH'
      && ref( $spec->{entities}{default} ) eq 'ARRAY'
      && ref( $spec->{entities}{supported} ) eq 'ARRAY';
}

for my $section (qw(input output options)) {
    die "HTTP request registry section <$section> must contain an array\n"
      unless ref( $registry->{http_request_fields}{$section} ) eq 'ARRAY';
}

for my $name ( keys %PUBLIC_CONVERSION ) {
    for my $stage ( @{ $PUBLIC_CONVERSION{$name}{pipeline} } ) {
        die "Conversion <$name> references unknown pipeline stage <$stage>\n"
          unless exists $PUBLIC_CONVERSION{$stage};
        die "Conversion <$name> references compound pipeline stage <$stage>\n"
          if $PUBLIC_CONVERSION{$stage}{operation} eq 'pipeline';
    }
}

sub is_public_conversion {
    my ($conversion) = @_;
    return 0 unless defined $conversion && !ref($conversion);
    return exists $PUBLIC_CONVERSION{$conversion} ? 1 : 0;
}

sub public_conversions {
    return [ sort keys %PUBLIC_CONVERSION ];
}

sub conversion_spec {
    my ($conversion) = @_;
    return unless is_public_conversion($conversion);

    my $spec = dclone( $PUBLIC_CONVERSION{$conversion} );
    $spec->{name} = $conversion;
    return $spec;
}

sub is_http_conversion {
    my ($conversion) = @_;
    return 0 unless is_public_conversion($conversion);
    return $PUBLIC_CONVERSION{$conversion}{http_enabled} ? 1 : 0;
}

sub http_request_fields {
    return dclone( $registry->{http_request_fields} );
}

1;
