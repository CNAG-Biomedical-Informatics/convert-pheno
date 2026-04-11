package Convert::Pheno::CLI::Args;

use strict;
use warnings;

use Exporter 'import';
use Getopt::Long qw(GetOptionsFromArray :config no_ignore_case);
use File::Spec::Functions qw(catfile file_name_is_absolute);

our @EXPORT_OK = qw(build_cli_request);

sub _normalize_cli_type {
    my ($type) = @_;
    return undef unless defined $type;
    my $norm = lc $type;
    $norm =~ s/^\s+|\s+$//g;
    $norm =~ s/[-_\s]+//g;
    my %map = (
        bff          => 'bff',
        beacon       => 'bff',
        pxf          => 'pxf',
        phenopackets => 'pxf',
        omop         => 'omop',
        omopcdm      => 'omop',
        redcap       => 'redcap',
        cdisc        => 'cdisc',
        cdiscodm     => 'cdisc',
        csv          => 'csv',
        jsonf        => 'jsonf',
        jsonld       => 'jsonld',
    );
    return $map{$norm};
}

sub _count_defined {
    return scalar grep { defined $_ } @_;
}

sub _resolve_output_path {
    my ( $dir, $path ) = @_;
    return undef unless defined $path;
    return $path if file_name_is_absolute($path);
    return catfile( $dir, $path );
}

