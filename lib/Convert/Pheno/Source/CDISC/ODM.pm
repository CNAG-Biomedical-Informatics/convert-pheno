package Convert::Pheno::Source::CDISC::ODM;

use strict;
use warnings;

use Path::Tiny qw(path);
use XML::Fast qw(xml2hash);

use Convert::Pheno::CDISC::ODM qw(parse_odm_records);
use Convert::Pheno::CDISC::ODM::Detector qw(detect_odm_document);
use Convert::Pheno::CDISC::ODM::Metadata;
use Convert::Pheno::IO::CSVHandler qw(
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
    my $descriptor = detect_odm_document($odm);
    my $mapping = read_mapping_file(
        {
            mapping_file         => $converter->{mapping_file},
            self_validate_schema => $converter->{self_validate_schema},
            schema_file          => $converter->{schema_file},
        }
    );

    my ( $redcap_dictionary, $metadata_catalog );
    if ( $descriptor->{recordProfile} eq 'redcap' ) {
        die "REDCap-origin CDISC-ODM input requires --redcap-dictionary <file>\n"
          unless defined $converter->{redcap_dictionary}
          && length $converter->{redcap_dictionary};
        $redcap_dictionary = read_redcap_dict_file(
            { redcap_dictionary => $converter->{redcap_dictionary} }
        );
    }
    else {
        die "--redcap-dictionary is only valid for REDCap-origin CDISC-ODM input\n"
          if defined $converter->{redcap_dictionary}
          && length $converter->{redcap_dictionary};
        $metadata_catalog = Convert::Pheno::CDISC::ODM::Metadata->from_document(
            $descriptor
        );
    }

    my $data = parse_odm_records(
        $descriptor,
        metadata         => $redcap_dictionary,
        metadata_catalog => $metadata_catalog,
    );
    my $compiled_mapping = compile_mapping(
        $mapping,
        source_profile => 'cdisc-odm',
        record_profile => $descriptor->{recordProfile},
        headers        => _record_headers($data),
    );

    my %artifacts = (
        mapping        => $mapping,
        entity_mapping => $compiled_mapping,
        odm_descriptor => $descriptor,
    );
    $artifacts{redcap_dictionary} = $redcap_dictionary
      if defined $redcap_dictionary;

    return Convert::Pheno::Source::Result->new(
        {
            data      => $data,
            owned     => 1,
            artifacts => \%artifacts,
        }
    );
}

sub _record_headers {
    my ($records) = @_;
    my ( @headers, %seen );
    for my $record ( @{$records} ) {
        for my $header ( @{ $record->headers } ) {
            push @headers, $header unless $seen{$header}++;
        }
    }
    return \@headers;
}

1;
