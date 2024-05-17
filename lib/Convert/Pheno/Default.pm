package Convert::Pheno::Default;

use strict;
use warnings;
use Hash::Util 'lock_hash';
use Exporter 'import';
our @EXPORT_OK = qw(get_defaults);

# Define your default values
my %DEFAULT = (
    ontology      => { id => 'NCIT:NA0000', label => 'NA' },
    date          => '1900-01-01',
    duration      => 'P999Y',
    duration_OMOP => 'P0Y',
    value         => -1,
    age           => { age => { iso8601duration => 'P999Y' } },
    timestamp     => '1900-01-01T00:00:00Z',
);

$DEFAULT{iso8601duration} = { iso8601duration => $DEFAULT{duration} };
$DEFAULT{quantity}        = {
    unit  => $DEFAULT{ontology},
    value => $DEFAULT{value}
};

# Lock the hash to make it read-only
lock_hash(%DEFAULT);

# Function to get a reference to the locked default values
sub get_defaults {
    return \%DEFAULT;
}

1;
