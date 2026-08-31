package Convert::Pheno::Source::CDISC::DatasetJSON;

use strict;
use warnings;

use File::ShareDir::ProjectDistDir qw(dist_dir);
use File::Spec::Functions qw(catfile);
use JSON::Validator;
use Storable qw(dclone);

use Convert::Pheno::CDISC::DefineXML qw(
  enrich_dataset_from_define
  load_define_catalog
);
use Convert::Pheno::CDISC::SDTM::Normalizer qw(
  derive_sdtm_entity_overrides
  normalize_sdtm_datasets
);
use Convert::Pheno::CDISC::SDTM::Terminology qw(prepare_sdtm_terminology);
use Convert::Pheno::IO::FileIO qw(read_json);
use Convert::Pheno::Mapping::Shared qw(get_info);
use Convert::Pheno::Source::Result;

my $SCHEMA_FILE =
  catfile( dist_dir('Convert-Pheno'), 'schema', 'dataset-json-1.1.json' );

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};

    my ( @datasets, @labels );
    if ( exists $converter->{data} ) {
        my $data = $converter->{data};
        @datasets = ref($data) eq 'ARRAY' ? @{$data} : ($data);
        @datasets = map { dclone($_) } @datasets;
        @labels   = map { 'in-memory dataset ' . ( $_ + 1 ) } 0 .. $#datasets;
    }
    else {
        my @files = @{ $converter->{in_files} || [] };
        push @files, $converter->{in_file}
          if !@files && defined $converter->{in_file};
        die "Dataset-JSON input requires at least one JSON file\n" unless @files;

        for my $file (@files) {
            push @datasets, read_json($file);
            push @labels,   $file;
        }
    }

    my $validator = JSON::Validator->new;
    $validator->schema( read_json($SCHEMA_FILE) );
    for my $index ( 0 .. $#datasets ) {
        my @errors = $validator->validate( $datasets[$index] );
        next unless @errors;
        die "Dataset-JSON schema validation failed for <$labels[$index]>:\n"
          . join( q{}, map { "  $_\n" } @errors );
    }

    if ( defined $converter->{define_xml} && length $converter->{define_xml} ) {
        my $catalog = load_define_catalog(
            $converter->{define_xml},
            "Define-XML <$converter->{define_xml}>",
        );
        for my $index ( 0 .. $#datasets ) {
            enrich_dataset_from_define(
                $datasets[$index],
                $catalog,
                "Dataset-JSON input <$labels[$index]>",
            );
        }
    }

    my $normalized = normalize_sdtm_datasets(
        \@datasets,
        \@labels,
        format_name   => 'Dataset-JSON',
        source_format => 'dataset-json',
        version_key   => 'datasetJSONVersion',
    );
    my $terminology = prepare_sdtm_terminology(
        $converter,
        $normalized->{metadata},
    );

    return Convert::Pheno::Source::Result->new(
        {
            data  => $normalized->{subjects},
            owned => 1,
            artifacts => {
                dataset_metadata            => $normalized->{metadata},
                subject_independent_domains => $normalized->{subject_independent},
                terminology_mapping         => $terminology->{mapping},
                source_terminology          => $terminology->{source_terms},
                terminology_requires_sqlite => $terminology->{requires_sqlite},
                derived_entity_overrides    => derive_sdtm_entity_overrides(
                    $converter,
                    $normalized->{metadata},
                    $normalized->{subject_independent},
                    format_label   => 'Dataset-JSON',
                    provenance_key => 'datasetJson',
                ),
            },
        }
    );
}

sub prepare {
    my ($self) = @_;
    my $converter = $self->{converter};
    return 1 if $converter->{dataset_json_input_prepared}
      && exists $converter->{data};

    $converter->{_dataset_json_source_data} = $converter->{data}
      if exists $converter->{data}
      && !exists $converter->{_dataset_json_source_data};
    $converter->{data} = $converter->{_dataset_json_source_data}
      if !exists $converter->{data}
      && exists $converter->{_dataset_json_source_data};

    my $source = $self->load;
    $source->apply_to($converter);
    $converter->{dataset_json_metadata} =
      $source->artifact('dataset_metadata');
    $converter->{dataset_json_subject_independent_domains} =
      $source->artifact('subject_independent_domains');
    $converter->{source_derived_entity_overrides} =
      $source->artifact('derived_entity_overrides') || {};
    $converter->{sdtm_terminology_mapping} =
      $source->artifact('terminology_mapping') || {};
    $converter->{sdtm_source_terms} =
      $source->artifact('source_terminology') || {};
    $converter->{terminology_lookup_required} =
      $source->artifact('terminology_requires_sqlite') ? 1 : 0;
    $converter->{convertPheno} ||= get_info($converter);
    $converter->{dataset_json_input_prepared} = 1;
    return 1;
}

1;
