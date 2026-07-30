package Convert::Pheno::Source::Tabular;

use strict;
use warnings;

use Convert::Pheno::IO::CSVHandler qw(
  read_csv
  read_mapping_file
  read_redcap_dict_file
  select_mapping_entity
);
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

    my %artifacts = (
        mapping        => $mapping,
        entity_mapping => select_mapping_entity( $mapping, 'individuals' ),
    );
    $artifacts{redcap_dictionary} = read_redcap_dict_file(
        { redcap_dictionary => $converter->{redcap_dictionary} }
      )
      if $self->{kind} eq 'redcap';

    return Convert::Pheno::Source::Result->new(
        {
            data => read_csv(
                {
                    in             => $converter->{in_file},
                    sep            => $converter->{sep},
                    coerce_numbers => 0,
                }
            ),
            owned     => 1,
            artifacts => \%artifacts,
        }
    );
}

1;
