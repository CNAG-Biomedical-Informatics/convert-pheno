package Convert::Pheno::Mapping::Metadata;

use strict;
use warnings;

use Exporter 'import';
use File::ShareDir::ProjectDistDir qw(dist_dir);
use File::Spec::Functions qw(catfile);

use Convert::Pheno::BFF::DerivedEntities qw(mapping_entity_overrides);
use Convert::Pheno::IO::CSVHandler qw(read_mapping_file);
use Convert::Pheno::Mapping::Compiler qw(
  compile_mapping
  is_metadata_profile
);

our @EXPORT_OK = qw(
  apply_metadata_mapping
  load_metadata_mapping
);

sub load_metadata_mapping {
    my ( $converter, $profile ) = @_;
    return unless is_metadata_profile($profile);
    return
      unless defined $converter->{mapping_file}
      && length $converter->{mapping_file};

    my $schema_file = $converter->{schema_file}
      // catfile( dist_dir('Convert-Pheno'), 'schema', 'mapping-v2.json' );
    my $mapping = read_mapping_file(
        {
            mapping_file         => $converter->{mapping_file},
            self_validate_schema => $converter->{self_validate_schema} || 0,
            schema_file          => $schema_file,
        }
    );
    my $compiled = compile_mapping(
        $mapping,
        source_profile => $profile,
    );

    return mapping_entity_overrides($compiled);
}

sub apply_metadata_mapping {
    my ( $converter, $profile, $overrides ) = @_;
    return 1 unless is_metadata_profile($profile);

    # Source adapters may be reused by more than one route. Reset only the
    # mapping-derived layer; source-derived and explicit programmatic overrides
    # have their own precedence in DerivedEntities.
    delete $converter->{mapping_file_derived_entity_overrides};
    $converter->{mapping_file_derived_entity_overrides} = $overrides
      if defined $overrides;
    return 1;
}

1;
