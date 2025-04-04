package Convert::Pheno::Default;

use strict;
use warnings;
use Hash::Util qw(lock_hash_recurse);
use Exporter 'import';
our @EXPORT_OK = qw(get_defaults);

# Define your default values
my %DEFAULT = (
    ontology_term => { id => 'NCIT:C126101', label => 'Not Available' },
    date          => '1900-01-01',
    duration      => 'P999Y',
    duration_OMOP => 'P0Y',
    value         => -1,
    age           => { age => { iso8601duration => 'P999Y' } },
    timestamp     => '1900-01-01T00:00:00Z',
    year          => 1900,
    concept_id    => 0
);

$DEFAULT{iso8601duration} = { iso8601duration => $DEFAULT{duration} };
$DEFAULT{interval} =
  { start => $DEFAULT{timestamp}, end => $DEFAULT{timestamp} };
$DEFAULT{referenceRange} =
  { low => -1, high => -1, unit => $DEFAULT{ontology_term} };
$DEFAULT{quantity} = {
    unit           => $DEFAULT{ontology_term},
    value          => $DEFAULT{value},
    referenceRange => $DEFAULT{referenceRange}
};

# Lock the hash recursively to make it read-only
lock_hash_recurse(%DEFAULT);

# Function to get a reference to the locked default values
sub get_defaults {
    return \%DEFAULT;
}

1;
