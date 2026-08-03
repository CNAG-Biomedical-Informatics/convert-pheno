package Convert::Pheno::DB::SQLite;

use strict;
use warnings;
use autodie;
use feature qw(say);
use DBI;
use File::Spec::Functions qw(catdir catfile);
use Time::HiRes qw(time);
use Data::Dumper;
use Text::Similarity::Overlaps;
use Exporter 'import';
use Convert::Pheno::DB::Similarity;
our @EXPORT =
  qw( $VERSION open_connections_SQLite close_connections_SQLite get_ontology_terms);
my @matches = qw(exact_match full_text_search relaxed_full_text_search);

use constant DEVEL_MODE => 0;
use constant RELAXED_FTS_CANDIDATE_LIMIT => 200;
use constant RELAXED_FTS_MAX_TOKENS      => 12;

my %COLUMN_MATCH_CONFIG = (
    label         => { exact_collate_nocase => 1 },
    id            => { exact_collate_nocase => 1 },
    concept_id    => { exact_collate_nocase => 0 },
    vocabulary_id => { exact_collate_nocase => 1 },
);

sub _ontology_prefix {
    my ($ontology) = @_;
    return 'HP'   if $ontology eq 'hpo';
    return 'NCIT' if $ontology eq 'cdisc';
    return uc($ontology);
}

sub _db_profile_enabled {
    my ($self) = @_;
    return $self && defined $self->{debug} && $self->{debug} >= 2;
}