sub build_cli_request {
    my (%arg) = @_;
    my $argv           = $arg{argv} || [];
    my $usage_error    = $arg{usage_error} || sub { die @_ };
    my $schema_default = $arg{schema_file};
    my $out_dir        = exists $arg{out_dir}   ? $arg{out_dir}   : '.';
    my $color          = exists $arg{color}     ? $arg{color}     : 1;
    my $stream         = exists $arg{stream}    ? $arg{stream}    : 0;
    my $ohdsi_db       = exists $arg{ohdsi_db}  ? $arg{ohdsi_db}  : 0;

    my ( $in_type_arg, $out_type_arg );
    my ( $in_pxf, $in_bff, $in_redcap, $in_cdisc, $in_csv );
    my @omop_files;
    my ( $out_bff, $out_pxf, $out_csv, $out_jsonf, $out_jsonld, $out_omop );
    my @entities_args;
    my @out_entity_specs;
    my ( $help, $man, $mapping_file, $max_lines_sql, $search );
    my ( $text_similarity_method, $min_text_similarity_score, $levenshtein_weight );
    my ( $debug, $verbose, $sep, $exposures_file, $sql2csv, $test, $search_audit_tsv );
    my ( @omop_tables, $redcap_dictionary, $path_to_ohdsi_db, $print_hidden_labels );
    my ( $self_validate_schema, $overwrite, $username, $log, $version );
    my $schema_file = $schema_default;

    GetOptionsFromArray(
        $argv,
        'i=s'                         => \$in_type_arg,
        'o=s'                         => \$out_type_arg,
        'ipxf=s'                      => \$in_pxf,
        'ibff=s'                      => \$in_bff,
        'iredcap=s'                   => \$in_redcap,
        'icdisc=s'                    => \$in_cdisc,
        'iomop=s{1,}'                 => \@omop_files,
        'icsv=s'                      => \$in_csv,
        'obff=s'                      => \$out_bff,
        'opxf=s'                      => \$out_pxf,
        'ocsv=s'                      => \$out_csv,
        'ojsonf=s'                    => \$out_jsonf,
        'ojsonld=s'                   => \$out_jsonld,
        'oomop=s'                     => \$out_omop,
        'out-dir=s'                   => \$out_dir,
        'entities=s{1,}'              => \@entities_args,
        'out-entity=s'                => \@out_entity_specs,
        'help|?'                      => \$help,
        'man'                         => \$man,
        'mapping-file=s'              => \$mapping_file,
        'max-lines-sql=i'             => \$max_lines_sql,
        'search=s'                    => \$search,
        'text-similarity-method=s'    => \$text_similarity_method,
        'min-text-similarity-score=f' => \$min_text_similarity_score,
        'levenshtein-weight=f'        => \$levenshtein_weight,
        'debug=i'                     => \$debug,
        'verbose|v'                   => \$verbose,
        'color!'                      => \$color,
        'separator|sep=s'             => \$sep,
        'schema-file=s'               => \$schema_file,
        'exposures-file=s'            => \$exposures_file,
        'stream!'                     => \$stream,
        'sql2csv'                     => \$sql2csv,
        'test'                        => \$test,
        'search-audit-tsv=s'          => \$search_audit_tsv,
        'ohdsi-db'                    => \$ohdsi_db,
        'omop-tables=s{1,}'           => \@omop_tables,
        'redcap-dictionary|rcd=s'     => \$redcap_dictionary,
        'path-to-ohdsi-db=s'          => \$path_to_ohdsi_db,
        'print-hidden-labels|phl'     => \$print_hidden_labels,
        'self-validate-schema|svs'    => \$self_validate_schema,
        'O'                           => \$overwrite,
        'username=s'                  => \$username,
        'log:s'                       => \$log,
        'version|V'                   => \$version,
    ) or $usage_error->('Invalid command-line arguments');

    return {
        action  => 'help',
        color   => $color,
    } if $help;

    return {
        action  => 'man',
        color   => $color,
    } if $man;

    return {
        action  => 'version',
        color   => $color,
    } if $version;

    my $normalized_in_type  = _normalize_cli_type($in_type_arg);
    my $normalized_out_type = _normalize_cli_type($out_type_arg);

    $usage_error->("Unsupported input type <$in_type_arg> for -i")
      if defined $in_type_arg && !defined $normalized_in_type;
    $usage_error->("Unsupported output type <$out_type_arg> for -o")
      if defined $out_type_arg && !defined $normalized_out_type;

    $usage_error->("Please use either the generic <-i/-o> syntax or the compact <-ixxx/-oxxx> flags for each side, not both")
      if ( defined $normalized_in_type
        && _count_defined( $in_pxf, $in_bff, $in_redcap, $in_cdisc, $in_csv, @omop_files ? 1 : undef ) )
      || ( defined $normalized_out_type
        && _count_defined( $out_bff, $out_pxf, $out_csv, $out_jsonf, $out_jsonld, $out_omop ) );

    if ( defined $normalized_in_type ) {
        if ( $normalized_in_type eq 'omop' ) {
            $usage_error->("Please provide OMOP input file(s) after <-i omop>") unless @{$argv};
            if ( defined $normalized_out_type ) {
                $usage_error->("Please provide OMOP input file(s) followed by one output path")
                  unless @{$argv} >= 2;
                @omop_files = @{$argv}[ 0 .. $#{$argv} - 1 ];
                my $generic_outfile = $argv->[-1];
                if    ( $normalized_out_type eq 'bff' )    { $out_bff    = $generic_outfile }
                elsif ( $normalized_out_type eq 'pxf' )    { $out_pxf    = $generic_outfile }
                elsif ( $normalized_out_type eq 'csv' )    { $out_csv    = $generic_outfile }
                elsif ( $normalized_out_type eq 'jsonf' )  { $out_jsonf  = $generic_outfile }
                elsif ( $normalized_out_type eq 'jsonld' ) { $out_jsonld = $generic_outfile }
                elsif ( $normalized_out_type eq 'omop' )   { $out_omop   = $generic_outfile }
            }
            else {
                @omop_files = @{$argv};
            }
            @{$argv} = ();
        }
        else {
            $usage_error->("Please provide an input file after <-i $in_type_arg>")
              unless @{$argv};
            my $generic_infile = shift @{$argv};
            if    ( $normalized_in_type eq 'pxf' )    { $in_pxf    = $generic_infile }
            elsif ( $normalized_in_type eq 'bff' )    { $in_bff    = $generic_infile }
            elsif ( $normalized_in_type eq 'redcap' ) { $in_redcap = $generic_infile }
            elsif ( $normalized_in_type eq 'cdisc' )  { $in_cdisc  = $generic_infile }
            elsif ( $normalized_in_type eq 'csv' )    { $in_csv    = $generic_infile }

            if ( defined $normalized_out_type ) {
                $usage_error->("Please provide an output file after <-o $out_type_arg>")
                  unless @{$argv};
                my $generic_outfile = shift @{$argv};
                if    ( $normalized_out_type eq 'bff' )    { $out_bff    = $generic_outfile }
                elsif ( $normalized_out_type eq 'pxf' )    { $out_pxf    = $generic_outfile }
                elsif ( $normalized_out_type eq 'csv' )    { $out_csv    = $generic_outfile }
                elsif ( $normalized_out_type eq 'jsonf' )  { $out_jsonf  = $generic_outfile }
                elsif ( $normalized_out_type eq 'jsonld' ) { $out_jsonld = $generic_outfile }
                elsif ( $normalized_out_type eq 'omop' )   { $out_omop   = $generic_outfile }
            }
        }
    }

    $usage_error->("The flag <-o> requires <-i> when using the generic syntax")
      if defined $normalized_out_type && !defined $normalized_in_type;

    $usage_error->("Unexpected extra positional arguments: @{$argv}") if @{$argv};

    my @validation_checks = (
        {
            condition => sub {
                !(     ( defined $in_pxf && -f $in_pxf )
                    || ( defined $in_bff    && -f $in_bff )
                    || ( defined $in_redcap && -f $in_redcap )
                    || ( defined $in_cdisc  && -f $in_cdisc )
                    || ( defined $in_csv    && -f $in_csv )
                    || ( @omop_files        && -f $omop_files[0] ) );
            },
            message => "Please specify a valid input [-i input-type] <infile>\n",
        },
        { condition => sub { !-d $out_dir }, message => "Please specify a valid directory for --out-dir\n", },
        {
            condition => sub { ( $in_redcap || $in_cdisc ) && !$redcap_dictionary },
            message   => "Please specify a valid REDCap data dictionary --rcd <file>\n",
        },
        {
            condition => sub { ( $in_redcap || $in_cdisc || $in_csv ) && !$mapping_file },
            message   => "Please specify a valid mapping file --mapping-file <file>\n",
        },
        {
            condition => sub { @omop_files && $omop_files[0] !~ m/\.(csv|sql|tsv)/i },
            message   => "Please specify a valid OMOP-CDM file(s) (e.g., *csv or .sql)\n",
        },
        {
            condition => sub { @omop_tables && !@omop_files },
            message   => "The flag <--omop-tables> is only valid with <-iomop>\n",
        },
        {
            condition => sub { $stream && $out_pxf },
            message   => "The flag <--stream> is only valid with <-obff>\n",
        },
        {
            condition => sub { $stream && $sql2csv },
            message   =>
"The flags <--stream> and <--sql2csv> are mutually exclusive.\nIf you are using <--stream> is because you are likely processing huge files and we don't want to duplicate them in your HDD\n",
        },
        {
            condition => sub {
                @omop_files
                  && ( ( defined $out_bff && $out_bff !~ m/\.json/i )
                    || ( defined $out_pxf && $out_pxf !~ m/\.json/i ) );
            },
            message => "The flag <--iomops> only supports output files in <json|json.gz> format\n",
        },
        {
            condition => sub { !-f $schema_file },
            message   => "Please specify a valid schema for the mapping file --schema-file <file>\n",
        },
        {
            condition => sub { defined $path_to_ohdsi_db && !-d $path_to_ohdsi_db },
            message   => "Please specify a valid directory for the mapping file --path-to-ohdsi-db <dir>\n",
        },
        {
            condition => sub { defined $exposures_file && !-f $exposures_file },
            message   => "Please specify a valid --exposures-file <file>\n",
        },
        {
            condition => sub { ( $out_csv || $out_jsonf || $out_jsonld ) && ( !$in_bff && !$in_pxf ); },
            message   => "Sorry, <--ocsv>, <--ojsonf> and <--ojsonf> are only compatible with <--ibff> or <--ipxf>\n",
        },
        {
            condition => sub { defined $out_omop && !$ohdsi_db },
            message   => "Error: Please use --ohdsi-db when using OMOP CDM as an output",
        },
        {
            condition => sub { defined($out_omop) && $out_omop =~ /^-/ },
            message   => "Error: The value for --oomop appears to be an option. Please supply a proper non-option string using --oomop=VALUE",
        },
    );

    for my $check (@validation_checks) {
        $usage_error->( $check->{message} ) if $check->{condition}->();
    }

    $usage_error->("Please provide <--entities> as a space-separated list, e.g. <--entities individuals biosamples>")
      if grep { defined $_ && /,/ } @entities_args;

    my @entity_list =
      @entities_args
      ? map { uc($_) eq 'ALL' ? () : $_ } grep { length } map { s/^\s+|\s+$//gr } @entities_args
      : ('individuals');

    @entity_list = ('individuals') unless @entity_list;

    my %supported_entities = map { $_ => 1 } qw(individuals biosamples);
    for my $entity (@entity_list) {
        $usage_error->("Unsupported entity <$entity> in --entities")
          unless $supported_entities{$entity};
    }

    $usage_error->("The flag <--entities> is only valid with BFF output")
      if @entities_args && ( $out_pxf || $out_csv || $out_jsonf || $out_jsonld || $out_omop );

    $usage_error->("The entity <biosamples> is currently only supported with <-ipxf> and <-obff>")
      if grep { $_ eq 'biosamples' } @entity_list && !$in_pxf;

    $usage_error->("When using <--entities>, please use <--out-dir> without <-obff FILE>")
      if @entities_args && defined $out_bff;

    $usage_error->("The flag <--out-entity> requires <--entities>")
      if @out_entity_specs && !@entities_args;

    my %entity_output_files;
    for my $spec (@out_entity_specs) {
        $usage_error->("Invalid <--out-entity> value <$spec>; use entity=filename")
          unless defined $spec && $spec =~ /\A([^=]+)=(.+)\z/;
        my ( $entity, $filename ) = ( $1, $2 );
        $entity =~ s/^\s+|\s+$//g;
        $filename =~ s/^\s+|\s+$//g;

        $usage_error->("Unsupported entity <$entity> in --out-entity")
          unless $supported_entities{$entity};
        $usage_error->("The entity <$entity> must also be requested in <--entities>")
          unless grep { $_ eq $entity } @entity_list;
        $usage_error->("Please provide a filename for <--out-entity $entity=...>")
          unless length $filename;

        $entity_output_files{$entity} = _resolve_output_path( $out_dir, $filename );
    }

    die
"Error: The value for --oomop ('$out_omop') appears to be an option. Please supply a proper non-option string using --oomop=VALUE\n"
      if defined($out_omop) && $out_omop =~ /^-/;

    my $out_file =
        $out_pxf    ? _resolve_output_path( $out_dir, $out_pxf )
      : $out_bff    ? _resolve_output_path( $out_dir, $out_bff )
      : $out_csv    ? _resolve_output_path( $out_dir, $out_csv )
      : $out_jsonf  ? _resolve_output_path( $out_dir, $out_jsonf )
      : $out_jsonld ? _resolve_output_path( $out_dir, $out_jsonld )
      : $out_omop   ? _resolve_output_path( $out_dir, $out_omop )
      : @entity_list == 1
      ? catfile( $out_dir, $entity_list[0] . '.json' )
      : catfile( $out_dir, 'individuals.json' );

    my $log_file =
      catfile( $out_dir, ( $log ? $log : 'convert-pheno-log.json' ) );
    my $search_audit_file =
      defined $search_audit_tsv
      ? _resolve_output_path( $out_dir, $search_audit_tsv )
      : undef;

    my $in_type =
        $in_pxf     ? 'pxf'
      : $in_bff     ? 'bff'
      : $in_redcap  ? 'redcap'
      : $in_cdisc   ? 'cdisc'
      : $in_csv     ? 'csv'
      : @omop_files ? 'omop'
      :               'bff';
    my $out_type =
        $out_pxf    ? 'pxf'
      : $out_bff    ? 'bff'
      : $out_csv    ? 'csv'
      : $out_jsonf  ? 'jsonf'
      : $out_jsonld ? 'jsonld'
      : $out_omop   ? 'omop'
      :               'bff';
    my $method = $in_type . '2' . $out_type;

    my $id = time . substr( "00000$$", -5 );

    my %data = (
        out_dir                   => $out_dir,
        in_textfile               => 1,
        method                    => $method,
        sql2csv                   => $sql2csv ? 1 : 0,
        exposures_file            => $exposures_file,
        search                    => $search,
        ohdsi_db                  => $ohdsi_db ? 1 : 0,
        omop_tables               => \@omop_tables,
        username                  => $username,
        text_similarity_method    => $text_similarity_method,
        min_text_similarity_score => $min_text_similarity_score,
        levenshtein_weight        => $levenshtein_weight,
        max_lines_sql             => $max_lines_sql,
        stream                    => $stream ? 1 : 0,
        schema_file               => $schema_file,
        out_file                  => $out_file,
        id                        => $id,
        test                      => $test ? 1 : 0,
        entities                  => \@entity_list,
    );

    $data{entity_output_files} = \%entity_output_files if %entity_output_files;

    my $resolved_in_file =
        $in_pxf     ? $in_pxf
      : $in_bff     ? $in_bff
      : $in_redcap  ? $in_redcap
      : $in_cdisc   ? $in_cdisc
      : $in_csv     ? $in_csv
      :               undef;

    $data{in_file}              = $resolved_in_file if defined $resolved_in_file;
    $data{in_files}             = \@omop_files      if @omop_files;
    $data{sep}                  = $sep if defined $sep;
    $data{redcap_dictionary}    = $redcap_dictionary if defined $redcap_dictionary;
    $data{mapping_file}         = $mapping_file if defined $mapping_file;
    $data{self_validate_schema} = $self_validate_schema if defined $self_validate_schema;
    $data{path_to_ohdsi_db}     = $path_to_ohdsi_db if defined $path_to_ohdsi_db;
    $data{print_hidden_labels}  = $print_hidden_labels ? 1 : 0 if defined $print_hidden_labels;
    $data{search_audit_file}    = $search_audit_file if defined $search_audit_file;
    $data{debug}                = $debug if defined $debug;
    $data{log}                  = $log if defined $log;
    $data{verbose}              = $verbose ? 1 : 0 if defined $verbose;

    return {
        action    => 'run',
        color     => $color,
        overwrite => $overwrite,
        out_file  => $out_file,
        log_file  => $log_file,
        verbose   => $verbose,
        stream    => $stream,
        data      => \%data,
    };
}

1;
