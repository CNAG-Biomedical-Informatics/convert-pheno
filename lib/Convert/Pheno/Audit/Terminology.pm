package Convert::Pheno::Audit::Terminology;

use strict;
use warnings;

use IO::Compress::Gzip qw($GzipError);

my @COLUMNS = qw(
  row
  source_record
  source_field
  source_value
  source_label
  lookup_query
  lookup_column
  converted_term_label
  converted_term_id
  ontology
  configured_search_mode
  effective_search_mode
  text_similarity_method
  min_text_similarity_score
  levenshtein_weight
  match_status
  decision_reason
  review_action
  match_source
  lookup_resolution
  fallback_action
  retrieval_path
  best_candidate_label
  best_candidate_id
  best_candidate_score
  score_margin
);

my %NUMERIC_COLUMN = map { $_ => 1 } qw(
  row
  min_text_similarity_score
  levenshtein_weight
  best_candidate_score
  score_margin
);

use constant MAX_XLSX_DATA_ROWS => 1_048_575;
use constant PREVIEW_ROWS_PER_ACTION => 100;

my @REVIEW_ACTIONS = qw(
  resolve_or_accept_fallback
  review_similarity
  review_source_fallback
  keep
);

sub new {
    my ( $class, %arg ) = @_;
    my $path = $arg{path};
    die "A terminology audit output path is required\n"
      unless defined $path && length $path;

    my $self = bless {
        path    => $path,
        config  => $arg{config} || {},
        counts  => {
            resolved   => 0,
            review     => 0,
            unresolved => 0,
            not_searched => 0,
        },
        action_counts => { map { $_ => 0 } @REVIEW_ACTIONS },
        preview_rows => { map { $_ => [] } @REVIEW_ACTIONS },
        total_rows   => 0,
    }, $class;

    if ( $path =~ /\.tsv(?:\.gz)?\z/i ) {
        $self->_open_tsv;
    }
    elsif ( $path =~ /\.xlsx\z/i ) {
        $self->_open_xlsx;
    }
    else {
        die "Unsupported terminology audit format for <$path>; use .tsv, .tsv.gz, or .xlsx\n";
    }

    return $self;
}

sub columns {
    return wantarray ? @COLUMNS : [@COLUMNS];
}

sub write_row {
    my ( $self, $row ) = @_;
    die "A terminology audit row must be a hash reference\n"
      unless ref $row eq 'HASH';

    my %output_row = %{$row};
    $output_row{review_action} //= _review_action(\%output_row);

    if ( $self->{format} eq 'xlsx' ) {
        $self->_write_xlsx_row(\%output_row);
    }
    else {
        $self->_write_tsv_row(\%output_row);
    }

    my $category = _review_category(\%output_row);
    my $action   = $output_row{review_action};
    $self->{counts}{$category}++;
    $self->{action_counts}{$action}++;
    if ( @{ $self->{preview_rows}{$action} } < PREVIEW_ROWS_PER_ACTION ) {
        push @{ $self->{preview_rows}{$action} },
          { map { $_ => $output_row{$_} } @COLUMNS };
    }
    $self->{total_rows}++;
    return 1;
}

sub review {
    my ($self) = @_;
    my @rows = map { @{ $self->{preview_rows}{$_} } } @REVIEW_ACTIONS;
    my %settings = map { $_ => $self->{config}{$_} }
      qw(search text_similarity_method min_text_similarity_score levenshtein_weight);

    return {
        total_decisions          => $self->{total_rows},
        counts                   => { %{ $self->{action_counts} } },
        rows                     => \@rows,
        preview_rows             => scalar @rows,
        preview_limit_per_action => PREVIEW_ROWS_PER_ACTION,
        truncated                => $self->{total_rows} > @rows ? 1 : 0,
        settings                 => \%settings,
    };
}

sub close {
    my ($self) = @_;
    return 1 if $self->{closed};

    if ( $self->{format} eq 'xlsx' ) {
        $self->_close_xlsx;
    }
    else {
        close $self->{fh}
          or die "Failed to finalize terminology audit '$self->{path}': $!\n";
    }

    $self->{closed} = 1;
    return 1;
}

sub _open_tsv {
    my ($self) = @_;
    my $path = $self->{path};
    my $fh;

    if ( $path =~ /\.gz\z/i ) {
        $fh = IO::Compress::Gzip->new($path)
          or die "Cannot gzip <$path>: $GzipError\n";
        binmode( $fh, ':encoding(UTF-8)' );
        $self->{format} = 'tsv_gzip';
    }
    else {
        open $fh, '>:encoding(UTF-8)', $path
          or die "Cannot write terminology audit <$path>: $!\n";
        $self->{format} = 'tsv';
    }

    print {$fh} join( "\t", @COLUMNS ), "\n";
    $self->{fh} = $fh;
    return 1;
}

