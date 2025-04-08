package Convert::Pheno::SQLite;

use strict;
use warnings;
use autodie;
use feature qw(say);
use DBI;
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use Exporter 'import';
use Convert::Pheno::Similarity;
our @EXPORT =
  qw( $VERSION open_connections_SQLite close_connections_SQLite get_ontology_terms);
my @matches = qw(exact_match full_text_search);    # excluded 'contains'

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

    my %match_type = (

        # Contains queries
        #contains => qq(SELECT * FROM $db WHERE $column LIKE '%' || ? || '%' COLLATE NOCASE),

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
    return $match_type{$match};
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
    say "QUERY <$query> ONTOLOGY <$ontology> COLUM <$column> SEARCH <$search>"
      if DEVEL_MODE;

    # A) 'exact'
    # - exact_match
    # B) Mixed queries:
    #    1 - exact_match
    #      if no results are found
    #    2 - FTS
    #       for which we rank by similarity with Text:Similarity

    # Default values
    my %default_value = (
        id    => $ontology eq 'hpo'   ? 'HP:NA0000' : uc($ontology) . ':NA0000',
        label => $ontology eq 'ohdsi' ? 'No matching concept' : 'NA'
    );
    $default_value{concept_id} = 0 if $ontology eq 'ohdsi';

    # exact_match (always performed)
    my ( $id, $label, $concept_id ) = execute_query_SQLite(
        {
            sth                       => $sth_column_ref->{exact_match},    # IMPORTANT STEP
            query                     => $query,
            ontology                  => $ontology,
            databases                 => $databases,
            search                    => $search,
            match_type                => 'exact_match',
            text_similarity_method    => $text_similarity_method,           # Not used here
            min_text_similarity_score => $min_text_similarity_score
        }
    );

    # mixed/hybrid
    unless ( defined $id && defined $label ) {
        if ( $search eq 'mixed' || $search eq 'hybrid' ) {
            print "EXECUTING SEARCH <$search> on QUERY <$query>\n"
              if DEVEL_MODE;
            ( $id, $label, $concept_id ) = execute_query_SQLite(
                {
                    sth        => $sth_column_ref->{'full_text_search'},    # IMPORTANT STEP
                    query      => $query,
                    ontology   => $ontology,
                    databases  => $databases,
                    match_type => 'full_text_search',
                    search     => $search,
                    text_similarity_method    => $text_similarity_method,
                    min_text_similarity_score => $min_text_similarity_score
                }
            );
        }
    }

    # Set defaults if undefined
    $id    = $id    // $default_value{id};
    $label = $label // $default_value{label};
    if ( $ontology eq 'ohdsi' ) {
        $concept_id = $concept_id // $default_value{concept_id};
    }

    #############
    # END QUERY #
    #############

    return ( $id, $label, $concept_id );

}

sub execute_query_SQLite {
    my $arg                       = shift;
    my $sth                       = $arg->{sth};
    my $query                     = $arg->{query};
    my $text_similarity_method    = $arg->{text_similarity_method};
    my $min_text_similarity_score = $arg->{min_text_similarity_score};
    my $ontology                  = $arg->{ontology};
    my $match_type                = $arg->{match_type};
    my @databases                 = @{ $arg->{databases} };
    my $search                    = $arg->{search};

    # Initialize $id and $label to undefined
    my ( $id, $label, $concept_id ) = ( undef, undef, undef );

    # Premature return if $query is empty
    return ( $id, $label, $concept_id ) if $query eq '';

    # Preprocess query for execution
    $query = prune_problematic_chars( $query, $match_type );

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
    my $id_column         = $position->{$ontology}{id};
    my $label_column      = $position->{$ontology}{label};
    my $concept_id_column = 2;

    # Execute the query
    $sth->bind_param( 1, $query );

    eval { $sth->execute(); };
    if ($@) {
        warn "Query execution failed: $@";
        return ( $id, $label, $concept_id );
    }

    # HPO to HP
    chop($ontology) if $ontology eq 'hpo';

    # Process results depending on the type of match
    if ( $match_type eq 'exact_match' ) {
        say "MATCH_TYPE: <exact_match>" if DEVEL_MODE;
        while ( my $row = $sth->fetchrow_arrayref ) {
            $id =
              $ontology ne 'ohdsi'
              ? uc($ontology) . ':' . $row->[$id_column]
              : $row->[3] . ':' . $row->[$id_column];
            $label      = $row->[$label_column];
            $concept_id = $row->[$concept_id_column];
            last;    # Only the first match is used
        }
    }
    else {
        say "MATCH_TYPE: <full_text_seacch>" if DEVEL_MODE;

        if ( $search eq 'mixed' ) {

            # For other match types, use text similarity
            ( $id, $label, $concept_id ) = similarity_match(
                {
                    sth                       => $sth,
                    query                     => $query,
                    ontology                  => $ontology,
                    id_column                 => $id_column,
                    label_column              => $label_column,
                    text_similarity_method    => $text_similarity_method,
                    min_text_similarity_score => $min_text_similarity_score,
                    concept_id_column         => $concept_id_column
                }
            );
        }
        else {

            # Call a subroutine to compute composite similarity.
            ( $id, $label, $concept_id ) = composite_similarity_match(
                {
                    sth                       => $sth,
                    query                     => $query,
                    ontology                  => $ontology,
                    id_column                 => $id_column,
                    label_column              => $label_column,
                    text_similarity_method    => $text_similarity_method,      # cosine or dice
                    min_text_similarity_score => $min_text_similarity_score,
                    concept_id_column         => $concept_id_column

                      # Possibly additional parameters, e.g., weighting factors
                }
            );
        }
    }

    # Finish the statement handle
    $sth->finish();

    # Return the results
    return ( $id, $label, $concept_id );
}

