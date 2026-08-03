package Test::ConvertPheno;

use strict;
use warnings;

use Exporter 'import';
use Config;
use File::Compare qw(compare);
use File::Path qw(mkpath remove_tree);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use IPC::Open3 qw(open3);
use IO::Uncompress::Gunzip;
use IO::Uncompress::Unzip qw($UnzipError);
use JSON::XS qw(decode_json);
use Text::CSV_XS;
use lib qw(./lib ../lib);
use Convert::Pheno;
use Convert::Pheno::DB::Bundle qw(bundled_database_path);
use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);

our @EXPORT_OK = qw(
  build_convert
  is_ld_arch
  is_windows
  has_ohdsi_db
  test_ohdsi_db_dir
  slurp_file
  load_json_file
  read_first_json_object
  temp_output_file
  json_files_match
  write_json_file
  csv_headers_from_file
  load_csv_table
  write_csv_rows
  load_data_file
  structured_files_match
  cli_script_path
  test_tmpdir
  ensure_clean_dir
  remove_dir_if_exists
  csv_files_match
  gunzip_file_content
  slurp_zip_member
  run_command_capture
);

my $TEST_OHDSI_DB_DIR;

sub build_convert {
    my (%args) = @_;

    my %data = (
        in_files             => [],
        in_textfile          => 1,
        self_validate_schema => 0,
        schema_file          => 'share/schema/mapping-v2.json',
        stream               => 0,
        omop_tables          => [],
        search               => 'exact',
        test                 => 1,
    );

    for my $key ( keys %args ) {
        next unless defined $args{$key};
        $data{$key} = $args{$key};
    }

    return Convert::Pheno->new( \%data );
}

sub is_ld_arch {
    return $Config{archname} =~ /-ld\b/ ? 1 : 0;
}

sub is_windows {
    return ( $^O eq 'MSWin32' || $^O eq 'cygwin' ) ? 1 : 0;
}

sub has_ohdsi_db {
    return -f bundled_database_path( $Convert::Pheno::share_dir, 'ohdsi' )
      ? 1
      : 0;
}

