use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use DBI;
use Convert::Pheno::HTTP::Service qw(lookup_omop_concept);

my $dir = tempdir(CLEANUP => 1);
local $ENV{CONVERT_PHENO_OHDSI_DB_DIR} = $dir;
is(lookup_omop_concept(12)->{state}, 'unavailable', 'missing vocabulary is explicit');
my $dbh = DBI->connect("dbi:SQLite:dbname=$dir/ohdsi.db", '', '', {RaiseError => 1});
$dbh->do('CREATE TABLE OHDSI_table (concept_id INTEGER, label TEXT, id TEXT, domain_id TEXT)');
$dbh->do('CREATE INDEX concept_lookup ON OHDSI_table(concept_id)');
$dbh->do('INSERT INTO OHDSI_table VALUES (12, ?, ?, ?)', undef, 'Synthetic measurement', 'TEST:12', 'Measurement');
my $before = $dbh->selectall_arrayref('SELECT * FROM OHDSI_table');
my $result = lookup_omop_concept(12);
is($result->{state}, 'found', 'exact identifier is found');
is($result->{concept}{label}, 'Synthetic measurement', 'canonical database label is returned');
is($result->{concept}{domain_id}, 'Measurement', 'available metadata is returned');
ok(!exists $result->{concept}{standard_concept}, 'missing metadata is not invented');
is(lookup_omop_concept(13)->{state}, 'not_found', 'no approximate identifier matching');
is(lookup_omop_concept(0)->{state}, 'not_assigned', 'zero has OMOP-specific explanation');
for my $invalid ('12 OR 1=1', -1, '1.5', 2147483648, {}, undef) {
    my $ok = eval { lookup_omop_concept($invalid); 1 };
    ok(!$ok, 'invalid identifiers are rejected');
}
is_deeply($dbh->selectall_arrayref('SELECT * FROM OHDSI_table'), $before, 'inspection leaves records unchanged');
$dbh->do('INSERT INTO OHDSI_table SELECT * FROM OHDSI_table');
is(lookup_omop_concept(12)->{state}, 'unavailable', 'ambiguous identifiers are not silently selected');
$dbh->disconnect;
done_testing;
