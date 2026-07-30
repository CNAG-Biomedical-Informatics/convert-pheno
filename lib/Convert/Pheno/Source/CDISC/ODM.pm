package Convert::Pheno::Source::CDISC::ODM;

use strict;
use warnings;

use Path::Tiny qw(path);
use XML::Fast qw(xml2hash);

use Convert::Pheno::CDISC::ODM qw(odm2redcap);
use Convert::Pheno::IO::CSVHandler qw(
  get_headers
  read_mapping_file
  read_redcap_dict_file
);
use Convert::Pheno::Mapping::Compiler qw(compile_mapping);
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
    my $data = odm2redcap($odm);
    my $compiled_mapping = compile_mapping(
        $mapping,
        source_profile => 'cdisc-odm',
        headers        => get_headers($data),
    );

    return Convert::Pheno::Source::Result->new(
        {
            data  => $data,
            owned => 1,
            artifacts => {
                mapping        => $mapping,
                entity_mapping => $compiled_mapping,
                redcap_dictionary => read_redcap_dict_file(
                    { redcap_dictionary => $converter->{redcap_dictionary} }
                ),
            },
        }
    );
}

1;
