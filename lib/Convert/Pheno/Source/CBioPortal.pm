package Convert::Pheno::Source::CBioPortal;

use strict;
use warnings;

use Encode qw(decode FB_CROAK);
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use IO::Uncompress::Unzip qw($UnzipError);
use Path::Tiny qw(path);
use Storable qw(dclone);
use Text::CSV_XS;

use Convert::Pheno::BFF::DerivedEntities qw(mapping_entity_overrides);
use Convert::Pheno::IO::CSVHandler qw(read_mapping_file);
use Convert::Pheno::Mapping::Compiler qw(compile_mapping);
use Convert::Pheno::Mapping::Shared qw(get_info get_metaData);
use Convert::Pheno::Source::Result;

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};

    my $package = exists $converter->{data}
      ? _memory_package( $converter->{data} )
      : _path_package( $converter->{in_file} );
    my $normalized = _normalize_package($package);

    my %artifacts = ( study => $normalized->{study} );
    if ( defined $converter->{mapping_file}
        && length $converter->{mapping_file} )
    {
        my $mapping = read_mapping_file(
            {
                mapping_file         => $converter->{mapping_file},
                self_validate_schema => $converter->{self_validate_schema},
                schema_file          => $converter->{schema_file},
            }
        );
        my $compiled = compile_mapping(
            $mapping,
            source_profile => 'cbioportal',
            headers        => $normalized->{headers},
        );
        $artifacts{mapping}        = $mapping;
        $artifacts{entity_mapping} = $compiled;
    }

    return Convert::Pheno::Source::Result->new(
        {
            data      => $normalized->{records},
            owned     => 1,
            artifacts => \%artifacts,
        }
    );
}

sub prepare {
    my ($self) = @_;
    my $converter = $self->{converter};
    return 1 if $converter->{cbioportal_input_prepared}
      && exists $converter->{data};

    $converter->{_cbioportal_source_data} = $converter->{data}
      if exists $converter->{data}
      && !exists $converter->{_cbioportal_source_data};
    $converter->{data} = $converter->{_cbioportal_source_data}
      if !exists $converter->{data}
      && exists $converter->{_cbioportal_source_data};

    my $source = $self->load;
    $source->apply_to($converter);
    $converter->{cbioportal_study} = $source->artifact('study');

    my $compiled = $source->artifact('entity_mapping');
    if ( defined $compiled ) {
        $converter->{data_mapping_file} = $compiled;
    }
    else {
        delete $converter->{data_mapping_file};
    }

    $converter->{mapping_file_derived_entity_overrides} =
      mapping_entity_overrides( $source->artifact('mapping') );
    $converter->{metaData}     = get_metaData($converter);
    $converter->{convertPheno} = get_info($converter);
    $converter->{cbioportal_input_prepared} = 1;
    return 1;
}

sub _path_package {
    my ($input) = @_;
    die "cBioPortal input requires a study directory or ZIP file\n"
      unless defined $input && length $input;

    return _directory_package($input) if -d $input;
    return _zip_package($input) if -f $input && $input =~ /\.zip\z/i;

    die "cBioPortal input <$input> must be a study directory or .zip file\n";
}

sub _directory_package {
    my ($directory) = @_;
    my $root = File::Spec->rel2abs($directory);
    my %entries;

    find(
        {
            no_chdir => 1,
            wanted   => sub {
                return unless -f $File::Find::name;
                my $name = File::Spec->abs2rel( $File::Find::name, $root );
                $name =~ tr{\\}{/};
                $name = _normalize_entry_name($name);
                $entries{$name} = { size => -s $File::Find::name };
            },
        },
        $root,
    );

    my %cache;
    return {
        label   => $directory,
        entries => \%entries,
        read_many => sub {
            my ($names) = @_;
            for my $name ( @{$names} ) {
                next if exists $cache{$name};
                die "cBioPortal package <$directory> does not contain <$name>\n"
                  unless exists $entries{$name};
                my $file = File::Spec->catfile( $root, split m{/}, $name );
                $cache{$name} = path($file)->slurp_utf8;
            }
            return { map { $_ => $cache{$_} } @{$names} };
        },
    };
}

