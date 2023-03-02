package Convert::Pheno::SQLite;

use strict;
use warnings;
use autodie;
use feature qw(say);
#use Carp    qw(confess);
use DBI;
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use Text::Similarity::Overlaps;
use Exporter 'import';
our @EXPORT =
  qw( $VERSION open_connections_SQLite close_connections_SQLite get_ontology);

my @sqlites = qw(ncit icd10 ohdsi cdisc);
my @matches = qw(exact_match full_text_search contains);
use constant DEVEL_MODE => 0;

########################
########################
#  SUBROUTINES FOR DB  #
########################
########################

sub open_connections_SQLite {

    my $self = shift;

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # Well open ALL databases once (instead that on each call), regardless if they user has selected them.
    # It imrpoves speed by 15%
    # The only exception is for <ohdsi> that is the larger and may interfere in timings

    # Only open ohdsi.db if $self->{ohdsi_db}
    my @databases =
      $self->{ohdsi_db} ? @sqlites : grep { !m/ohdsi/ } @sqlites;    # global

    # Open databases
    my $dbh;
    $dbh->{$_} = open_db_SQLite( $_, $self->{path_to_ohdsi_db} )
      for (@databases);

    # Add $dbh HANDLE to $self
    $self->{dbh} = $dbh;                                             # Dynamically adding attributes (setter)

    # Prepare the query once
    prepare_query_SQLite($self);

    return 1;
}

sub close_connections_SQLite {

    my $self = shift;
    my $dbh  = $self->{dbh};

    # Check flag ohdsi_db
    my @databases =
      $self->{ohdsi_db} ? @sqlites : grep { !m/ohdsi/ } @sqlites;    # global
    close_db_SQLite( $dbh->{$_} ) for (@databases);
    return 1;
}

