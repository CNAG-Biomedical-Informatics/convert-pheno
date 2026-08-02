package Convert::Pheno::CDISC::ODM;

use strict;
use warnings;

use Exporter 'import';

use Convert::Pheno::CDISC::ODM::V1;
use Convert::Pheno::CDISC::ODM::V2;
use Convert::Pheno::Tabular::ToBFF qw(map_tabular_individual);

our @EXPORT_OK = qw(do_cdiscodm2bff parse_odm_records);

sub do_cdiscodm2bff {
    my ( $self, $participant ) = @_;
    return map_tabular_individual( $self, $participant );
}

sub parse_odm_records {
    my ( $descriptor, %arg ) = @_;
    my %adapter = (
        v1 => 'Convert::Pheno::CDISC::ODM::V1',
        v2 => 'Convert::Pheno::CDISC::ODM::V2',
    );
    my $class = $adapter{ $descriptor->{adapter} }
      or die "No CDISC-ODM adapter is available for <$descriptor->{adapter}>\n";
    return $class->parse_records( $descriptor, %arg );
}

1;
