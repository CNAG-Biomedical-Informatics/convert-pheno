package Convert::Pheno::Source::OMOP;

use strict;
use warnings;
use autodie;

use File::Basename qw(fileparse);
use List::Util qw(any);
use Storable qw(dclone);

use Convert::Pheno::IO::CSVHandler qw(read_csv read_sqldump sqldump2csv);
use Convert::Pheno::OMOP::Definitions;
use Convert::Pheno::OMOP::ParticipantStream qw(
  omop_init_caches_and_metadata
  omop_prepare_data_shape
  omop_require_core_tables
);
use Convert::Pheno::Source::Result;

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $collected = _collect_omop_input( $self->{converter} );

    return Convert::Pheno::Source::Result->new(
        {
            data      => $collected->{data},
            owned     => $collected->{owned},
            artifacts => {
                kind          => $collected->{kind},
                filepath_sql  => $collected->{filepath_sql},
                filepaths_csv => $collected->{filepaths_csv},
            },
        }
    );
}

sub prepare {
    my ($self) = @_;
    my $converter = $self->{converter};
    return 1 if $converter->{omop_input_prepared}
      && exists $converter->{data};

    $converter->{_omop_source_data} = $converter->{data}
      if exists $converter->{data}
      && !exists $converter->{_omop_source_data};
    $converter->{data} = $converter->{_omop_source_data}
      if !exists $converter->{data}
      && exists $converter->{_omop_source_data};

    $converter->{method_ori} = 'omop2bff'
      unless exists $converter->{method_ori};
    _ensure_specimen_table_for_biosamples($converter);
    $converter->{prev_omop_tables} = [ @{ $converter->{omop_tables} } ];

    my $source = $self->load;
    my $data   = $source->data;
    omop_require_core_tables( $converter, $data );
    _require_specimen_for_biosamples(
        $converter,
        $data,
        {
            filepath_sql  => $source->artifact('filepath_sql'),
            filepaths_csv => $source->artifact('filepaths_csv'),
        },
    );
    omop_init_caches_and_metadata( $converter, $data );
    omop_prepare_data_shape( $converter, $data );
    $converter->{_owns_prepared_data} = 1 if $source->owned;
    delete $converter->{mapping_file_derived_entity_overrides};

    $converter->{filepath_sql} = $source->artifact('filepath_sql')
      if defined $source->artifact('filepath_sql');
    $converter->{filepaths_csv} = $source->artifact('filepaths_csv') || [];
    $converter->{omop_input_prepared} = 1;
    return 1;
}

sub _requests_biosamples {
    my ($converter) = @_;
    return scalar grep { $_ eq 'biosamples' }
      @{ $converter->{entities} || [] };
}

sub _ensure_specimen_table_for_biosamples {
    my ($converter) = @_;
    return 1 unless _requests_biosamples($converter);
    return 1 if grep { $_ eq 'SPECIMEN' }
      @{ $converter->{omop_tables} || [] };
    $converter->{omop_tables} = [
        @{ $converter->{omop_tables} || [] },
        'SPECIMEN',
    ];
    return 1;
}

sub _require_specimen_for_biosamples {
    my ( $converter, $data, $context ) = @_;
    return 1 unless _requests_biosamples($converter);
    return 1 if exists $data->{SPECIMEN};
    return 1 if _stream_source_has_specimen( $converter, $context );
    die "The entity <biosamples> requires the OMOP table <SPECIMEN>\n";
}

sub _stream_source_has_specimen {
    my ( $converter, $context ) = @_;
    return 0 unless $converter->{stream};
    return 0 unless ref($context) eq 'HASH';

    if ( defined $context->{filepath_sql} && length $context->{filepath_sql} ) {
        return scalar grep { $_ eq 'SPECIMEN' }
          @{ $converter->{prev_omop_tables} || [] };
    }
    for my $file ( @{ $context->{filepaths_csv} || [] } ) {
        return 1
          if $file =~ m{(?:^|/|\\)SPECIMEN\.(?:csv|tsv)(?:\.gz)?$}i;
    }
    return 0;
}