sub _write_tsv_row {
    my ( $self, $row ) = @_;
    my @values = map {
        my $value = $row->{$_};
        $value = sprintf '%.4f', $value
          if defined $value
          && ( $_ eq 'best_candidate_score' || $_ eq 'score_margin' );
        _tsv_field($value);
    } @COLUMNS;

    print { $self->{fh} } join( "\t", @values ), "\n";
    return 1;
}

sub _open_xlsx {
    my ($self) = @_;

    eval { require Excel::Writer::XLSX; 1 }
      or die
"Excel::Writer::XLSX is required for .xlsx terminology audits. Install the distribution dependencies and retry.\n";

    my $workbook = Excel::Writer::XLSX->new( $self->{path} )
      or die "Failed to create XLSX terminology audit '$self->{path}'\n";
    my $summary = $workbook->add_worksheet('Summary');
    my $audit   = $workbook->add_worksheet('Terminology Audit');

    my $header_format = $workbook->add_format(
        bold     => 1,
        color    => 'white',
        bg_color => '#1F4E78',
        border   => 1,
        valign   => 'vcenter',
    );
    my $summary_label_format = $workbook->add_format( bold => 1 );
    my $score_format = $workbook->add_format( num_format => '0.0000' );

    my %row_format = (
        resolved => $workbook->add_format( bg_color => '#E2F0D9' ),
        review => $workbook->add_format( bg_color => '#FFF2CC' ),
        unresolved => $workbook->add_format( bg_color => '#FCE4D6' ),
        not_searched => $workbook->add_format( bg_color => '#E7E6E6' ),
    );
    my %legend_format = (
        resolved => $workbook->add_format(
            bold => 1, color => 'white', bg_color => '#1B5E20', border => 1,
        ),
        review => $workbook->add_format(
            bold => 1, color => '#5F4300', bg_color => '#FFD966', border => 1,
        ),
        unresolved => $workbook->add_format(
            bold => 1, color => 'white', bg_color => '#8B0000', border => 1,
        ),
        not_searched => $workbook->add_format(
            bold => 1, color => '#404040', bg_color => '#BFBFBF', border => 1,
        ),
    );

    $workbook->set_properties(
        title    => 'Convert-Pheno terminology audit',
        subject  => 'Terminology resolution and candidate review',
        author   => 'Convert-Pheno',
        comments => 'Colors indicate review priority, not clinical confidence',
    );

    $summary->write_row( 0, 0, [ 'Field', 'Value' ], $header_format );
    $summary->set_column( 0, 0, 31 );
    $summary->set_column( 1, 1, 58 );
    $summary->freeze_panes(1, 0);

    for my $index ( 0 .. $#COLUMNS ) {
        $audit->write_string( 0, $index, $COLUMNS[$index], $header_format );
    }
    $audit->freeze_panes( 1, 3 );
    $audit->set_selection( 1, 0 );
    $audit->set_zoom(85);

    my @widths = (
        8, 18, 25, 28, 28, 28, 18, 32, 22, 14,
        20, 20, 20, 18, 18, 16, 27, 29, 16, 20,
        17, 20, 32, 22, 17, 17,
    );
    for my $index ( 0 .. $#widths ) {
        $audit->set_column( $index, $index, $widths[$index] );
    }

    # Keep the default workbook focused on review while retaining all evidence
    # for users who choose to unhide the technical columns.
    my @hidden_columns = ( 6, 9 .. 15, 18 .. 21 );
    for my $index (@hidden_columns) {
        $audit->set_column( $index, $index, $widths[$index], undef, 1 );
    }

    $self->{format}               = 'xlsx';
    $self->{workbook}             = $workbook;
    $self->{summary_worksheet}    = $summary;
    $self->{audit_worksheet}      = $audit;
    $self->{header_format}        = $header_format;
    $self->{summary_label_format} = $summary_label_format;
    $self->{score_format}         = $score_format;
    $self->{row_format}           = \%row_format;
    $self->{legend_format}        = \%legend_format;
    $self->{next_xlsx_row}        = 1;
    return 1;
}

sub _write_xlsx_row {
    my ( $self, $row ) = @_;
    die "XLSX terminology audits support at most "
      . MAX_XLSX_DATA_ROWS
      . " decisions; use .tsv.gz for larger runs\n"
      if $self->{next_xlsx_row} > MAX_XLSX_DATA_ROWS;

    my $worksheet = $self->{audit_worksheet};
    my $xlsx_row = $self->{next_xlsx_row};

    for my $index ( 0 .. $#COLUMNS ) {
        my $column = $COLUMNS[$index];
        my $value = $row->{$column};
        next unless defined $value && length $value;

        if ( $NUMERIC_COLUMN{$column} && _is_number($value) ) {
            my $format =
              $column eq 'best_candidate_score' || $column eq 'score_margin'
              ? $self->{score_format}
              : undef;
            $worksheet->write_number( $xlsx_row, $index, $value, $format );
        }
        else {
            # Explicit string writes prevent source values beginning with '='
            # from being interpreted as spreadsheet formulas.
            $worksheet->write_string( $xlsx_row, $index, "$value" );
        }
    }

    $self->{next_xlsx_row}++;
    return 1;
}