sub _zip_package {
    my ($zip_file) = @_;
    my %entries;
    my $zip = IO::Uncompress::Unzip->new($zip_file)
      or die "Cannot open cBioPortal ZIP <$zip_file>: $UnzipError\n";

    while (1) {
        my $header = $zip->getHeaderInfo;
        my $raw_name = $header->{Name};
        if ( defined $raw_name && $raw_name !~ m{/\z} ) {
            my $name = _normalize_entry_name($raw_name);
            die "cBioPortal ZIP <$zip_file> contains duplicate entry <$name>\n"
              if exists $entries{$name};
            $entries{$name} = {
                size => $header->{UncompressedLength} // 0,
            };
        }
        last unless $zip->nextStream;
    }
    close $zip;

    my %cache;
    return {
        label   => $zip_file,
        entries => \%entries,
        read_many => sub {
            my ($names) = @_;
            my %wanted = map { $_ => 1 } grep { !exists $cache{$_} } @{$names};
            return { map { $_ => $cache{$_} } @{$names} } unless %wanted;

            for my $name ( keys %wanted ) {
                die "cBioPortal ZIP <$zip_file> does not contain <$name>\n"
                  unless exists $entries{$name};
            }

            my $reader = IO::Uncompress::Unzip->new($zip_file)
              or die "Cannot reopen cBioPortal ZIP <$zip_file>: $UnzipError\n";
            while (1) {
                my $header = $reader->getHeaderInfo;
                my $raw_name = $header->{Name};
                if ( defined $raw_name && $raw_name !~ m{/\z} ) {
                    my $name = _normalize_entry_name($raw_name);
                    if ( $wanted{$name} ) {
                        my $bytes = q{};
                        my $buffer;
                        while (1) {
                            my $read = $reader->read($buffer);
                            die "Cannot read cBioPortal ZIP entry <$name>: $UnzipError\n"
                              if !defined $read || $read < 0;
                            last if $read == 0;
                            $bytes .= $buffer;
                        }
                        my $text = eval { decode( 'UTF-8', $bytes, FB_CROAK ) };
                        if ( my $error = $@ ) {
                            chomp $error;
                            die "cBioPortal ZIP entry <$name> is not valid UTF-8: $error\n";
                        }
                        $cache{$name} = $text;
                        delete $wanted{$name};
                    }
                }
                last unless %wanted && $reader->nextStream;
            }
            close $reader;

            die "Could not read cBioPortal ZIP entries <"
              . join( '>, <', sort keys %wanted ) . ">\n"
              if %wanted;
            return { map { $_ => $cache{$_} } @{$names} };
        },
    };
}

sub _memory_package {
    my ($data) = @_;
    die "In-memory cBioPortal input must contain a <files> object\n"
      unless ref($data) eq 'HASH' && ref( $data->{files} ) eq 'HASH';

    my ( %files, %entries );
    for my $raw_name ( keys %{ $data->{files} } ) {
        my $name = _normalize_entry_name($raw_name);
        my $content = $data->{files}{$raw_name};
        die "In-memory cBioPortal file <$name> must contain text\n"
          if ref($content);
        die "In-memory cBioPortal input contains duplicate file <$name>\n"
          if exists $files{$name};
        $files{$name}   = defined $content ? "$content" : q{};
        $entries{$name} = { size => length $files{$name} };
    }

    return {
        label   => 'in-memory cBioPortal study',
        entries => \%entries,
        read_many => sub {
            my ($names) = @_;
            for my $name ( @{$names} ) {
                die "In-memory cBioPortal package does not contain <$name>\n"
                  unless exists $files{$name};
            }
            return { map { $_ => $files{$_} } @{$names} };
        },
    };
}

