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
  qw( $VERSION open_connections_SQLite close_connections_SQLite get_ontology_terms);

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
    # Initialize database connections for improved performance.
    # This section opens connections to all relevant SQLite databases at once.
    # Doing this at the beginning, rather than on each call, has been found to
    # improve speed by approximately 15%. The approach enhances efficiency by
    # reducing the overhead of repeatedly opening and closing connections.

    # Exception Handling:
    # The 'ohdsi' database is treated as an exception due to its larger size.
    # Opening the 'ohdsi' database can impact performance timings, so it's only
    # opened if explicitly required (indicated by $self->{ohdsi_db}).
    my @databases = @{ $self->{databases} };

    # Open databases
    my $dbh;
    $dbh->{$_} = open_db_SQLite( $_, $self->{path_to_ohdsi_db} )
      for (@databases);

    # Add $dbh HANDLE to $self
    $self->{dbh} = $dbh;    # Dynamically adding attributes (setter)

    # Prepare the query once
    prepare_query_SQLite($self);

    return 1;
}

sub close_connections_SQLite {

    my $self      = shift;
    my $dbh       = $self->{dbh};
    my @databases = @{ $self->{databases} };
    close_db_SQLite( $dbh->{$_} ) for (@databases);
    return 1;
}

sub open_db_SQLite {

    my ( $ontology, $path_to_ohdsi_db ) = @_;

    # Construct database file path
    my $dbfile = get_database_file_path( $ontology, $path_to_ohdsi_db );
    die "Database file not found: $dbfile" unless -f $dbfile;

    # Database connection settings
    my $dsn        = "dbi:SQLite:dbname=$dbfile";
    my %db_options = (
        PrintError       => 0,
        RaiseError       => 1,
        ReadOnly         => 1,
        AutoCommit       => 1,
        FetchHashKeyName => 'NAME_lc',
    );

    # Connect to the database
    my $db_handle = DBI->connect( $dsn, '', '', \%db_options )
      or die "Failed to connect to database: $DBI::errstr";

    # Optimizations for SQLite
    $db_handle->do("PRAGMA synchronous = OFF");
    $db_handle->do("PRAGMA cache_size = 800000");

    return $db_handle;
}

sub get_database_file_path {

    my ( $ontology, $path_to_ohdsi_db ) = @_;
    my $filename = "$ontology.db";
    my $path =
      ( $ontology eq 'ohdsi' && defined $path_to_ohdsi_db )
      ? $path_to_ohdsi_db
      : catdir( $Convert::Pheno::share_dir, 'db' );
    return catfile( $path, $filename );
}

sub close_db_SQLite {

    my $dbh = shift;
    $dbh->disconnect();
    return 1;
}

sub prepare_query_SQLite {

    my $self      = shift;
    my @databases = @{ $self->{databases} };

    ###############
    # EXPLANATION #
    ###############
    #
    # Optimization Decision: The "prepare step" is executed once at the start, rather than with each query.
    # Although the speed gain is modest (~15%), this approach reduces repetitive processing.
    # Flexibility in Querying: We've enabled searching in columns other than 'label'. This necessitates the creation
    # of corresponding $sth (Statement Handle) for each case. As a result, we have structured nested statement handles
    # like sth->{ncit}{label}, sth->{icd10}{label}, sth->{ohdsi}{concept_id}, and sth->{ohdsi}{label}.
    # Extensibility for Match Types: The structure also incorporates a "match" type, paving the way for various matching
    # methods in future enhancements.
    # NB: While it's feasible to alter the "prepare" dynamically during queries, it's crucial to reset it to the default
    # post-use. For faster performance, using smaller databases (e.g., ncit/icd10) is advisable.

    # NB:
    # dbh = "Database Handle"
    # sth = "Statement Handle"

    for my $match (@matches) {
        for my $ontology (@databases) {
            for my $column ( 'label', 'concept_id' ) {

                # We only need to open 'concept_id' in ohdsi
                next if ( $column eq 'concept_id' && $ontology ne 'ohdsi' );

                ##############################
                # Start building the queries #
                ##############################

                # Call build_query to construct the SQL query
                my $dbh   = $self->{dbh}{$ontology};
                my $query = build_query( $ontology, $column, $match );

                # Prepare the query
                my $sth = $dbh->prepare($query);

                # Autovivification of $self->{sth}{$ontology}{$column}{$match}
                $self->{sth}{$ontology}{$column}{$match} =
                  $sth;    # Dynamically adding nested attributes (setter)
            }
        }
    }

    #print Dumper $self and die;
    return 1;
}

