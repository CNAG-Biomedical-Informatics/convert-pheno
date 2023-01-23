package Convert::Pheno::SQLite;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Carp    qw(confess);
use DBI;
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use List::Util qw(any);
use Text::Similarity::Overlaps;
use Exporter 'import';
our @EXPORT =
  qw( $VERSION open_connections_SQLite close_connections_SQLite get_ontology);

my @sqlites = qw(ncit icd10 ohdsi);
my @matches = qw(exact_match contains);
use constant DEVEL_MODE => 1;

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

    # Connect to the database
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

    for my $match (@matches) {
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
                my $sth = $dbh->prepare( $query_type{$match} );

                # Autovivification of $self->{sth}{$ontology}{$column}{$match}
                $self->{sth}{$ontology}{$column}{$match} =
                  $sth;    # Dynamically adding nested attributes (setter)
            }
        }
    }

    #print Dumper $self and die;
    return 1;
}

sub get_ontology {

    ###############
    # START QUERY #
    ###############

    my $arg      = shift;
    my $ontology = $arg->{ontology};
    my $sth_ref  = $arg->{sth_ref};    #it contains hashref
    my $query    = $arg->{query};
    my $match    = $arg->{match};

    # A) 'exact'
    # - exact_match
    # B) Mixed queries:
    #    1 - exact_match
    #      if we don't get results
    #    2 - contains
    #       for which we rank by similarity w/ Text:Similarity

    my $default_id    = uc($ontology) . ':NA0000';
    my $default_label = 'NA';

    # exact_match
    my ( $id, $label ) = execute_query_SQLite(
        {
            sth      => $sth_ref->{exact_match},    # IMPORTANT STEP
            query    => $query,
            ontology => $ontology,
            match    => 'exact_match'
        }
    );

    # mixed
    if ( $match eq 'mixed' && ( !defined $id && !defined $label ) ) {
        ( $id, $label ) = execute_query_SQLite(
            {
                sth      => $sth_ref->{contains},    # IMPORTANT STEP
                query    => $query,
                ontology => $ontology,
                match    => 'contains'
            }
        );
    }

    # Set defaults if undef
    $id    = $id    // $default_id;
    $label = $label // $default_label;

    #############
    # END QUERY #
    #############

    return ( $id, $label );

}

sub execute_query_SQLite {

    my $arg                       = shift;
    my $sth                       = $arg->{sth};
    my $query                     = $arg->{query};
    my $ontology                  = uc( $arg->{ontology} );
    my $match                     = $arg->{match};
    my $id_row                    = $ontology ne 'OHDSI' ? 1 : 0;
    my $label_row                 = $ontology ne 'OHDSI' ? 0 : 1;
    my $min_text_similarity_score = $arg->{min_text_similarity_score};

    # Excute query
    $sth->execute($query);

    my $id    = undef;
    my $label = undef;

    if ( $match eq 'exact_match' ) {

        # Parse query
        while ( my $row = $sth->fetchrow_arrayref ) {
            $id =
                $ontology ne 'OHDSI'
              ? $ontology . ':' . $row->[$id_row]
              : $row->[2] . ':' . $row->[$id_row];
            $label = $row->[$label_row];
            last; # Note that sometimes we get more than one (they're discarded)
        }
    }
    else {

        # Parse query w/ sub
        ( $id, $label ) = text_similarity(
            {
                sth                       => $sth,
                query                     => $query,
                ontology                  => $ontology,
                id_row                    => $id_row,
                label_row                 => $label_row,
                min_text_similarity_score => $min_text_similarity_score
            }
        );
    }

    # Finish $sth
    $sth->finish();

    # We return results
    return ( $id, $label );
}

sub text_similarity {

    my $arg       = shift;
    my $sth       = $arg->{sth};
    my $query     = $arg->{query};
    my $ontology  = $arg->{ontology};
    my $id_row    = $arg->{id_row};
    my $label_row = $arg->{label_row};
    my $min_score = $arg->{min_text_similarity_score};

    # Create a new Text::Similarity object
    my $ts = Text::Similarity::Overlaps->new();

    # Fetch the query results
    my $data = ();
    while ( my $row = $sth->fetchrow_arrayref() ) {
        $data->{ $row->[$label_row] } = {
            id => $ontology ne 'OHDSI'
            ? $ontology . ':' . $row->[$label_row]
            : $row->[2] . ':' . $row->[$label_row],
            label => $row->[$label_row],
            score => $ts->getSimilarityStrings( $query, $row->[$label_row] ),
            query => $query
        };
    }

    # Sort the results by similarity score
    #$Data::Dumper::Sortkeys = 1 ;
    my @sorted_keys =
      sort { $data->{$b}{score} <=> $data->{$a}{score} } keys %{$data};

    #print Dumper $data         if DEVEL_MODE;
    #print "$query\n"           if DEVEL_MODE;
    #print Dumper \@sorted_keys if DEVEL_MODE;

    # We have a threshold to assign a result as valid
    my @valid_keys = grep { $data->{$_}{score} >= $min_score } @sorted_keys;

    print Dumper \@valid_keys if DEVEL_MODE;

    # Return 1st element if present
    return $valid_keys[0]
      ? ( $data->{ $valid_keys[0] }{id}, $data->{ $valid_keys[0] }{label} )
      : ( undef, undef );

}
1;