sub _collect_omop_input {
    my ($converter) = @_;

    if ( exists $converter->{data} ) {
        $converter->{omop_cli} = 0;

        my $data = $converter->{data};
        die "OMOP in-memory input must be an object keyed by table name\n"
          unless ref($data) eq 'HASH';

        my %supported = map { $_ => 1 } @omop_supported_tables;
        my $normalized = {};
        for my $input_table ( keys %{$data} ) {
            my $table = uc($input_table);
            die "<$input_table> is not a valid table in OMOP-CDM\n"
              unless $supported{$table};
            die "OMOP input contains table <$table> more than once\n"
              if exists $normalized->{$table};

            my $rows = $data->{$input_table};
            die "OMOP table <$table> must contain an array of row objects\n"
              unless ref($rows) eq 'ARRAY';
            for my $row ( @{$rows} ) {
                die "OMOP table <$table> must contain only row objects\n"
                  unless ref($row) eq 'HASH';
            }

            # OMOP cache construction drains owned arrays. Clone module/API
            # input so callers retain their original table package.
            $normalized->{$table} = dclone($rows);
        }

        return {
            kind          => 'memory',
            data          => $normalized,
            owned         => 1,
            filepath_sql  => undef,
            filepaths_csv => [],
        };
    }

    $converter->{omop_cli} = 1;

    my $data = {};
    my $filepath_sql;
    my @filepaths_csv_stream;
    my @exts = map { $_, $_ . '.gz' } qw(.csv .tsv .sql);

    for my $file ( @{ $converter->{in_files} } ) {
        my ( $table_name, undef, $ext ) = fileparse( $file, @exts );

        if ( $ext =~ m/\.sql/i ) {
            print "> Param: --max-lines-sql = $converter->{max_lines_sql}\n"
              if $converter->{verbose};

            if ( !$converter->{stream} ) {
                print "> Mode : --no-stream\n\n" if $converter->{verbose};
                my $sql_headers;
                ( $data, $sql_headers ) =
                  read_sqldump( { in => $file, self => $converter } );
                sqldump2csv( $data, $converter->{out_dir}, $sql_headers )
                  if $converter->{sql2csv};
            }
            else {
                print "> Mode : --stream\n\n" if $converter->{verbose};
                _with_temp_field(
                    $converter,
                    'omop_tables',
                    [@stream_ram_memory_tables],
                    sub {
                        ( $data, undef ) =
                          read_sqldump( { in => $file, self => $converter } );
                        return 1;
                    }
                );
            }

            print "> Parameter --max-lines-sql set to: $converter->{max_lines_sql}\n\n"
              if $converter->{verbose};
            $filepath_sql = $file;
            last;
        }

        warn "<$table_name> is not a valid table in OMOP-CDM\n" and next
          unless any { $_ eq $table_name } @omop_supported_tables;

        my $message = "Reading <$table_name> and storing it in RAM memory...";
        if ( !$converter->{stream} ) {
            print "$message\n"
              if $converter->{verbose} || $converter->{debug};
            $data->{$table_name} = read_csv(
                { in => $file, sep => $converter->{sep}, self => $converter }
            );
        }
        elsif ( any { $_ eq $table_name } @stream_ram_memory_tables ) {
            print "$message\n"
              if $converter->{verbose} || $converter->{debug};
            $data->{$table_name} = read_csv(
                { in => $file, sep => $converter->{sep}, self => $converter }
            );
        }
        else {
            push @filepaths_csv_stream, $file;
        }
    }

    return {
        kind          => ( $filepath_sql ? 'sql' : 'csv' ),
        data          => $data,
        owned         => 1,
        filepath_sql  => $filepath_sql,
        filepaths_csv => \@filepaths_csv_stream,
    };
}

sub _with_temp_field {
    my ( $converter, $field, $value, $code ) = @_;
    my $had = exists $converter->{$field};
    my $old = $had ? $converter->{$field} : undef;
    $converter->{$field} = $value;

    my ( $ok, $result );
    $ok = eval {
        $result = $code->();
        1;
    };
    my $error = $@;

    if ($had) { $converter->{$field} = $old }
    else      { delete $converter->{$field} }

    die $error unless $ok;
    return $result;
}

1;
