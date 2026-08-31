package Convert::Pheno::CDISC::ODM::Parser;

use strict;
use warnings;

use Exporter 'import';

use Convert::Pheno::CDISC::ODM::V1;
use Convert::Pheno::CDISC::ODM::V2;

our @EXPORT_OK = qw(parse_odm_records);

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
