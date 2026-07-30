package Convert::Pheno::Source;

use strict;
use warnings;

use Exporter 'import';

use Convert::Pheno::Source::CDISC::ODM;
use Convert::Pheno::Source::OMOP;
use Convert::Pheno::Source::OpenEHR;
use Convert::Pheno::Source::Structured;
use Convert::Pheno::Source::Tabular;

our @EXPORT_OK = qw(source_adapter);

sub source_adapter {
    my ( $converter, $format ) = @_;

    return Convert::Pheno::Source::Structured->new($converter)
      if $format eq 'beacon' || $format eq 'pxf';
    return Convert::Pheno::Source::Tabular->new( $converter, kind => 'csv' )
      if $format eq 'csv';
    return Convert::Pheno::Source::Tabular->new( $converter, kind => 'redcap' )
      if $format eq 'redcap';
    # Keep CDISC encodings behind format-specific adapters. Dataset-JSON can
    # later be added as a sibling that returns the same Source::Result shape.
    return Convert::Pheno::Source::CDISC::ODM->new($converter)
      if $format eq 'cdisc';
    return Convert::Pheno::Source::OpenEHR->new($converter)
      if $format eq 'openehr';
    return Convert::Pheno::Source::OMOP->new($converter)
      if $format eq 'omop';

    die "No source adapter is registered for <$format>\n";
}

1;
