package Convert::Pheno::SQLite;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Carp qw(confess);
use DBI;
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use List::Util qw(any);
use Exporter 'import';
our @EXPORT =
  qw( $VERSION open_connections_SQLite close_connections_SQLite execute_query_SQLite);

my @sqlites = qw(ncit icd10 ohdsi);

########################
########################
#  SUBROUTINES FOR DB  #
########################
########################

sub open_connections_SQLite {

    my $self = shift;

    # Check flag ohdsi_db
    my @databases =
      defined $self->{ohdsi_db} ? @sqlites : grep { !m/ohdsi/ }
      @sqlites;    # global

    # Opening the DB once (instead that on each call) improves speed ~15%
    my $dbh;
    $dbh->{$_} = open_db_SQLite($_) for (@databases);

    # Add $dbh HANDLE to $self
    $self->{dbh} = $dbh;    # Dynamically adding attributes (setter)

    # Prepare the query once
    prepare_query_SQLite($self);

    return 1;
}

sub close_connections_SQLite {

    my $self = shift;
    my $dbh  = $self->{dbh};

    # Check flag ohdsi_db
    my @databases =
      defined $self->{ohdsi_db} ? @sqlites : grep { !m/ohdsi/ }
      @sqlites;    # global
    close_db_SQLite( $dbh->{$_} ) for (@databases);
    return 1;
}

sub open_db_SQLite {

    my $ontology = shift;
    my $dbfile   = catfile( $Convert::Pheno::Bin, '../db', "$ontology.db" );
    confess "Sorry we could not find <$dbfile> file" unless -f $dbfile;
    my $user   = '';
    my $passwd = '';
    my $dsn    = "dbi:SQLite:dbname=$dbfile";
    my $dbh    = DBI->connect(
        $dsn, $user, $passwd,
        {
            PrintError       => 0,
            RaiseError       => 1,
            AutoCommit       => 1,
            FetchHashKeyName => 'NAME_lc',
        }
    );

    return $dbh;
}

sub close_db_SQLite {

    my $dbh = shift;
    $dbh->disconnect();
    return 1;
}

sub prepare_query_SQLite {

    my $self = shift;

    ###############
    # EXPLANATION #
    ###############
#
# Even though we did not gain a lot of speed (~15%), we decided to do the "prepare step" once, instead of on each query.
# Then, if we want to search in a different column than 'label' we also need to create that $sth
# To solve that we have created a nested sth->{ncit}{label}, sth->{icd10}{label}, sth->{ohdsi}{concept_id} and sth->{ohdsi}{label}
# On top of that, we add the "match" type, so that we can have other matches in the future if needed
# NB: In principle, is is possible to change the "prepare" during queries but we must reverte it back to default after using it
# We prefer using ncit/icd10 as they're small and fast

    # Check flag ohdsi_db
    my @databases =
      defined $self->{ohdsi_db} ? @sqlites : grep { !m/ohdsi/ }
      @sqlites;    # global

    # NB1:
    # dbh = "Database Handle"
    # sth = "Statement Handle"

# NB2:
#     *<ncit.db> and <icd10.db> were pre-processed to have "id" and "label" columns only
#       label [0]
#       id    [1]
#
#     * <ohdsi.db> consists of 4 columns:
#       concept_id    => concept_id    [0]
#       concept_name  => label         [1]
#       vocabulary_id => vocabulary_id [2]
#       vocabulary_id => id            [4]

    for my $match ('exact_match') {
        for my $ontology (@databases) {    #global
            for my $column ( 'label', 'concept_id' ) {
                next
                  if ( $column eq 'concept_id' && any { /^$ontology$/ }
                    ( 'ncit', 'icd10' ) );
                my $db         = uc($ontology) . '_table';
                my $dbh        = $self->{dbh}{$ontology};
                my %query_type = (
                    contains =>
qq(SELECT * FROM $db WHERE $column LIKE '%' || ? || '%' COLLATE NOCASE),
                    contains_word =>
qq(SELECT * FROM $db WHERE $column LIKE '% ' || ? || ' %' COLLATE NOCASE),
                    exact_match =>
                      qq(SELECT * FROM $db WHERE $column = ? COLLATE NOCASE),
                    begins_with =>
qq(SELECT * FROM $db WHERE $column LIKE ? || '%' COLLATE NOCASE)
                );

                # Prepare the query
                my $sth = $dbh->prepare(<<SQL);
$query_type{$match}
SQL

                # Autovivification of $self->{sth}{$ontology}{$column}{$match}
                $self->{sth}{$ontology}{$column}{$match} =
                  $sth;    # Dynamically adding nested attributes (setter)
            }
        }
    }

    #print Dumper $self and die;
    return 1;
}

sub execute_query_SQLite {

    my $arg      = shift;
    my $sth      = $arg->{sth};
    my $query    = $arg->{query};
    my $ontology = $arg->{ontology};
    my $match    = $arg->{match};

    # Excute query
    $sth->execute($query);

    # Parse query
    $ontology = uc($ontology);
    my $id    = $ontology . ':NA0000';
    my $label = 'NA';
    while ( my $row = $sth->fetchrow_arrayref ) {
        if ( $ontology ne 'OHDSI' ) {
            $id    = $ontology . ':' . $row->[1];
            $label = $row->[0];
        }
        else {
            $id    = $row->[2] . ':' . $row->[0];
            $label = $row->[1];
        }
        last
          if $match eq 'exact_match'; # Note that sometimes we get more than one
    }
    $sth->finish();

    return ( $id, $label );
}
1;