sub prune_problematic_chars {
    my ( $query, $match_type ) = @_;

    # **********************
    # *** IMPORTANT STEP ***
    # **********************
    # full_text_search is supposed to be ONLY in text fields, but, for
    # whatever reason the binding of parameters e.g, '2 - mild'
    # that start with number produce exceptions on SQLite.

    # Prune
    # "OPCS(v4-0.0):Cannulation of lymphatic duct"
    # to
    # "Cannulation of lymphatic duct"
    $query =~ s/^[^:]*://;

    # Remove leading number-pattern for all searches
    #say "BEFORE <$query>";
    $query =~ s/^\d+\s+-\s+//;           # '2 - mild' => 'mild'
                                         #say "A1 <$query>";
    $query =~ s/^\d+\s+\((.+)\)$/$1/;    # '0 (none)' => 'none'
                                         #say "A2 <$query>";

    # Replace certain characters with spaces for spefific searches
    $query =~ tr#_,-/# # if $match_type eq 'full_text_search';

    # Collapse duplicated spaces for all searches
    $query =~ tr/ //s;
    return $query;
}

sub similarity_match {
    my $arg               = shift;
    my $sth               = $arg->{sth};
    my $query             = $arg->{query};
    my $ontology          = $arg->{ontology};
    my $id_column         = $arg->{id_column};
    my $label_column      = $arg->{label_column};
    my $min_score         = $arg->{min_text_similarity_score};
    my $sim_method        = $arg->{text_similarity_method};      # 'dice' or 'cosine'
    my $concept_id_column = $arg->{concept_id_column};

    # Create a new Text::Similarity object.
    my $ts = Text::Similarity::Overlaps->new();

    my @results;
    while ( my $row = $sth->fetchrow_arrayref() ) {
        my $candidate_label = $row->[$label_column];
        say "--- MIXED: Computing similarity for candidate <$candidate_label>"
          if DEVEL_MODE;

        # Calculate similarity score using Text::Similarity::Overlaps.
        my ( $score, %scores ) =
          $ts->getSimilarityStrings( $query, $candidate_label );

        # Only consider candidates above our minimum threshold.
        if ( $scores{$sim_method} >= $min_score ) {
            push @results,
              {
                id => $ontology ne 'ohdsi'
                ? uc($ontology) . ':' . $row->[$id_column]
                : $row->[3] . ':' . $row->[$id_column],
                label      => $candidate_label,
                scores     => \%scores,
                query      => $query,
                concept_id => $row->[$concept_id_column],
              };
        }
    }

    # Sort the candidates by the token-based similarity (using the chosen method) in descending order.
    @results =
      sort { $b->{scores}->{$sim_method} <=> $a->{scores}->{$sim_method} }
      @results;

    print Dumper( \@results ) if DEVEL_MODE;
    if ( @results && DEVEL_MODE ) {
        say "--- WINNER ---";
        print Dumper( $results[0] );
    }

    # Return the top candidate if available, otherwise return undefined values.
    return @results
      ? ( $results[0]->{id}, $results[0]->{label}, $results[0]->{concept_id} )
      : ( undef, undef, undef );
}

sub composite_similarity_match {
    my $arg                    = shift;
    my $sth                    = $arg->{sth};
    my $query                  = $arg->{query};
    my $ontology               = $arg->{ontology};
    my $id_column              = $arg->{id_column};
    my $label_column           = $arg->{label_column};
    my $min_score              = $arg->{min_text_similarity_score};
    my $text_similarity_method = $arg->{text_similarity_method};
    my $concept_id_column      = $arg->{concept_id_column};

    my @results;
    while ( my $row = $sth->fetchrow_arrayref() ) {
        my $candidate_label = $row->[$label_column];
        my $token_sim =
          Convert::Pheno::Similarity::compute_token_similarity( $query,
            $candidate_label, $text_similarity_method );

        # Skip candidates below minimum token similarity.
        next unless $token_sim >= $min_score;
        my $composite =
          Convert::Pheno::Similarity::composite_similarity( $query,
            $candidate_label, 0.9, 0.1, $text_similarity_method );
        push @results,
          {
            id => $ontology ne 'ohdsi'
            ? uc($ontology) . ':' . $row->[$id_column]
            : $row->[3] . ':' . $row->[$id_column],
            label     => $candidate_label,
            token_sim => $token_sim,
            lev_sim   =>
              Convert::Pheno::Similarity::compute_normalized_levenshtein(
                $query, $candidate_label
              ),
            composite  => $composite,
            query      => $query,
            concept_id => $row->[$concept_id_column],
          };
    }

    @results = sort { $b->{composite} <=> $a->{composite} } @results;
    return @results
      ? ( $results[0]->{id}, $results[0]->{label}, $results[0]->{concept_id} )
      : ( undef, undef, undef );
}
1;