sub _db_profile_path {
    my ( $self, @keys ) = @_;
    return unless _db_profile_enabled($self);
    return unless @keys;

    my $node = $self->{db_profile} ||= {};
    for my $key ( @keys[ 0 .. $#keys - 1 ] ) {
        $node->{$key} ||= {};
        $node = $node->{$key};
    }

    return ( $node, $keys[-1] );
}

sub _db_profile_inc {
    my ( $self, @keys ) = @_;
    my ( $node, $leaf ) = _db_profile_path( $self, @keys ) or return 1;
    $node->{$leaf} = ( $node->{$leaf} // 0 ) + 1;
    return 1;
}

sub _db_profile_add {
    my ( $self, $value, @keys ) = @_;
    return 1 unless defined $value;
    my ( $node, $leaf ) = _db_profile_path( $self, @keys ) or return 1;
    $node->{$leaf} = ( $node->{$leaf} // 0 ) + $value;
    return 1;
}

sub _db_profile_get {
    my ( $hashref, @keys ) = @_;
    my $node = $hashref;
    for my $key (@keys) {
        return 0 unless ref $node eq 'HASH' && exists $node->{$key};
        $node = $node->{$key};
    }
    return $node // 0;
}

sub _db_profile_reset {
    my ($self) = @_;
    return 1 unless _db_profile_enabled($self);
    $self->{db_profile} = { started_at => time };
    return 1;
}

sub _emit_db_profile_summary {
    my ($self) = @_;
    return 1 unless _db_profile_enabled($self);

    my $profile = delete $self->{db_profile};
    return 1 unless $profile;

    my $elapsed = time - ( $profile->{started_at} || time );
    my @lines   = ('DB lookup profile:');

    push @lines,
      sprintf(
        '  mapping requests=%d cache_hits=%d db_lookups=%d elapsed=%.3fs',
        _db_profile_get( $profile, 'mapping', 'requests' ),
        _db_profile_get( $profile, 'mapping', 'cache_hits' ),
        _db_profile_get( $profile, 'mapping', 'db_lookups' ),
        $elapsed,
      );

    push @lines,
      sprintf(
        '  final resolution exact=%d similarity=%d fallback_na=%d',
        _db_profile_get( $profile, 'final_resolution', 'exact' ),
        _db_profile_get( $profile, 'final_resolution', 'similarity' ),
        _db_profile_get( $profile, 'final_resolution', 'fallback_na' ),
      );

    push @lines,
      sprintf(
        '  sql exact_match=%d full_text_search=%d relaxed_full_text_search=%d rows_fetched=%d candidate_rows=%d shortlisted=%d failures=%d time=%.3fs',
        _db_profile_get( $profile, 'sql', 'match_type', 'exact_match',      'executions' ),
        _db_profile_get( $profile, 'sql', 'match_type', 'full_text_search', 'executions' ),
        _db_profile_get( $profile, 'sql', 'match_type', 'relaxed_full_text_search', 'executions' ),
        _db_profile_get( $profile, 'sql', 'rows_fetched' ),
        _db_profile_get( $profile, 'sql', 'candidate_rows' ),
        _db_profile_get( $profile, 'sql', 'shortlisted_candidates' ),
        _db_profile_get( $profile, 'sql', 'failures' ),
        _db_profile_get( $profile, 'sql', 'total_time' ),
      );

    my $ontologies = $profile->{ontology} || {};
    for my $ontology ( sort keys %{$ontologies} ) {
        push @lines,
          sprintf(
            '  ontology[%s] requests=%d cache_hits=%d db_lookups=%d exact=%d similarity=%d fallback_na=%d',
            $ontology,
            _db_profile_get( $ontologies, $ontology, 'requests' ),
            _db_profile_get( $ontologies, $ontology, 'cache_hits' ),
            _db_profile_get( $ontologies, $ontology, 'db_lookups' ),
            _db_profile_get( $ontologies, $ontology, 'final_resolution', 'exact' ),
            _db_profile_get( $ontologies, $ontology, 'final_resolution', 'similarity' ),
            _db_profile_get( $ontologies, $ontology, 'final_resolution', 'fallback_na' ),
          );
    }

    print STDERR join( "\n", @lines ), "\n";
    return 1;
}

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
    _db_profile_reset($self);

    my @databases = @{ $self->{databases} };

    # Open databases
    my $dbh = {};
    my $ok = eval {
        for my $database (@databases) {
            $dbh->{$database} =
              open_db_SQLite( $database, $self->{path_to_ohdsi_db} );
        }

        # Add $dbh HANDLE to $self
        $self->{dbh} = $dbh;    # Dynamically adding attributes (setter)

        # Prepare the query once
        prepare_query_SQLite($self);
        1;
    };

    unless ($ok) {
        my $error = $@;
        delete $self->{sth};
        for my $database ( reverse @databases ) {
            next unless exists $dbh->{$database};
            eval { close_db_SQLite( $dbh->{$database} ) };
        }
        delete $self->{dbh};
        die $error;
    }

    return 1;
}

sub close_connections_SQLite {
    my $self      = shift;
    my $dbh       = $self->{dbh} || {};
    my @databases = @{ $self->{databases} };
    my @errors;

    delete $self->{sth};
    for my $database (@databases) {
        next unless exists $dbh->{$database};
        my $ok = eval {
            close_db_SQLite( $dbh->{$database} );
            1;
        };
        push @errors, $@ unless $ok;
    }
    delete $self->{dbh};

    my $profile_ok = eval {
        _emit_db_profile_summary($self);
        1;
    };
    push @errors, $@ unless $profile_ok;

    die join q{}, @errors if @errors;
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

    if ( defined $ontology && $ontology eq 'ohdsi' ) {
        my $ok = eval {
            validate_ohdsi_schema( $db_handle, $dbfile );
            1;
        };
        unless ($ok) {
            my $error = $@;
            eval { $db_handle->disconnect() };
            die $error;
        }
    }

    return $db_handle;
}

sub validate_ohdsi_schema {
    my ( $dbh, $dbfile ) = @_;
    my @required_concept_columns = qw(
      label id concept_id vocabulary_id domain_id concept_class_id
      standard_concept valid_start_date valid_end_date invalid_reason
    );
    my @required_mapping_columns = qw(
      source_concept_id target_concept_id relationship_id
      valid_start_date valid_end_date invalid_reason
    );
    my @required_fts_columns = qw(label id concept_id vocabulary_id);

    my %concept_column = map { $_->[1] => 1 }
      @{ $dbh->selectall_arrayref('PRAGMA table_info(OHDSI_table)') };
    my @missing_concept_columns =
      grep { !$concept_column{$_} } @required_concept_columns;

    my %mapping_column = map { $_->[1] => 1 }
      @{ $dbh->selectall_arrayref('PRAGMA table_info(OHDSI_maps_to)') };
    my @missing_mapping_columns =
      grep { !$mapping_column{$_} } @required_mapping_columns;

    my %fts_column = map { $_->[1] => 1 }
      @{ $dbh->selectall_arrayref('PRAGMA table_info(OHDSI_fts)') };
    my @missing_fts_columns = grep { !$fts_column{$_} } @required_fts_columns;

    return 1
      unless @missing_concept_columns
      || @missing_mapping_columns
      || @missing_fts_columns;

    my @details;
    push @details,
      'OHDSI_table columns: ' . join( ', ', @missing_concept_columns )
      if @missing_concept_columns;
    push @details,
      'OHDSI_maps_to columns: ' . join( ', ', @missing_mapping_columns )
      if @missing_mapping_columns;
    push @details, 'OHDSI_fts columns: ' . join( ', ', @missing_fts_columns )
      if @missing_fts_columns;

    die "Athena-OHDSI database <$dbfile> uses the pre-bundle schema "
      . '(' . join( '; ', @details ) . '). '
      . "Install the current ohdsi.db.\n";
}

sub get_database_file_path {
    my ( $ontology, $path_to_ohdsi_db ) = @_;
    my $filename = defined $ontology ? "$ontology.db" : '.db';
    my $path =
      ( defined $ontology && $ontology eq 'ohdsi' && defined $path_to_ohdsi_db )
      ? $path_to_ohdsi_db
      : catdir( $Convert::Pheno::share_dir // q{}, 'db' );
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
            my @columns = $match eq 'exact_match'
              ? ( 'label', 'id', $ontology eq 'ohdsi' ? ('concept_id') : () )
              : ('label');
            for my $column (@columns) {

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
    die "Unsupported SQLite lookup column <$column>\n"
      unless exists $COLUMN_MATCH_CONFIG{$column};
    my $db     = uc($ontology) . '_table';
    my $db_fts = uc($ontology) . '_fts';
    my $exact_predicate =
      $COLUMN_MATCH_CONFIG{$column}{exact_collate_nocase}
      ? qq($column = ? COLLATE NOCASE)
      : qq($column = ?);

    my %match_type = (

        # Contains queries
        #contains => qq(SELECT * FROM $db WHERE $column LIKE '%' || ? || '%' COLLATE NOCASE),

        # Exact search queries
        # What out for leading spaces!!!
        # SELECT * FROM HPO_table WHERE TRIM(label) = ? COLLATE NOCASE
        exact_match => qq(SELECT * FROM $db WHERE $exact_predicate),

        # **********************
        # *** IMPORTANT STEP ***
        # **********************

        # Strict FTS supplies candidates containing every query token. Fuzzy
        # search may retry with an all-but-one-token expression when this set
        # is empty; BM25 and a hard limit keep that broader pass bounded.
        full_text_search => qq(SELECT * FROM $db_fts WHERE $column MATCH ?),
        relaxed_full_text_search =>
          qq(SELECT * FROM $db_fts WHERE $column MATCH ? ORDER BY bm25($db_fts) LIMIT )
          . RELAXED_FTS_CANDIDATE_LIMIT,

        # SOUNDEX using TABLE_fts but only on column <label>
        # soundex     => qq(SELECT * FROM $db_fts WHERE SOUNDEX($column) = SOUNDEX(?)) # NOT USED

    );
    return $match_type{$match};
}

# MATCH parameters are still parsed as FTS syntax even when bound safely.
# Convert source labels into quoted literal words so operators such as OR,
# NEAR, quotes, and parentheses cannot change candidate retrieval.
sub _fts_tokens {
    my ($query) = @_;
    $query = prune_problematic_chars( $query, 'full_text_search' );

    my %seen;
    return grep { !$seen{lc $_}++ } ( $query =~ /([\p{L}\p{N}]+)/gu );
}

sub _quote_fts_token {
    my ($token) = @_;
    $token =~ s/"/""/g;
    return qq{"$token"};
}

sub build_strict_fts_query {
    my @tokens = _fts_tokens(@_);
    return unless @tokens;
    return join ' AND ', map { _quote_fts_token($_) } @tokens;
}

sub build_relaxed_fts_query {
    my @tokens = _fts_tokens(@_);
    return unless @tokens >= 2 && @tokens <= RELAXED_FTS_MAX_TOKENS;

    my @quoted = map { _quote_fts_token($_) } @tokens;

    return join ' OR ', map { qq{($_)} } @quoted if @quoted == 2;

    my @clauses;
    for my $omitted ( 0 .. $#quoted ) {
        my @required = @quoted;
        splice @required, $omitted, 1;
        push @clauses, '(' . join( ' AND ', @required ) . ')';
    }
    return join ' OR ', @clauses;
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
    my $levenshtein_weight        = $arg->{levenshtein_weight};
    my $self                      = $arg->{self};
    say "QUERY <$query> ONTOLOGY <$ontology> COLUM <$column> SEARCH <$search>\n      min_text_similarity_score <$min_text_similarity_score> levenshtein_weight<$levenshtein_weight>"
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
        id    => _ontology_prefix($ontology) . ':NA0000',
        label => $ontology eq 'ohdsi' ? 'No matching concept' : 'NA'
    );
    $default_value{concept_id} = 0 if $ontology eq 'ohdsi';

    # exact_match (always performed)
    my ( $id, $label, $concept_id, $search_resolution, $search_evidence ) =
      execute_query_SQLite(
        {
            sth                       => $sth_column_ref->{exact_match},    # IMPORTANT STEP
            query                     => $query,
            ontology                  => $ontology,
            databases                 => $databases,
            search                    => $search,
            match_type                => 'exact_match',
            text_similarity_method    => $text_similarity_method,           # Not used here
            min_text_similarity_score => $min_text_similarity_score,
            levenshtein_weight        => $levenshtein_weight,
            self                      => $self,
        }
    );

    # mixed/fuzzy
    unless ( defined $id && defined $label ) {
        if ( $search eq 'mixed' || $search eq 'fuzzy' ) {
            print "EXECUTING SEARCH <$search> on QUERY <$query>\n"
              if DEVEL_MODE;
            my $strict_query = build_strict_fts_query($query);
            if ( defined $strict_query ) {
                ( $id, $label, $concept_id, $search_resolution, $search_evidence ) =
                  execute_query_SQLite(
                    {
                        sth => $sth_column_ref->{'full_text_search'},
                        query                     => $strict_query,
                        scoring_query             => $query,
                        query_is_fts_expression   => 1,
                        ontology                  => $ontology,
                        databases                 => $databases,
                        match_type                => 'full_text_search',
                        search                    => $search,
                        text_similarity_method    => $text_similarity_method,
                        min_text_similarity_score => $min_text_similarity_score,
                        levenshtein_weight        => $levenshtein_weight,
                        self                      => $self,
                    }
                  );
            }

            # Strict FTS requires every token. If it produces no candidates,
            # fuzzy search retries with a bounded all-but-one-token query. The
            # original normalized text remains the input to similarity scoring.
            if (
                   $search eq 'fuzzy'
                && !defined $id
                && $search_evidence
                && !( $search_evidence->{candidates_evaluated} // 0 )
              )
            {
                my $relaxed_query = build_relaxed_fts_query($query);
                if ( defined $relaxed_query ) {
                    ( $id, $label, $concept_id, $search_resolution, $search_evidence ) =
                      execute_query_SQLite(
                        {
                            sth => $sth_column_ref->{'relaxed_full_text_search'},
                            query                     => $relaxed_query,
                            scoring_query             => $query,
                            query_is_fts_expression   => 1,
                            ontology                  => $ontology,
                            databases                 => $databases,
                            match_type                => 'relaxed_full_text_search',
                            search                    => $search,
                            text_similarity_method    => $text_similarity_method,
                            min_text_similarity_score => $min_text_similarity_score,
                            levenshtein_weight        => $levenshtein_weight,
                            self                      => $self,
                        }
                      );
                }
            }
        }
    }

    # Set defaults if undefined
    $id    = $id    // $default_value{id};
    $label = $label // $default_value{label};
    if ( $ontology eq 'ohdsi' ) {
        $concept_id = $concept_id // $default_value{concept_id};
    }
    $search_resolution = defined $id && $id eq $default_value{id}
      ? 'fallback_na'
      : $search_resolution // 'fallback_na';

    #############
    # END QUERY #
    #############

    return ( $id, $label, $concept_id, $search_resolution, $search_evidence );

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
    my $levenshtein_weight        = $arg->{levenshtein_weight};
    my $self                      = $arg->{self};
    my $started_at                = _db_profile_enabled($self) ? time : undef;
    my $scoring_query             = $arg->{scoring_query} // $query;

    # Initialize $id and $label to undefined
    my ( $id, $label, $concept_id, $search_resolution, $search_evidence ) =
      ( undef, undef, undef, undef, undef );

    # Premature return if $query is empty
    return ( $id, $label, $concept_id, $search_resolution, $search_evidence )
      if $query eq '';

    # Preprocess query for execution
    $query = prune_problematic_chars( $query, $match_type )
      unless $arg->{query_is_fts_expression};
    $scoring_query = prune_problematic_chars( $scoring_query, 'full_text_search' );

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
    _db_profile_inc( $self, 'sql', 'match_type', $match_type, 'executions' );

    my $execute_started_at = _db_profile_enabled($self) ? time : undef;
    eval { $sth->execute(); };
    if ($@) {
        _db_profile_inc( $self, 'sql', 'failures' );
        warn "Query execution failed: $@";
        return ( $id, $label, $concept_id, $search_resolution, $search_evidence );
    }
    _db_profile_add( $self, time - $execute_started_at, 'sql', 'execute_time' )
      if defined $execute_started_at;

    # Process results depending on the type of match
    if ( $match_type eq 'exact_match' ) {
        say "MATCH_TYPE: <exact_match>" if DEVEL_MODE;
        my $candidate_rows = 0;
        my ( $runner_up_id, $runner_up_label );
        while ( my $row = $sth->fetchrow_arrayref ) {
            _db_profile_inc( $self, 'sql', 'rows_fetched' );
            $candidate_rows++;
            if ( !defined $id ) {
                $id = _candidate_id( $ontology, $row, $id_column );
                $label             = $row->[$label_column];
                $concept_id        = $row->[$concept_id_column];
                $search_resolution = 'exact';
            }
            elsif ( !defined $runner_up_id ) {
                $runner_up_id    = _candidate_id( $ontology, $row, $id_column );
                $runner_up_label = $row->[$label_column];
            }
        }
        $search_evidence = {
            candidate_strategy => 'exact_index',
            candidates_evaluated => $candidate_rows,
            eligible_candidates => $candidate_rows,
            defined $id
            ? (
                best_candidate_label => $label,
                best_candidate_id    => $id,
                best_candidate_score => 1,
              )
            : (),
            defined $runner_up_id
            ? (
                runner_up_label => $runner_up_label,
                runner_up_id    => $runner_up_id,
                runner_up_score => 1,
                score_margin    => 0,
              )
            : (),
        };
    }
    else {
        say "MATCH_TYPE: <full_text_search>" if DEVEL_MODE;

        if ( $search eq 'mixed' ) {

            # For other match types, use text similarity
            my $stats;
            ( $id, $label, $concept_id, $stats ) = similarity_match(
                {
                    sth                       => $sth,
                    query                     => $scoring_query,
                    ontology                  => $ontology,
                    id_column                 => $id_column,
                    label_column              => $label_column,
                    text_similarity_method    => $text_similarity_method,
                    min_text_similarity_score => $min_text_similarity_score,
                    levenshtein_weight        => $levenshtein_weight,
                    concept_id_column         => $concept_id_column,
                    self                      => $self,
                }
            );
            _db_profile_add( $self, $stats->{candidate_rows},         'sql', 'candidate_rows' );
            _db_profile_add( $self, $stats->{shortlisted_candidates}, 'sql', 'shortlisted_candidates' );
            _db_profile_add( $self, $stats->{evaluation_time},        'sql', 'similarity_time' );
            $search_resolution = defined $id ? 'similarity' : undef;
            $search_evidence = _search_evidence(
                $stats,
                $match_type eq 'relaxed_full_text_search'
                ? 'relaxed_fts'
                : 'strict_fts'
            );
        }
        else {

            # Call a subroutine to compute composite similarity.
            my $stats;
            ( $id, $label, $concept_id, $stats ) = composite_similarity_match(
                {
                    sth                       => $sth,
                    query                     => $scoring_query,
                    ontology                  => $ontology,
                    id_column                 => $id_column,
                    label_column              => $label_column,
                    text_similarity_method    => $text_similarity_method,      # cosine or dice
                    min_text_similarity_score => $min_text_similarity_score,
                    levenshtein_weight        => $levenshtein_weight,
                    concept_id_column         => $concept_id_column,
                    self                      => $self,
                    allow_spelling_variant    =>
                      $match_type eq 'relaxed_full_text_search',

                      # Possibly additional parameters, e.g., weighting factors
                }
            );
            _db_profile_add( $self, $stats->{candidate_rows},         'sql', 'candidate_rows' );
            _db_profile_add( $self, $stats->{shortlisted_candidates}, 'sql', 'shortlisted_candidates' );
            _db_profile_add( $self, $stats->{evaluation_time},        'sql', 'similarity_time' );
            $search_resolution = defined $id ? 'similarity' : undef;
            $search_evidence = _search_evidence(
                $stats,
                $match_type eq 'relaxed_full_text_search'
                ? 'relaxed_fts'
                : 'strict_fts'
            );
        }
    }

    # Finish the statement handle
    $sth->finish();
    _db_profile_add( $self, time - $started_at, 'sql', 'total_time' )
      if defined $started_at;

    # Return the results
    return ( $id, $label, $concept_id, $search_resolution, $search_evidence );
}

sub _candidate_id {
    my ( $ontology, $row, $id_column ) = @_;
    return $ontology ne 'ohdsi'
      ? _ontology_prefix($ontology) . ':' . $row->[$id_column]
      : $row->[3] . ':' . $row->[$id_column];
}

sub _search_evidence {
    my ( $stats, $strategy ) = @_;
    return {
        candidate_strategy => $strategy,
        candidates_evaluated => $stats->{candidate_rows},
        eligible_candidates => $stats->{shortlisted_candidates},
        map { $_ => $stats->{$_} }
          grep { exists $stats->{$_} }
          qw(best_candidate_label best_candidate_id best_candidate_score token_similarity base_token_similarity normalized_levenshtein spelling_variant spelling_query_token spelling_candidate_token spelling_token_similarity runner_up_label runner_up_id runner_up_score score_margin),
    };
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

sub _select_ranked_candidate {
    my ( $results, $candidate_rows, $min_score, $started_at ) = @_;
    @{$results} = sort {
           $b->{match_score} <=> $a->{match_score}
        || $a->{sequence} <=> $b->{sequence}
    } @{$results};

    my $winner              = $results->[0];
    my $runner_up           = $results->[1];
    my $eligible_candidates = grep { $_->{match_score} >= $min_score } @{$results};
    my $stats = {
        candidate_rows         => $candidate_rows,
        shortlisted_candidates => $eligible_candidates,
        evaluation_time        => defined $started_at ? time - $started_at : undef,
        defined $winner
        ? (
            best_candidate_label => $winner->{label},
            best_candidate_id    => $winner->{id},
            best_candidate_score => $winner->{match_score},
            map { $_ => $winner->{$_} }
              grep { exists $winner->{$_} }
              qw(token_similarity base_token_similarity normalized_levenshtein spelling_variant spelling_query_token spelling_candidate_token spelling_token_similarity),
          )
        : (),
        defined $runner_up
        ? (
            runner_up_label => $runner_up->{label},
            runner_up_id    => $runner_up->{id},
            runner_up_score => $runner_up->{match_score},
            score_margin    => $winner->{match_score} - $runner_up->{match_score},
          )
        : (),
    };

    return defined $winner && $winner->{match_score} >= $min_score
      ? ( $winner->{id}, $winner->{label}, $winner->{concept_id}, $stats )
      : ( undef, undef, undef, $stats );
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
    my $started_at        = _db_profile_enabled( $arg->{self} ) ? time : undef;
    my $candidate_rows    = 0;
    my $sequence          = 0;

    # Create a new Text::Similarity object.
    my $ts = Text::Similarity::Overlaps->new();

    my @results;
    while ( my $row = $sth->fetchrow_arrayref() ) {
        $candidate_rows++;
        my $candidate_label = $row->[$label_column];
        say "--- MIXED: Computing similarity for candidate <$candidate_label>"
          if DEVEL_MODE;

        my $token_similarity =
          Convert::Pheno::DB::Similarity::compute_token_similarity(
            $query, $candidate_label, $sim_method, $ts );

        # Retain scores below the threshold for audit and review.
        push @results,
          {
            id               => _candidate_id( $ontology, $row, $id_column ),
            label            => $candidate_label,
            match_score      => $token_similarity,
            token_similarity => $token_similarity,
            concept_id       => $row->[$concept_id_column],
            sequence         => $sequence,
          };
        $sequence++;
    }

    my @selected = _select_ranked_candidate(
        \@results, $candidate_rows, $min_score, $started_at
    );
    print Dumper( \@results ) if DEVEL_MODE;
    if ( @results && DEVEL_MODE ) {
        say "--- WINNER ---";
        print Dumper( $results[0] );
    }
    return @selected;
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
    my $levenshtein_weight     = $arg->{levenshtein_weight};
    my $token_weight           = 1 - $levenshtein_weight;
    my $concept_id_column      = $arg->{concept_id_column};
    my $allow_spelling_variant = $arg->{allow_spelling_variant};
    my $started_at             = _db_profile_enabled( $arg->{self} ) ? time : undef;
    my $candidate_rows         = 0;
    my $sequence               = 0;
    my $ts                     = Text::Similarity::Overlaps->new();

    my @results;
    while ( my $row = $sth->fetchrow_arrayref() ) {
        $candidate_rows++;
        my $candidate_label = $row->[$label_column];
        my $token_sim =
          Convert::Pheno::DB::Similarity::compute_token_similarity( $query,
            $candidate_label, $text_similarity_method, $ts );
        my $base_token_sim = $token_sim;
        my $spelling_variant;

        # Relaxed FTS retrieves labels through the unaffected words. Restore
        # partial token overlap only when exactly one remaining token pair is
        # close in spelling; all other fuzzy candidates retain the base score.
        if ($allow_spelling_variant) {
            $spelling_variant =
              Convert::Pheno::DB::Similarity::compute_single_token_spelling_similarity(
                $query, $candidate_label, $text_similarity_method );
            $token_sim = $spelling_variant->{adjusted_similarity}
              if $spelling_variant
              && $spelling_variant->{adjusted_similarity} > $token_sim;
        }
        my $lev_sim =
          Convert::Pheno::DB::Similarity::compute_normalized_levenshtein(
            $query, $candidate_label );
        my $composite =
          Convert::Pheno::DB::Similarity::combine_similarity_scores(
            $token_sim, $lev_sim, $token_weight, $levenshtein_weight );

        push @results,
          {
            id                    => _candidate_id( $ontology, $row, $id_column ),
            label                 => $candidate_label,
            token_similarity      => $token_sim,
            base_token_similarity => $base_token_sim,
            normalized_levenshtein => $lev_sim,
            match_score           => $composite,
            concept_id            => $row->[$concept_id_column],
            sequence              => $sequence,
            $spelling_variant
            ? (
                spelling_variant          => 1,
                spelling_query_token      => $spelling_variant->{query_token},
                spelling_candidate_token  => $spelling_variant->{candidate_token},
                spelling_token_similarity => $spelling_variant->{spelling_token_similarity},
              )
            : (),
          };
        $sequence++;
    }
    my @selected = _select_ranked_candidate(
        \@results, $candidate_rows, $min_score, $started_at
    );
    print Dumper \@results if DEVEL_MODE;
    return @selected;
}
1;
