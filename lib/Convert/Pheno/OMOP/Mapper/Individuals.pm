package Convert::Pheno::OMOP::Mapper::Individuals;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use Convert::Pheno::OMOP::ToBFF::Individuals qw(map_participant);

our @EXPORT_OK = qw(map_participant);

1;