sub open_db_SQLite {

    my ( $ontology, $path_to_ohdsi_db ) = @_;

    # Search file in two dirs, except for ($ontology eq 'ohdsi' && defined $path_to_ohdsi_db)
    my $filename = qq/$ontology.db/;
    my @dirs =
      ( $ontology eq 'ohdsi' && defined $path_to_ohdsi_db )
      ? $path_to_ohdsi_db
      : map { $Convert::Pheno::Bin . '/' . $_ } ( '../db', '../../db' );
    my $dbfile;
    foreach my $dir (@dirs) {
        $dbfile = catfile( $dir, $filename );
        if ( -e $dbfile ) {
            last;
        }
    }
    die "Sorry we could not find <$dbfile> file\n" unless -f $dbfile;

    # Connect to the database
    my $user   = '';
    my $passwd = '';
    my $dsn    = "dbi:SQLite:dbname=$dbfile";
    my $dbh    = DBI->connect(
        $dsn, $user, $passwd,

        # PRAGMAs
        {
            PrintError       => 0,
            RaiseError       => 1,
            ReadOnly         => 1,
            AutoCommit       => 1,
            FetchHashKeyName => 'NAME_lc',
        }
    );

    # These extra PRAGMAs are supposed to speed-up queries??
    $dbh->do("PRAGMA synchronous = OFF");
    $dbh->do("PRAGMA cache_size = 800000");

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
    # NB: In principle, is is possible to change the "prepare" during queries but we must revert it back to default after using it
    # We recommend using small db such as ncit/icd10 as they're fast

    # Check flag ohdsi_db
    my @databases =
      $self->{ohdsi_db} ? @sqlites : grep { !m/ohdsi/ } @sqlites;    # global

    # NB:
    # dbh = "Database Handle"
    # sth = "Statement Handle"

    for my $match (@matches) {
        for my $ontology (@databases) {    #global
            for my $column ( 'label', 'concept_id' ) {

                # We only need to open 'concept_id' in ohdsi
                next if ( $column eq 'concept_id' && $ontology ne 'ohdsi' );

                ##############################
                # Start building the queries #
                ##############################

                # NCIT_table or NCIT_fts depending on type of match
                my $db         = uc($ontology) . '_table';
                my $db_fts     = uc($ontology) . '_fts';
                my $dbh        = $self->{dbh}{$ontology};
                my %query_type = (

                    # Regular queries
                    contains =>
qq(SELECT * FROM $db WHERE $column LIKE '%' || ? || '%' COLLATE NOCASE)
                    ,    # NOT USED

                    #begins_with => qq(SELECT * FROM $db WHERE $column LIKE ? || '%' COLLATE NOCASE), # NOT USED
                    exact_match =>
                      qq(SELECT * FROM $db WHERE $column = ? COLLATE NOCASE),

                    # **********************
                    # *** IMPORTANT STEP ***
                    # **********************

                    # Full-text-search queries only on column <label> BUT IT CAN BE DONE ALL COLUMNS!!!!
                    # The speed of the FTS in $column == $db_fts
                    # FTS is 2x faster than 'contains'
                    # NOTE (Jan-2023): We don't check for misspelled words
                    #       --> TO DO - Tricky -->  https://www.sqlite.org/spellfix1.html
                    full_text_search =>
                      qq(SELECT * FROM $db_fts WHERE $column MATCH ?),    # SINGLE COLUMN
                                                                          #qq(SELECT * FROM $db_fts WHERE $db_fts MATCH ?), # ALL TABLE

                    # SOUNDEX using TABLE_fts but only on column <label>
                    # soundex     => qq(SELECT * FROM $db_fts WHERE SOUNDEX($column) = SOUNDEX(?)) # NOT USED
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

    my $arg                       = shift;
    my $ontology                  = $arg->{ontology};
    my $sth_column_ref            = $arg->{sth_column_ref};              #it contains hashref
    my $query                     = $arg->{query};
    my $column                    = $arg->{column};
    my $search                    = $arg->{search};
    my $text_similarity_method    = $arg->{text_similarity_method};
    my $min_text_similarity_score = $arg->{min_text_similarity_score};
    my $type_of_search            = 'full_text_search';                  # 'contains' and 'full_text_search'
                                                                         #say $type_of_search;
    say "QUERY <$query>" if DEVEL_MODE;

    # A) 'exact'
    # - exact_match
    # B) Mixed queries:
    #    1 - exact_match
    #      if we don't get results
    #    2 - contains
    #       for which we rank by similarity w/ Text:Similarity

    my $default_id    = uc($ontology) . ':NA0000';
    my $default_label = 'NA';

    # exact_match (always performed)
    my ( $id, $label ) = execute_query_SQLite(
        {
            sth                       => $sth_column_ref->{exact_match},    # IMPORTANT STEP
            query                     => $query,
            ontology                  => $ontology,
            match                     => 'exact_match',
            text_similarity_method    => $text_similarity_method,           # Not used here
            min_text_similarity_score => $min_text_similarity_score
        }
    );

    # mixed
    if ( $search eq 'mixed' && ( !defined $id && !defined $label ) ) {
        ( $id, $label ) = execute_query_SQLite(
            {
                sth                    => $sth_column_ref->{$type_of_search},  # IMPORTANT STEP
                query                  => $query,
                ontology               => $ontology,
                match                  => $type_of_search,
                text_similarity_method => $text_similarity_method,
                min_text_similarity_score => $min_text_similarity_score
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
    my $text_similarity_method    = $arg->{text_similarity_method};
    my $min_text_similarity_score = $arg->{min_text_similarity_score};
    my $ontology                  = $arg->{ontology};
    my $match                     = $arg->{match};

    #  Columns in DBs
    #     *<ncit.db>, <icd10.db> and <cdisc.db> were pre-processed to have "id" and "label" columns only
    #       label [0]
    #       id    [1]
    #
    #     * <ohdsi.db> consists of 4 columns:
    #       concept_name  => label         [0]
    #       concept_code  => id            [1]
    #       concept_id    => concept_id    [2]
    #       vocabulary_id => vocabulary_id [3]

    # Define a hash for column position on databases
    # We may encounter a situation where order of columns is different
    my $position = {};
    $position->{$_} = { label => 0, id => 1 } for (qw/ncit icd10 cdisc ohdsi/);
    my $id_column    = $position->{$ontology}{id};
    my $label_column = $position->{$ontology}{label};

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # full_text_search is supposed to be ONLY in text fields, but, for
    # whatever reaon the binding of parameters e.g, '2 - mild' (starts w/ number)
    # produce exceptions on SQLite. We'll be parsing them for ALL SEARCHES!!!

    # NB: Order matters in the changes below
    $query =~ s/^\d+\s+\-\s+//;                             # for ALL SEARCHES!!!
    $query =~ tr/_,-/ / if $match eq 'full_text_search';    # FTS
    $query =~ tr/ //s;                                      # remove duplicate spaces            # for ALL SEARCHES!!!

    # Execute query
    $sth->bind_param( 1, $query );                          # docstore.mik.ua/orelly/linux/dbi/ch05_03.htm
    $sth->execute();                                        # eq to $sth->execute($query);

    my $id    = undef;
    my $label = undef;

    if ( $match eq 'exact_match' ) {

        # Parse query
        while ( my $row = $sth->fetchrow_arrayref ) {
            $id =
              $ontology ne 'ohdsi'
              ? uc($ontology) . ':' . $row->[$id_column]
              : $row->[3] . ':' . $row->[$id_column];
            $label = $row->[$label_column];
            last;    # Note that sometimes we get more than one (they're discarded)
        }
    }
    else {

        # Parse query w/ sub
        ( $id, $label ) = text_similarity(
            {
                sth                       => $sth,
                query                     => $query,
                ontology                  => $ontology,
                id_column                 => $id_column,
                label_column              => $label_column,
                text_similarity_method    => $text_similarity_method,
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

    my $arg                    = shift;
    my $sth                    = $arg->{sth};
    my $query                  = $arg->{query};
    my $ontology               = $arg->{ontology};
    my $id_column              = $arg->{id_column};
    my $label_column           = $arg->{label_column};
    my $min_score              = $arg->{min_text_similarity_score};
    my $text_similarity_method = $arg->{text_similarity_method};
    die "--text-similarity-method <$text_similarity_method> not allowed"
      unless ( $text_similarity_method eq 'dice'
        || $text_similarity_method eq 'cosine' );

    #say $text_similarity_method;

    # Create a new Text::Similarity object
    my $ts = Text::Similarity::Overlaps->new();

    # Fetch the query results
    my $data;    # hashref
    while ( my $row = $sth->fetchrow_arrayref() ) {

        say "---Checking <$row->[$label_column]>" if DEVEL_MODE;

        # We have a threshold to assign a result as valid
        my ( $score, %scores ) =
          $ts->getSimilarityStrings( $query, $row->[$label_column] );

        # Only load $data if dice >= $min_score;
        $data->{ $row->[$label_column] } = {
            id => $ontology ne 'ohdsi'
            ? uc($ontology) . ':' . $row->[$id_column]
            : $row->[3] . ':' . $row->[$id_column],
            label  => $row->[$label_column],
            scores => {%scores},
            query  => $query
          }
          if $scores{$text_similarity_method} >= $min_score;
    }

    # Sort the results by similarity score
    #$Data::Dumper::Sortkeys = 1 ;
    my @sorted_keys =
      sort {
        $data->{$b}{scores}{$text_similarity_method}
          <=> $data->{$a}{scores}{$text_similarity_method}
      } keys %{$data};

    print Dumper $data             if DEVEL_MODE;
    say "WINNER <$sorted_keys[0]>" if ( $sorted_keys[0] && DEVEL_MODE );

    # Return 1st element if present
    return $sorted_keys[0]
      ? ( $data->{ $sorted_keys[0] }{id}, $data->{ $sorted_keys[0] }{label} )
      : ( undef, undef );
}
1;
