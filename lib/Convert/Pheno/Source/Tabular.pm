package Convert::Pheno::Source::Tabular;

use strict;
use warnings;

use Convert::Pheno::BFF::DerivedEntities qw(mapping_entity_overrides);
use Convert::Pheno::IO::CSVHandler qw(
  get_headers
  read_csv
  read_mapping_file
  read_redcap_dict_file
);
use Convert::Pheno::Mapping::Compiler qw(compile_mapping);
use Convert::Pheno::Mapping::Shared qw(get_info get_metaData);
use Convert::Pheno::Source::Result;

sub new {
    my ( $class, $converter, %arg ) = @_;
    return bless {
        converter => $converter,
        kind      => $arg{kind} || 'csv',
    }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};
    my $mapping = read_mapping_file(
        {
            mapping_file         => $converter->{mapping_file},
            self_validate_schema => $converter->{self_validate_schema},
            schema_file          => $converter->{schema_file},
        }
    );

    my $data = read_csv(
        {
            in             => $converter->{in_file},
            sep            => $converter->{sep},
            coerce_numbers => 0,
        }
    );

    my %artifacts = ( mapping => $mapping );
    $artifacts{redcap_dictionary} = read_redcap_dict_file(
        { redcap_dictionary => $converter->{redcap_dictionary} }
      )
      if $self->{kind} eq 'redcap';

    $artifacts{entity_mapping} = compile_mapping(
        $mapping,
        source_profile => $self->{kind},
        headers        => get_headers($data),
    );

    return Convert::Pheno::Source::Result->new(
        {
            data      => $data,
            owned     => 1,
            artifacts => \%artifacts,
        }
    );
}

sub prepare {
    my ($self) = @_;
    my $converter = $self->{converter};
    return 1 if exists $converter->{data}
      && exists $converter->{data_mapping_file};

    my $source = $self->load;
    $source->apply_to($converter);
    $converter->{data_redcap_dict} = $source->artifact('redcap_dictionary')
      if defined $source->artifact('redcap_dictionary');
    $converter->{data_mapping_file} = $source->artifact('entity_mapping');
    $converter->{metaData}          = get_metaData($converter);
    $converter->{convertPheno}      = get_info($converter);
    $converter->{mapping_file_derived_entity_overrides} =
      mapping_entity_overrides( $source->artifact('mapping') );
    return 1;
}

1;
