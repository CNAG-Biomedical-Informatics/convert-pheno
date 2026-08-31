package Convert::Pheno::Source::OMOP;

use strict;
use warnings;
use autodie;

use File::Basename qw(basename);
use File::Find qw(find);
use File::Spec::Functions qw(catfile);
use File::Temp ();
use IO::Uncompress::Unzip qw($UnzipError);
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
                cleanup_guards => $collected->{cleanup_guards},
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
    push @{ $converter->{_source_cleanup_guards} },
      @{ $source->artifact('cleanup_guards') || [] };
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
    my ( $input_files, $cleanup_guards ) = _resolve_file_inputs($converter);
    for my $file ( @{$input_files} ) {
        my ( $table_name, $ext ) = _input_file_parts($file);

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
        cleanup_guards => $cleanup_guards,
    };
}

sub _resolve_file_inputs {
    my ($converter) = @_;
    my ( @files, @guards );
    my @inputs = @{ $converter->{in_files} || [] };
    my @packages = grep {
        defined $_ && !ref($_) && ( -d $_ || ( -f $_ && /\.zip\z/i ) )
    } @inputs;
    die "An OMOP directory or ZIP package must be supplied as the only input path\n"
      if @packages && @inputs > 1;

    for my $input (@inputs) {
        die "OMOP input path is missing\n"
          unless defined $input && !ref($input) && length $input;

        if ( -d $input ) {
            my @directory_files = _directory_table_files($input);
            die "OMOP input directory <$input> does not contain CSV or TSV table files\n"
              unless @directory_files;
            push @files, @directory_files;
            next;
        }

        if ( -f $input && $input =~ /\.zip\z/i ) {
            my ( $archive_files, $guard ) =
              _extract_zip_tables( $converter, $input );
            push @files,  @{$archive_files};
            push @guards, $guard;
            next;
        }

        if ( _is_supported_input_file($input) ) {
            push @files, $input;
            next;
        }

        die "OMOP input <$input> must be a CSV/TSV table, SQL dump, directory, or ZIP package\n";
    }

    die "OMOP input requires table files, a directory, a ZIP package, or an SQL dump\n"
      unless @files;
    _reject_duplicate_tables(\@files);
    return ( \@files, \@guards );
}

sub _directory_table_files {
    my ($directory) = @_;
    my @files;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                push @files, $File::Find::name
                  if -f $File::Find::name
                  && _is_table_file($File::Find::name);
            },
        },
        $directory,
    );
    return sort @files;
}

sub _extract_zip_tables {
    my ( $converter, $archive ) = @_;
    my $guard = File::Temp->newdir(
        'convert-pheno-omop-XXXXXX',
        TMPDIR  => 1,
        CLEANUP => 1,
    );
    my $directory = "$guard";
    my $zip = IO::Uncompress::Unzip->new($archive)
      or die "Cannot open OMOP ZIP package <$archive>: $UnzipError\n";

    my ( @files, %seen_names );
    my $total_bytes = 0;
    while (1) {
        my $header = $zip->getHeaderInfo;
        my $entry  = $header->{Name};

        if ( defined $entry && $entry !~ m{[\\/]\z} ) {
            _validate_zip_entry_name( $archive, $entry );
            if ( _is_table_file($entry) ) {
                my $name = $entry;
                $name =~ tr{\\}{/};
                $name =~ s{.*/}{};
                my $key = lc $name;
                die "OMOP ZIP package <$archive> contains duplicate table filename <$name>\n"
                  if $seen_names{$key}++;

                my $destination = catfile( $directory, $name );
                open my $fh, '>:raw', $destination
                  or die "Cannot extract OMOP ZIP entry <$entry>: $!\n";
                my $buffer;
                while (1) {
                    my $read = $zip->read($buffer);
                    die "Cannot read OMOP ZIP entry <$entry>: $UnzipError\n"
                      if !defined $read || $read < 0;
                    last if $read == 0;
                    $total_bytes += $read;
                    my $maximum = $converter->{max_archive_uncompressed_bytes} || 0;
                    die "OMOP ZIP package <$archive> exceeds the allowed uncompressed size\n"
                      if $maximum && $total_bytes > $maximum;
                    print {$fh} $buffer;
                }
                close $fh;
                push @files, $destination;
            }
        }

        last unless $zip->nextStream;
    }
    close $zip;

    die "OMOP ZIP package <$archive> does not contain CSV or TSV table files\n"
      unless @files;
    return ( \@files, $guard );
}

sub _validate_zip_entry_name {
    my ( $archive, $entry ) = @_;
    my $normalized = $entry;
    $normalized =~ tr{\\}{/};
    die "OMOP ZIP package <$archive> contains an unsafe entry <$entry>\n"
      if $normalized =~ m{\A/}
      || $normalized =~ m{\A[A-Za-z]:/}
      || $normalized =~ m{(?:\A|/)\.\.(?:/|\z)};
    return 1;
}

sub _reject_duplicate_tables {
    my ($files) = @_;
    my %seen;
    for my $file ( @{$files} ) {
        my $table = _table_name($file);
        next unless defined $table;
        die "OMOP input contains table <$table> more than once\n"
          if $seen{$table}++;
    }
    return 1;
}

sub _table_name {
    my ($file) = @_;
    my $name = basename($file);
    return uc($1) if $name =~ /\A(.+)\.(?:csv|tsv)(?:\.gz)?\z/i;
    return;
}

sub _input_file_parts {
    my ($file) = @_;
    my $name = basename($file);
    return ( uc($1), lc($2) )
      if $name =~ /\A(.+?)(\.(?:csv|tsv|sql)(?:\.gz)?)\z/i;
    return ( uc($name), q{} );
}

sub _is_table_file {
    my ($file) = @_;
    return defined $file && $file =~ /\.(?:csv|tsv)(?:\.gz)?\z/i;
}

sub _is_supported_input_file {
    my ($file) = @_;
    return defined $file
      && $file =~ /\.(?:csv|tsv|sql)(?:\.gz)?\z/i;
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