sub test_ohdsi_db_dir {
    return $TEST_OHDSI_DB_DIR if defined $TEST_OHDSI_DB_DIR;

    $TEST_OHDSI_DB_DIR = tempdir(
        'convert-pheno-ohdsi-XXXXXX',
        TMPDIR  => 1,
        CLEANUP => 1,
    );
    my $db_file = File::Spec->catfile( $TEST_OHDSI_DB_DIR, 'ohdsi.db' );
    my $fixture      = 't/fixtures/ohdsi-concepts.tsv';
    my $maps_fixture = 't/fixtures/ohdsi-maps-to.tsv';

    open my $fh, '<:encoding(UTF-8)', $fixture
      or die "Could not open test vocabulary '$fixture': $!";
    my $csv = Text::CSV_XS->new( { binary => 1, sep_char => "\t" } );
    my $headers = $csv->getline($fh)
      or die "Test vocabulary '$fixture' has no header";
    $csv->column_names( @{$headers} );

    require DBI;
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$db_file",
        q{},
        q{},
        {
            AutoCommit => 1,
            PrintError => 0,
            RaiseError => 1,
        },
    );
    # Mirror the production schema so query preparation and bounded fuzzy
    # retrieval are exercised against FTS5 rather than a compatibility table.
    $dbh->do(
        'CREATE TABLE OHDSI_table ('
          . 'label TEXT, id TEXT, concept_id INTEGER, vocabulary_id TEXT, '
          . 'domain_id TEXT, concept_class_id TEXT, standard_concept TEXT, '
          . 'valid_start_date TEXT, valid_end_date TEXT, invalid_reason TEXT)'
    );
    $dbh->do(
        'CREATE VIRTUAL TABLE OHDSI_fts USING fts5(label, id, concept_id, vocabulary_id)'
    );
    $dbh->do(
        'CREATE TABLE OHDSI_maps_to ('
          . 'source_concept_id INTEGER NOT NULL, target_concept_id INTEGER NOT NULL, '
          . 'relationship_id TEXT NOT NULL, valid_start_date TEXT NOT NULL, '
          . 'valid_end_date TEXT NOT NULL, invalid_reason TEXT NOT NULL, '
          . 'PRIMARY KEY (source_concept_id, target_concept_id, relationship_id)) WITHOUT ROWID'
    );

    my $insert_table = $dbh->prepare(
        'INSERT INTO OHDSI_table ('
          . 'label, id, concept_id, vocabulary_id, domain_id, concept_class_id, '
          . 'standard_concept, valid_start_date, valid_end_date, invalid_reason'
          . ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    my $insert_fts = $dbh->prepare(
        'INSERT INTO OHDSI_fts (label, id, concept_id, vocabulary_id) VALUES (?, ?, ?, ?)'
    );
    my @concept_columns = qw(
      label id concept_id vocabulary_id domain_id concept_class_id
      standard_concept valid_start_date valid_end_date invalid_reason
    );
    while ( my $row = $csv->getline_hr($fh) ) {
        my @values = map { $row->{$_} // q{} } @concept_columns;
        $insert_table->execute(@values);
        $insert_fts->execute( @values[ 0 .. 3 ] );
    }
    close $fh;

    open my $maps_fh, '<:encoding(UTF-8)', $maps_fixture
      or die "Could not open test mappings '$maps_fixture': $!";
    my $maps_csv = Text::CSV_XS->new( { binary => 1, sep_char => "\t" } );
    my $maps_headers = $maps_csv->getline($maps_fh)
      or die "Test mappings '$maps_fixture' has no header";
    $maps_csv->column_names( @{$maps_headers} );
    my @mapping_columns = qw(
      source_concept_id target_concept_id relationship_id
      valid_start_date valid_end_date invalid_reason
    );
    my $insert_mapping = $dbh->prepare(
        'INSERT INTO OHDSI_maps_to ('
          . join( q{, }, @mapping_columns )
          . ') VALUES (?, ?, ?, ?, ?, ?)'
    );
    while ( my $row = $maps_csv->getline_hr($maps_fh) ) {
        $insert_mapping->execute(
            map { $row->{$_} // q{} } @mapping_columns
        );
    }
    close $maps_fh;

    $dbh->do(
        'CREATE INDEX idx_ohdsi_label_nocase ON OHDSI_table(label COLLATE NOCASE)'
    );
    $dbh->do(
        'CREATE INDEX idx_ohdsi_id_nocase ON OHDSI_table(id COLLATE NOCASE)'
    );
    $dbh->do('CREATE UNIQUE INDEX idx_ohdsi_concept_id ON OHDSI_table(concept_id)');
    $dbh->do(
        'CREATE INDEX idx_ohdsi_vocabulary_code_nocase '
          . 'ON OHDSI_table(vocabulary_id COLLATE NOCASE, id COLLATE NOCASE)'
    );
    $dbh->do(
        'CREATE INDEX idx_ohdsi_standard_domain_label_nocase '
          . 'ON OHDSI_table(domain_id COLLATE NOCASE, standard_concept, label COLLATE NOCASE) '
          . q{WHERE invalid_reason = ''}
    );
    $dbh->disconnect;

    return $TEST_OHDSI_DB_DIR;
}

sub slurp_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub slurp_zip_member {
    my ( $archive_path, $member_name ) = @_;
    my $zip = IO::Uncompress::Unzip->new($archive_path)
      or die "Cannot open ZIP archive '$archive_path': $UnzipError\n";

    while (1) {
        my $header = $zip->getHeaderInfo();
        my $name   = $header->{Name};
        my $text   = q{};
        my $buffer;

        while ( $zip->read($buffer) > 0 ) {
            $text .= $buffer;
        }

        return $text if $name eq $member_name;
        last unless $zip->nextStream();
    }

    die "Archive member '$member_name' not found in '$archive_path'\n";
}

sub load_json_file {
    my ($file) = @_;
    return decode_json( slurp_file($file) );
}

sub read_first_json_object {
    my ($file) = @_;
    my $json = load_json_file($file);
    die "Expected a JSON array in $file" unless ref $json eq 'ARRAY';
    return $json->[0];
}

sub test_tmpdir {
    return File::Spec->tmpdir();
}

sub temp_output_file {
    my (%args) = @_;
    my $suffix = exists $args{suffix} ? $args{suffix} : '.json';
    my $dir    = exists $args{dir}    ? $args{dir}    : 't';
    $dir = test_tmpdir() if !defined $dir || !-d $dir;
    my ( $fh, $file ) = tempfile( DIR => $dir, SUFFIX => $suffix, UNLINK => 1 );
    close $fh or die "Could not close temporary output placeholder '$file': $!";

    # Return a reserved path rather than an existing file. Windows cannot move
    # an open File::Temp placeholder when the CLI preserves atomic output.
    unlink $file if -e $file
      or die "Could not remove temporary output placeholder '$file': $!";

    return $file;
}

sub run_command_capture {
    my (%args) = @_;
    my $command = $args{command};
    die 'run_command_capture requires a command array reference'
      unless ref $command eq 'ARRAY' && @{$command};

    my ( $stdin,  undef ) = tempfile( DIR => test_tmpdir(), UNLINK => 1 );
    my ( $stdout, undef ) = tempfile( DIR => test_tmpdir(), UNLINK => 1 );
    my ( $stderr, undef ) = tempfile( DIR => test_tmpdir(), UNLINK => 1 );
    binmode $_, ':raw' for ( $stdin, $stdout, $stderr );

    print {$stdin} $args{stdin} if defined $args{stdin};
    seek $stdin, 0, 0 or die "Could not rewind command input: $!";

    # Direct file handles avoid the pipe EOF deadlocks that IPC::Open3 can
    # trigger on Windows while preserving separate stdout and stderr capture.
    my $pid = open3(
        '<&' . fileno($stdin),
        '>&' . fileno($stdout),
        '>&' . fileno($stderr),
        @{$command},
    );
    waitpid( $pid, 0 );
    my $status = $?;

    seek $stdout, 0, 0 or die "Could not rewind command output: $!";
    seek $stderr, 0, 0 or die "Could not rewind command errors: $!";
    local $/;
    my $output = <$stdout> // q{};
    my $errors = <$stderr> // q{};

    return ( $status == -1 ? -1 : $status >> 8, $output, $errors );
}

sub json_files_match {
    my ( $expected, $got ) = @_;
    return compare( $expected, $got ) == 0 ? 1 : 0;
}

sub write_json_file {
    my ( $file, $data ) = @_;
    return io_yaml_or_json(
        {
            filepath => $file,
            mode     => 'write',
            data     => $data,
        }
    );
}

sub csv_headers_from_file {
    my ($file) = @_;
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    my $csv = Text::CSV_XS->new( { binary => 1, sep_char => ';' } );
    my $row = $csv->getline($fh);
    close $fh;
    return $row;
}

sub load_csv_table {
    my ($file) = @_;
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    my $csv = Text::CSV_XS->new( { binary => 1, sep_char => ';' } );
    my $headers = $csv->getline($fh);
    my @rows;
    while ( my $row = $csv->getline($fh) ) {
        my %item;
        @item{@$headers} = @$row;
        push @rows, \%item;
    }
    close $fh;
    return \@rows;
}

sub write_csv_rows {
    my ( $file, $headers, $rows ) = @_;
    open my $fh, '>', $file or die "Could not open file '$file': $!";
    my $csv = Text::CSV_XS->new( { binary => 1, eol => "\n", sep_char => ';' } );
    $csv->print( $fh, $headers );
    for my $row (@$rows) {
        $csv->print( $fh, [ map { $row->{$_} } @$headers ] );
    }
    close $fh;
    return 1;
}

sub load_data_file {
    my ($file) = @_;
    return io_yaml_or_json(
        {
            filepath => $file,
            mode     => 'read',
        }
    );
}

sub _strip_convertpheno {
    my ($data) = @_;

    if ( ref $data eq 'HASH' ) {
        delete $data->{convertPheno};
        _strip_convertpheno($_) for values %{$data};
    }
    elsif ( ref $data eq 'ARRAY' ) {
        _strip_convertpheno($_) for @{$data};
    }

    return $data;
}

sub structured_files_match {
    my ( $expected, $got ) = @_;
    my $expected_data = load_data_file($expected);
    my $got_data      = load_data_file($got);
    _strip_convertpheno($expected_data);
    _strip_convertpheno($got_data);
    my $json = JSON::XS->new->canonical;
    return $json->encode($expected_data) eq $json->encode($got_data) ? 1 : 0;
}

sub cli_script_path {
    return File::Spec->catfile( $Bin, '..', 'bin', 'convert-pheno' );
}

sub ensure_clean_dir {
    my ($dir) = @_;
    remove_tree($dir) if -d $dir;
    mkpath($dir);
    return $dir;
}

sub remove_dir_if_exists {
    my ($dir) = @_;
    remove_tree($dir) if -d $dir;
    return 1;
}

sub csv_files_match {
    my ( $expected, $got ) = @_;
    return compare( $expected, $got ) == 0 ? 1 : 0;
}

sub gunzip_file_content {
    my ($file) = @_;
    my $z = IO::Uncompress::Gunzip->new($file)
      or die "Cannot gunzip '$file': $IO::Uncompress::Gunzip::GunzipError";
    my $content = do { local $/; <$z> };
    $z->close();
    return $content;
}

1;