sub build_query {

    my ( $ontology, $column, $match ) = @_;
    my $db     = uc($ontology) . '_table';
    my $db_fts = uc($ontology) . '_fts';

    my %query_type = (

        # Contains queries
        contains =>
qq(SELECT * FROM $db WHERE $column LIKE '%' || ? || '%' COLLATE NOCASE),

        # Exact search queries
        # What out for leading spaces!!!
        # SELECT * FROM HPO_table WHERE TRIM(label) = ? COLLATE NOCASE
        exact_match => qq(SELECT * FROM $db WHERE $column = ? COLLATE NOCASE),

        # **********************
        # *** IMPORTANT STEP ***
        # **********************

        # Full-text-search queries only on column <label> BUT IT CAN BE DONE ALL COLUMNS!!!!
        # The speed of the FTS in $column == $db_fts
        # FTS is 2x faster than 'contains'
        # NOTE (Jan-2023): We don't check for misspelled words
        #       --> TO DO - Tricky -->  https://www.sqlite.org/spellfix1.html
        full_text_search => qq(SELECT * FROM $db_fts WHERE $column MATCH ?),

        # SOUNDEX using TABLE_fts but only on column <label>
        # soundex     => qq(SELECT * FROM $db_fts WHERE SOUNDEX($column) = SOUNDEX(?)) # NOT USED

    );
    return $query_type{$match};
}

