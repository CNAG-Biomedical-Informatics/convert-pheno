package Convert::Pheno::Source::TablePackage;

use strict;
use warnings;

use Encode qw(decode FB_CROAK);
use Exporter 'import';
use File::Basename qw(basename);
use File::Find qw(find);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Unzip qw($UnzipError);
use Path::Tiny qw(path);
use Storable qw(dclone);
use Text::CSV_XS;

our @EXPORT_OK = qw(load_table_package normalize_table_name);

sub load_table_package {
    my ( $converter, $profile ) = @_;
    die "A table-package profile is required\n"
      unless defined $profile && !ref($profile) && length $profile;

    return _memory_package( $converter->{data}, $profile )
      if exists $converter->{data};

    my @inputs = @{ $converter->{in_files} || [] };
    push @inputs, $converter->{in_file}
      if !@inputs && defined $converter->{in_file};
    die "$profile input requires table files, a directory, or a ZIP package\n"
      unless @inputs;

    my @entries;
    for my $input (@inputs) {
        die "$profile input path is missing\n"
          unless defined $input && !ref($input) && length $input;
        if ( -d $input ) {
            push @entries, @{ _directory_entries($input) };
            next;
        }
        if ( -f $input && $input =~ /\.zip\z/i ) {
            push @entries, @{ _zip_entries($input) };
            next;
        }
        if ( -f $input && _is_table_filename($input) ) {
            push @entries, _file_entry($input);
            next;
        }
        die "$profile input <$input> must be a CSV/TSV table, directory, or ZIP package\n";
    }

    die "$profile input does not contain any CSV or TSV table files\n"
      unless @entries;
    return _parse_entries( \@entries, $profile );
}

sub normalize_table_name {
    my ( $name, $profile ) = @_;
    $name = basename( defined $name ? $name : q{} );
    $name =~ s/\.gz\z//i;
    $name =~ s/\.(?:csv|tsv|txt)\z//i;
    $name = uc $name;
    $name =~ s/[^A-Z0-9]+/_/g;
    $name =~ s/^_+|_+$//g;

    my $profile_prefix = uc($profile // q{});
    $profile_prefix =~ s/[^A-Z0-9]+/_/g;
    $name =~ s/^(?:${profile_prefix}|SCDM|CDM)_// if length $profile_prefix;

    my %alias = (
        i2b2 => {
            PATIENT => 'PATIENT_DIMENSION',
            VISIT   => 'VISIT_DIMENSION',
            CONCEPT => 'CONCEPT_DIMENSION',
        },
        sentinel => {
            PROCEDURES    => 'PROCEDURE',
            LAB_RESULT_CM => 'LAB_RESULT',
            VITAL         => 'VITAL_SIGNS',
        },
        pcornet => {
            PROCEDURE  => 'PROCEDURES',
            LAB_RESULT => 'LAB_RESULT_CM',
            VITAL_SIGNS => 'VITAL',
        },
    );
    my $key = lc($profile // q{});
    return $alias{$key}{$name}
      if exists $alias{$key} && exists $alias{$key}{$name};
    return $name;
}

sub _memory_package {
    my ( $data, $profile ) = @_;
    my $tables = ref($data) eq 'HASH' && ref( $data->{tables} ) eq 'HASH'
      ? $data->{tables}
      : $data;
    die "$profile in-memory input must be an object keyed by table name\n"
      unless ref($tables) eq 'HASH';

    my ( %normalized, %sources );
    for my $input_name ( sort keys %{$tables} ) {
        my $table = normalize_table_name( $input_name, $profile );
        die "$profile input contains table <$table> more than once\n"
          if exists $normalized{$table};
        my $rows = $tables->{$input_name};
        die "$profile table <$table> must contain an array of row objects\n"
          unless ref($rows) eq 'ARRAY';
        $normalized{$table} = [
            map {
                die "$profile table <$table> must contain only row objects\n"
                  unless ref($_) eq 'HASH';
                _normalize_row( dclone($_), $table )
            } @{$rows}
        ];
        $sources{$table} = ["memory:$input_name"];
    }

    return {
        tables  => \%normalized,
        sources => \%sources,
        kind    => 'memory',
    };
}

sub _directory_entries {
    my ($directory) = @_;
    my @files;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                push @files, $File::Find::name
                  if -f $File::Find::name
                  && _is_table_filename($File::Find::name);
            },
        },
        $directory,
    );
    return [ map { _file_entry($_) } sort @files ];
}

sub _file_entry {
    my ($file) = @_;
    return {
        name => basename($file),
        source => $file,
        read => sub {
            return _read_gzip($file) if $file =~ /\.gz\z/i;
            return path($file)->slurp_raw;
        },
    };
}