sub _close_xlsx {
    my ($self) = @_;
    my $summary = $self->{summary_worksheet};
    my $config  = $self->{config};
    my $counts  = $self->{counts};

    my @summary_rows = (
        [ 'report_format',              'XLSX' ],
        [ 'configured_search_mode',     $config->{search} ],
        [ 'text_similarity_method',     $config->{text_similarity_method} ],
        [ 'min_text_similarity_score',  $config->{min_text_similarity_score} ],
        [ 'levenshtein_weight',         $config->{levenshtein_weight} ],
        [ 'total_decisions',            $self->{total_rows} ],
        [ 'exact_or_direct',            $counts->{resolved} ],
        [ 'similarity_review',          $counts->{review} ],
        [ 'unresolved',                 $counts->{unresolved} ],
        [ 'not_searched_or_source_fallback', $counts->{not_searched} ],
    );
    for my $index ( 0 .. $#summary_rows ) {
        $summary->write_string(
            $index + 1,
            0,
            $summary_rows[$index][0],
            $self->{summary_label_format},
        );
        my $value = $summary_rows[$index][1];
        if ( defined $value && _is_number($value) ) {
            $summary->write_number( $index + 1, 1, $value );
        }
        else {
            $summary->write_string( $index + 1, 1, defined $value ? "$value" : q{} );
        }
    }

    my $legend_row = @summary_rows + 3;
    $summary->write_string( $legend_row, 0, 'Review colors', $self->{summary_label_format} );
    my @legend = (
        [ resolved     => 'Exact, direct, or configured resolution' ],
        [ review       => 'Similarity or spelling result to review' ],
        [ unresolved   => 'No term emitted' ],
        [ not_searched => 'Not searched or source fallback' ],
    );
    for my $index ( 0 .. $#legend ) {
        my ( $category, $description ) = @{ $legend[$index] };
        $summary->write_string(
            $legend_row + $index + 1,
            0,
            $category,
            $self->{legend_format}{$category},
        );
        $summary->write_string( $legend_row + $index + 1, 1, $description );
    }
    $summary->write_string(
        $legend_row + @legend + 2,
        0,
        'Interpretation',
        $self->{summary_label_format},
    );
    $summary->write_string(
        $legend_row + @legend + 2,
        1,
        'Colors prioritize review; they do not measure clinical confidence.',
    );
    $summary->write_string(
        $legend_row + @legend + 4,
        0,
        'Workbook view',
        $self->{summary_label_format},
    );
    $summary->write_string(
        $legend_row + @legend + 4,
        1,
        'Technical audit columns are present but hidden by default.',
    );

    my $audit = $self->{audit_worksheet};
    $audit->autofilter( 0, 0, $self->{total_rows}, $#COLUMNS );
    if ( $self->{total_rows} ) {
        my $last_row = $self->{total_rows} + 1;
        my $range = "A2:Z$last_row";
        my @rules = (
            [ unresolved => '=$P2="not_found"' ],
            [ not_searched => '=OR($P2="not_searched",$Q2="source_fallback")' ],
            [ review => '=AND($P2<>"not_found",$P2<>"not_searched",$Q2<>"source_fallback",OR($T2="similarity",$V2="one_token_relaxed"))' ],
            [ resolved => '=AND($P2<>"not_found",$P2<>"not_searched",$Q2<>"source_fallback",$T2<>"similarity",$V2<>"one_token_relaxed")' ],
        );
        for my $rule (@rules) {
            $audit->conditional_formatting(
                $range,
                {
                    type     => 'formula',
                    criteria => $rule->[1],
                    format   => $self->{row_format}{ $rule->[0] },
                }
            );
        }
    }

    $self->{workbook}->close()
      or die "Failed to finalize XLSX terminology audit '$self->{path}'\n";
    return 1;
}

sub _review_category {
    my ($row) = @_;
    return 'unresolved' if ( $row->{match_status} // q{} ) eq 'not_found';
    return 'not_searched'
      if ( $row->{match_status} // q{} ) eq 'not_searched'
      || ( $row->{decision_reason} // q{} ) eq 'source_fallback';
    return 'review'
      if ( $row->{lookup_resolution} // q{} ) eq 'similarity'
      || ( $row->{retrieval_path} // q{} ) eq 'one_token_relaxed';
    return 'resolved';
}

sub _review_action {
    my ($row) = @_;
    my $category = _review_category($row);
    return 'keep'                       if $category eq 'resolved';
    return 'review_similarity'          if $category eq 'review';
    return 'resolve_or_accept_fallback' if $category eq 'unresolved';
    return 'review_source_fallback';
}

sub _tsv_field {
    my ($value) = @_;
    return q{} unless defined $value;
    $value =~ s/[\t\r\n]+/ /g;
    return $value;
}

sub _is_number {
    my ($value) = @_;
    return defined $value
      && $value =~ /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?\z/;
}

1;