sub get_ontology_terms {

    ###############
    # START QUERY #
    ###############

    my $arg                       = shift;
    my $ontology                  = $arg->{ontology};
    my $sth_column_ref            = $arg->{sth_column_ref};              # Contains hashref
    my $query                     = $arg->{query};
    my $column                    = $arg->{column};
    my $databases                 = $arg->{databases};
    my $search                    = $arg->{search};
    my $text_similarity_method    = $arg->{text_similarity_method};
    my $min_text_similarity_score = $arg->{min_text_similarity_score};
    my $type_of_search            = 'full_text_search';                  # Options: 'contains' and 'full_text_search'
                                                                         # say $type_of_search;
    say "QUERY <$query> ONTOLOGY <$ontology>" if DEVEL_MODE;

    # A) 'exact'
    # - exact_match
    # B) Mixed queries:
    #    1 - exact_match
    #      if no results are found
    #    2 - contains
    #       for which we rank by similarity with Text:Similarity

    # Default values
    my %default_value = (
        id    => $ontology eq 'hpo' ? 'HP:NA0000' : uc($ontology) . ':NA0000',
        label => 'NA'
    );

    # exact_match (always performed)
    my ( $id, $label ) = execute_query_SQLite(
        {
            sth                       => $sth_column_ref->{exact_match},    # IMPORTANT STEP
            query                     => $query,
            ontology                  => $ontology,
            databases                 => $databases,
            match                     => 'exact_match',
            text_similarity_method    => $text_similarity_method,           # Not used here
            min_text_similarity_score => $min_text_similarity_score
        }
    );

    # Mixed queries
    if ( $search eq 'mixed' && ( !defined $id && !defined $label ) ) {
        ( $id, $label ) = execute_query_SQLite(
            {
                sth                    => $sth_column_ref->{$type_of_search},  # IMPORTANT STEP
                query                  => $query,
                ontology               => $ontology,
                databases              => $databases,
                match                  => $type_of_search,
                text_similarity_method => $text_similarity_method,
                min_text_similarity_score => $min_text_similarity_score
            }
        );
    }

    # Set defaults if undefined
    $id    = $id    // $default_value{id};
    $label = $label // $default_value{label};

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
    my @databases                 = @{ $arg->{databases} };

    # Initialize $id and $label to undefined
    my ( $id, $label ) = ( undef, undef );

    # Premature return if $query is empty
    return ( $id, $label ) if $query eq '';

    # Preprocess query for execution
    $query = prune_problematic_chars( $query, $match );

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

    # Define a hash for column positions in databases
    # In case we encounter in the future a situation where order of columns is different
    my $position = {
        map { $_ => { label => 0, id => 1 } } @databases    # Assuming @databases is defined elsewhere
    };
    my $id_column    = $position->{$ontology}{id};
    my $label_column = $position->{$ontology}{label};

    # Execute the query
    $sth->bind_param( 1, $query );

    eval { $sth->execute(); };
    if ($@) {
        warn "Query execution failed: $@";
        return ( $id, $label );
    }

    # HPO to HP
    chop($ontology) if $ontology eq 'hpo';

    # Process results depending on the type of match
    if ( $match eq 'exact_match' ) {
        while ( my $row = $sth->fetchrow_arrayref ) {
            $id =
              $ontology ne 'ohdsi'
              ? uc($ontology) . ':' . $row->[$id_column]
              : $row->[3] . ':' . $row->[$id_column];
            $label = $row->[$label_column];
            last;    # Only the first match is used
        }
    }
    else {
        # For other match types, use text similarity
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

    # Finish the statement handle
    $sth->finish();

    # Return the results
    return ( $id, $label );
}

sub prune_problematic_chars {

    my ( $query, $match ) = @_;

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # full_text_search is supposed to be ONLY in text fields, but, for
    # whatever reason the binding of parameters e.g, '2 - mild'
    # that start with number produce exceptions on SQLite.

    # Remove leading number-pattern for all searches
    #say "BEFORE <$query>";
    $query =~ s/^\d+\s+-\s+//;           # '2 - mild' => 'mild'
                                         #say "A1 <$query>";
    $query =~ s/^\d+\s+\((.+)\)$/$1/;    # '0 (none)' => 'none'
                                         #say "A2 <$query>";

    # Replace certain characters with spaces for Full Text Search
    $query =~ tr#_,-/# # if $match eq 'full_text_search';

    # Collapse duplicated spaces for all searches
    $query =~ tr/ //s;
    return $query;
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
    die "--text-similarity-method <$text_similarity_method> not allowed\n"
      unless ( $text_similarity_method eq 'dice'
        || $text_similarity_method eq 'cosine' );

    #say $text_similarity_method;

    # Create a new Text::Similarity object
    # NB: Overhead ???
    my $ts = Text::Similarity::Overlaps->new();

    # Fetch the query results
    my @results;
    while ( my $row = $sth->fetchrow_arrayref() ) {

        say "---Checking <$row->[$label_column]>" if DEVEL_MODE;

        # We have a threshold to assign a result as valid
        my ( $score, %scores ) =
          $ts->getSimilarityStrings( $query, $row->[$label_column] );

        # Only load $data if dice >= $min_score;
        push @results,
          {
            id => $ontology ne 'ohdsi'
            ? uc($ontology) . ':' . $row->[$id_column]
            : $row->[3] . ':' . $row->[$id_column],
            label  => $row->[$label_column],
            scores => {%scores},
            query  => $query
          }
          if $scores{$text_similarity_method} >= $min_score;
    }

    # Sort the array by similarity score
    @results = sort {
        $b->{scores}{$text_similarity_method}
          <=> $a->{scores}{$text_similarity_method}
    } @results;
    print Dumper \@results              if DEVEL_MODE;
    say "WINNER <$results[0]->{label}>" if ( @results && DEVEL_MODE );

    # Return 1st element if present
    # *** IMPORTANT ***
    # Often two labels get identical score. Getting 1st on the array
    return @results
      ? ( $results[0]->{id}, $results[0]->{label} )
      : ( undef, undef );
}
1;