sub _zip_entries {
    my ($zip_file) = @_;
    my @entries;
    my $zip = IO::Uncompress::Unzip->new($zip_file)
      or die "Cannot open ZIP package <$zip_file>: $UnzipError\n";

    while (1) {
        my $header = $zip->getHeaderInfo;
        my $name   = $header->{Name};
        if ( defined $name && $name !~ m{/\z} && _is_table_filename($name) ) {
            my $bytes = q{};
            my $buffer;
            while (1) {
                my $read = $zip->read($buffer);
                die "Cannot read ZIP entry <$name>: $UnzipError\n"
                  if !defined $read || $read < 0;
                last if $read == 0;
                $bytes .= $buffer;
            }
            if ( $name =~ /\.gz\z/i ) {
                my $uncompressed = q{};
                gunzip \$bytes => \$uncompressed
                  or die "Cannot decompress ZIP entry <$name>: $GunzipError\n";
                $bytes = $uncompressed;
            }
            push @entries, {
                name   => basename($name),
                source => "$zip_file:$name",
                read   => sub { return $bytes },
            };
        }
        last unless $zip->nextStream;
    }
    close $zip;
    return \@entries;
}

sub _parse_entries {
    my ( $entries, $profile ) = @_;
    my ( %tables, %headers, %sources );

    for my $entry ( @{$entries} ) {
        my $table = normalize_table_name( $entry->{name}, $profile );
        next unless length $table;
        my $bytes = $entry->{read}->();
        my $text = eval { decode( 'UTF-8', $bytes, FB_CROAK ) };
        if ( my $error = $@ ) {
            chomp $error;
            die "$profile table <$entry->{source}> is not valid UTF-8: $error\n";
        }
        my ( $rows, $table_headers ) = _parse_table_text(
            $text, $entry->{name}, $entry->{source}, $table,
        );

        if ( exists $headers{$table} ) {
            die "$profile table <$table> has inconsistent headers across input files\n"
              unless join( "\x1f", @{ $headers{$table} } ) eq
                join( "\x1f", @{$table_headers} );
        }
        else {
            $headers{$table} = $table_headers;
        }
        push @{ $tables{$table} }, @{$rows};
        push @{ $sources{$table} }, $entry->{source};
    }

    return {
        tables  => \%tables,
        sources => \%sources,
        kind    => 'files',
    };
}

sub _parse_table_text {
    my ( $text, $name, $source, $table ) = @_;
    my $separator = _separator_for( $name, $text );
    my $csv = Text::CSV_XS->new(
        {
            binary           => 1,
            auto_diag        => 2,
            sep_char         => $separator,
            empty_is_undef   => 0,
            blank_is_undef   => 0,
            allow_whitespace => 0,
        }
    );
    open my $fh, '<', \$text
      or die "Cannot read in-memory table <$source>: $!\n";
    my $raw_headers = $csv->getline($fh);
    die "Table <$source> has no header row\n" unless $raw_headers;

    my @headers = map { _normalize_column($_) } @{$raw_headers};
    my %seen;
    for my $header (@headers) {
        die "Table <$source> contains an empty column name\n" unless length $header;
        die "Table <$source> contains duplicate normalized column <$header>\n"
          if $seen{$header}++;
    }
    $csv->column_names(@headers);

    my @rows;
    while ( my $row = $csv->getline_hr($fh) ) {
        push @rows, _normalize_row( $row, $table );
    }
    close $fh;
    return ( \@rows, \@headers );
}

sub _normalize_row {
    my ( $row, $table ) = @_;
    my %normalized;
    for my $raw_key ( keys %{$row} ) {
        my $key = _normalize_column($raw_key);
        die "Table <$table> contains duplicate normalized column <$key>\n"
          if exists $normalized{$key};
        my $value = $row->{$raw_key};
        die "Table <$table> column <$key> must contain scalar values\n"
          if ref($value);
        if ( defined $value ) {
            $value =~ s/^\x{FEFF}//;
            $value =~ s/^\s+|\s+$//g;
        }
        $normalized{$key} = $value;
    }
    return \%normalized;
}

sub _normalize_column {
    my ($column) = @_;
    $column = defined $column ? $column : q{};
    $column =~ s/^\x{FEFF}//;
    $column =~ s/^\s+|\s+$//g;
    $column = uc $column;
    $column =~ s/[^A-Z0-9]+/_/g;
    $column =~ s/^_+|_+$//g;
    return $column;
}

sub _separator_for {
    my ( $name, $text ) = @_;
    return "\t" if $name =~ /\.tsv(?:\.gz)?\z/i;

    my ($line) = $text =~ /\A(?:\x{FEFF})?([^\r\n]*)/;
    my @candidate = ( ',', "\t", ';', '|' );
    my $best = ',';
    my $count = -1;
    for my $separator (@candidate) {
        my $found = () = ( $line // q{} ) =~ /\Q$separator\E/g;
        if ( $found > $count ) {
            $best  = $separator;
            $count = $found;
        }
    }
    return $best;
}

sub _read_gzip {
    my ($file) = @_;
    my $gz = IO::Uncompress::Gunzip->new($file)
      or die "Cannot open gzip table <$file>: $GunzipError\n";
    my $bytes = q{};
    my $buffer;
    while (1) {
        my $read = $gz->read($buffer);
        die "Cannot read gzip table <$file>: $GunzipError\n"
          if !defined $read || $read < 0;
        last if $read == 0;
        $bytes .= $buffer;
    }
    close $gz;
    return $bytes;
}

sub _is_table_filename {
    my ($file) = @_;
    return defined $file && $file =~ /\.(?:csv|tsv|txt)(?:\.gz)?\z/i;
}

1;
