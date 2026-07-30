package Convert::Pheno::Source::CDISC::ODM;

use strict;
use warnings;

use Path::Tiny qw(path);
use XML::Fast qw(xml2hash);

use Convert::Pheno::CDISC qw(cdisc2redcap);
use Convert::Pheno::IO::CSVHandler qw(
  read_mapping_file
  read_redcap_dict_file
  select_mapping_entity
);
use Convert::Pheno::Source::Result;

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};

    my $xml = path( $converter->{in_file} )->slurp_utf8;
    my $odm = xml2hash $xml, attr => '-', text => '~';
    my $mapping = read_mapping_file(
        {
            mapping_file         => $converter->{mapping_file},
            self_validate_schema => $converter->{self_validate_schema},
            schema_file          => $converter->{schema_file},
        }
    );

    return Convert::Pheno::Source::Result->new(
        {
            data  => cdisc2redcap($odm),
            owned => 1,
            artifacts => {
                mapping        => $mapping,
                entity_mapping => select_mapping_entity( $mapping, 'individuals' ),
                redcap_dictionary => read_redcap_dict_file(
                    { redcap_dictionary => $converter->{redcap_dictionary} }
                ),
            },
        }
    );
}

1;