sub _normalize_package {
    my ($package) = @_;
    my $entries = $package->{entries};

    my @study_meta = sort grep { m{(?:\A|/)meta_study\.txt\z}i }
      keys %{$entries};
    die "cBioPortal package <$package->{label}> must contain one <meta_study.txt>\n"
      unless @study_meta == 1;

    my $study_meta_name = $study_meta[0];
    my $root = dirname($study_meta_name);
    $root = q{} if $root eq '.';
    my $prefix = length $root ? "$root/" : q{};

    my @meta_candidates = sort grep {
        my $relative = substr( $_, length $prefix );
        index( $_, $prefix ) == 0
          && index( $relative, '/' ) < 0
          && $relative =~ /\Ameta_[^\/]+\.txt\z/i
    } keys %{$entries};
    my $candidate_text = $package->{read_many}->(\@meta_candidates);

    my $study = _parse_meta_file(
        $candidate_text->{$study_meta_name},
        $study_meta_name,
        1,
    );
    _require_meta_fields(
        $study,
        $study_meta_name,
        qw(cancer_study_identifier name),
    );

    my ( @patient_meta, @sample_meta );
    for my $name (@meta_candidates) {
        next if $name eq $study_meta_name;
        my $meta = _parse_meta_file( $candidate_text->{$name}, $name, 0 );
        next unless $meta;
        next unless uc( $meta->{genetic_alteration_type} // q{} ) eq 'CLINICAL';

        my $datatype = uc( $meta->{datatype} // q{} );
        push @patient_meta, [ $name, $meta ] if $datatype eq 'PATIENT_ATTRIBUTES';
        push @sample_meta,  [ $name, $meta ] if $datatype eq 'SAMPLE_ATTRIBUTES';
    }

    die "cBioPortal package <$package->{label}> contains multiple PATIENT_ATTRIBUTES meta files\n"
      if @patient_meta > 1;
    die "cBioPortal package <$package->{label}> must contain one SAMPLE_ATTRIBUTES meta file\n"
      unless @sample_meta == 1;

    my $study_id = _trim( $study->{cancer_study_identifier} );
    for my $entry ( @patient_meta, @sample_meta ) {
        my ( $name, $meta ) = @{$entry};
        _require_meta_fields( $meta, $name, qw(cancer_study_identifier data_filename) );
        my $meta_study_id = _trim( $meta->{cancer_study_identifier} );
        die "cBioPortal meta file <$name> references study <$meta_study_id>, expected <$study_id>\n"
          unless $meta_study_id eq $study_id;
    }

    my $sample_data_name = _resolve_package_name(
        $prefix,
        $sample_meta[0][1]{data_filename},
        $entries,
        $sample_meta[0][0],
    );
    my $patient_data_name = @patient_meta
      ? _resolve_package_name(
        $prefix,
        $patient_meta[0][1]{data_filename},
        $entries,
        $patient_meta[0][0],
      )
      : undef;

    my $case_prefix = $prefix . 'case_lists/';
    my @case_names = sort grep {
        index( $_, $case_prefix ) == 0
          && length substr( $_, length $case_prefix )
          && index( substr( $_, length $case_prefix ), '/' ) < 0
    } keys %{$entries};

    my @selected = ( $sample_data_name, @case_names );
    push @selected, $patient_data_name if defined $patient_data_name;
    my $selected_text = $package->{read_many}->(\@selected);

    my $sample_table = _parse_clinical_table(
        $selected_text->{$sample_data_name},
        $sample_data_name,
        [qw(PATIENT_ID SAMPLE_ID)],
    );
    my $patient_table = defined $patient_data_name
      ? _parse_clinical_table(
        $selected_text->{$patient_data_name},
        $patient_data_name,
        ['PATIENT_ID'],
      )
      : undef;

    my ( %patients, @patient_order );
    if ($patient_table) {
        for my $row ( @{ $patient_table->{rows} } ) {
            my $id = _required_id( $row->{PATIENT_ID}, 'PATIENT_ID', $patient_data_name );
            die "cBioPortal patient table <$patient_data_name> contains duplicate PATIENT_ID <$id>\n"
              if exists $patients{$id};
            $row->{PATIENT_ID} = $id;
            $patients{$id} = $row;
            push @patient_order, $id;
        }
    }

    my ( %samples, %samples_by_patient );
    for my $row ( @{ $sample_table->{rows} } ) {
        my $patient_id = _required_id(
            $row->{PATIENT_ID}, 'PATIENT_ID', $sample_data_name,
        );
        my $sample_id = _required_id(
            $row->{SAMPLE_ID}, 'SAMPLE_ID', $sample_data_name,
        );
        die "cBioPortal sample table <$sample_data_name> contains duplicate SAMPLE_ID <$sample_id>\n"
          if exists $samples{$sample_id};

        if ( $patient_table && !exists $patients{$patient_id} ) {
            die "cBioPortal sample <$sample_id> references unknown PATIENT_ID <$patient_id>\n";
        }
        if ( !$patient_table && !exists $patients{$patient_id} ) {
            $patients{$patient_id} = { PATIENT_ID => $patient_id };
            push @patient_order, $patient_id;
        }

        $row->{PATIENT_ID} = $patient_id;
        $row->{SAMPLE_ID}  = $sample_id;
        $samples{$sample_id} = $row;
        push @{ $samples_by_patient{$patient_id} }, $row;
    }

    die "cBioPortal study <$study_id> does not contain any patients\n"
      unless @patient_order;

    my ( @case_lists, %case_ids );
    for my $name (@case_names) {
        my $case = _parse_meta_file( $selected_text->{$name}, $name, 1 );
        _require_meta_fields(
            $case,
            $name,
            qw(cancer_study_identifier stable_id case_list_name case_list_ids),
        );
        my $case_study_id = _trim( $case->{cancer_study_identifier} );
        die "cBioPortal case list <$name> references study <$case_study_id>, expected <$study_id>\n"
          unless $case_study_id eq $study_id;

        my $stable_id = _trim( $case->{stable_id} );
        die "cBioPortal package contains duplicate case-list stable_id <$stable_id>\n"
          if $case_ids{$stable_id}++;

        my @sample_ids = grep { length } map { _trim($_) }
          split /\t/, $case->{case_list_ids};
        die "cBioPortal case list <$name> does not contain sample identifiers\n"
          unless @sample_ids;

        my ( %seen_patient, @individual_ids );
        for my $sample_id (@sample_ids) {
            die "cBioPortal case list <$name> references unknown SAMPLE_ID <$sample_id>\n"
              unless exists $samples{$sample_id};
            my $patient_id = $samples{$sample_id}{PATIENT_ID};
            push @individual_ids, $patient_id unless $seen_patient{$patient_id}++;
        }

        push @case_lists,
          {
            metadata      => $case,
            source        => $name,
            sampleIds     => \@sample_ids,
            individualIds => \@individual_ids,
        };
    }

    my %seen_header;
    my @headers = grep { !$seen_header{$_}++ } (
        @{ $patient_table ? $patient_table->{headers} : ['PATIENT_ID'] },
        @{ $sample_table->{headers} },
    );

    my $study_context = {
        id                          => $study_id,
        metadata                    => $study,
        source                      => $package->{label},
        patientAttributeDefinitions => $patient_table
        ? $patient_table->{definitions}
        : { PATIENT_ID => {} },
        sampleAttributeDefinitions => $sample_table->{definitions},
        caseLists                  => \@case_lists,
        patientCount               => scalar @patient_order,
        sampleCount                => scalar keys %samples,
    };

    my @records;
    for my $index ( 0 .. $#patient_order ) {
        my $patient_id = $patient_order[$index];
        push @records,
          {
            id       => $patient_id,
            patient  => $patients{$patient_id},
            samples  => $samples_by_patient{$patient_id} || [],
            study    => $study_context,
            isFirst  => $index == 0 ? 1 : 0,
          };
    }

    return {
        records => \@records,
        headers => \@headers,
        study   => $study_context,
    };
}

sub _parse_clinical_table {
    my ( $text, $label, $required_headers ) = @_;
    $text =~ s/^\x{FEFF}//;
    $text =~ s/\r\n?/\n/g;

    my ( @metadata_rows, @data_lines );
    for my $line ( split /\n/, $text, -1 ) {
        if ( $line =~ /^#(.*)\z/ ) {
            push @metadata_rows, $1 unless @data_lines;
            next;
        }
        next unless length $line;
        push @data_lines, $line;
    }
    die "cBioPortal clinical file <$label> does not contain a header row\n"
      unless @data_lines;

    my $body = join "\n", @data_lines;
    open my $fh, '<', \$body
      or die "Cannot parse cBioPortal clinical file <$label>: $!\n";
    my $csv = Text::CSV_XS->new(
        {
            binary         => 1,
            sep_char       => "\t",
            blank_is_undef => 0,
            empty_is_undef => 0,
        }
    );

    my $headers = $csv->getline($fh);
    die "Cannot parse cBioPortal clinical header in <$label>: "
      . $csv->error_diag . "\n"
      unless $headers;

    my %seen;
    for my $header ( @{$headers} ) {
        $header = _trim($header);
        die "cBioPortal clinical file <$label> contains an empty column name\n"
          unless length $header;
        die "cBioPortal clinical file <$label> contains duplicate column <$header>\n"
          if $seen{$header}++;
    }
    for my $required ( @{$required_headers} ) {
        die "cBioPortal clinical file <$label> is missing required column <$required>\n"
          unless $seen{$required};
    }

    my @rows;
    while ( my $values = $csv->getline($fh) ) {
        die "cBioPortal clinical row in <$label> contains " . scalar( @{$values} )
          . ' values but ' . scalar( @{$headers} ) . " columns are defined\n"
          unless @{$values} == @{$headers};
        my %row;
        @row{ @{$headers} } = @{$values};
        push @rows, \%row;
    }
    die "Cannot parse cBioPortal clinical data in <$label>: "
      . $csv->error_diag . "\n"
      unless $csv->eof;
    close $fh;

    my @metadata_names = qw(displayName description datatype priority);
    my %definitions;
    for my $column_index ( 0 .. $#{$headers} ) {
        my %definition;
        for my $row_index ( 0 .. $#metadata_names ) {
            next unless defined $metadata_rows[$row_index];
            my @values = split /\t/, $metadata_rows[$row_index], -1;
            next unless defined $values[$column_index] && length $values[$column_index];
            $definition{ $metadata_names[$row_index] } = $values[$column_index];
        }
        $definitions{ $headers->[$column_index] } = \%definition;
    }

    return {
        headers     => $headers,
        rows        => \@rows,
        definitions => \%definitions,
    };
}

sub _parse_meta_file {
    my ( $text, $label, $strict ) = @_;
    return unless defined $text;
    $text =~ s/^\x{FEFF}//;
    $text =~ s/\r\n?/\n/g;

    my %meta;
    my $found = 0;
    for my $line ( split /\n/, $text ) {
        next if $line =~ /^\s*(?:#|\z)/;
        if ( $line !~ /^\s*([^:]+?)\s*:\s*(.*)\z/ ) {
            return unless $strict;
            die "Invalid cBioPortal meta line in <$label>: <$line>\n";
        }
        my ( $key, $value ) = ( lc _trim($1), _trim($2) );
        die "cBioPortal meta file <$label> contains duplicate key <$key>\n"
          if exists $meta{$key};
        $meta{$key} = $value;
        $found = 1;
    }

    return $found ? \%meta : undef unless $strict;
    die "cBioPortal meta file <$label> is empty\n" unless $found;
    return \%meta;
}

sub _require_meta_fields {
    my ( $meta, $label, @fields ) = @_;
    for my $field (@fields) {
        die "cBioPortal meta file <$label> is missing <$field>\n"
          unless defined $meta->{$field} && length _trim( $meta->{$field} );
    }
    return 1;
}

sub _resolve_package_name {
    my ( $prefix, $relative, $entries, $meta_name ) = @_;
    $relative = _normalize_entry_name( _trim($relative) );
    my $name = $prefix . $relative;
    die "cBioPortal meta file <$meta_name> references missing data file <$relative>\n"
      unless exists $entries->{$name};
    return $name;
}

sub _normalize_entry_name {
    my ($name) = @_;
    die "cBioPortal package contains an empty file name\n"
      unless defined $name && length $name;
    $name =~ tr{\\}{/};
    $name =~ s{\A\./+}{};
    die "Unsafe cBioPortal package path <$name>\n"
      if $name =~ m{\A/} || grep { $_ eq '..' } split m{/+}, $name;
    $name =~ s{/+}{/}g;
    return $name;
}

sub _required_id {
    my ( $value, $field, $label ) = @_;
    my $id = _trim($value);
    die "cBioPortal clinical file <$label> contains a row without <$field>\n"
      unless defined $id && length $id;
    return $id;
}

sub _trim {
    my ($value) = @_;
    return unless defined $value;
    return $value if ref($value);
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

1;
