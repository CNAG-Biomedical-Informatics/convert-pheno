package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature               qw(say);
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use Path::Tiny;
use File::Basename;
use File::ShareDir::ProjectDistDir;
use List::Util qw(any uniq);
use XML::Fast;
use Moo;
use Types::Standard                qw(Str Int Num Enum ArrayRef Undef);
use File::ShareDir::ProjectDistDir qw(dist_dir);
#use Devel::Size     qw(size total_size);
use Convert::Pheno::IO::CSVHandler;
use Convert::Pheno::IO::FileIO;
use Convert::Pheno::OMOP::Definitions;
use Convert::Pheno::DB::SQLite;
use Convert::Pheno::Utils::Mapping;
use Convert::Pheno::CSV;
use Convert::Pheno::RDF qw(do_bff2jsonld do_pxf2jsonld);
use Convert::Pheno::OMOP;
use Convert::Pheno::PXF;
use Convert::Pheno::Bff2Pxf;
use Convert::Pheno::Bff2Omop;
use Convert::Pheno::CDISC;
use Convert::Pheno::REDCap;

use Exporter 'import';
our @EXPORT =
  qw($VERSION io_yaml_or_json omop2bff_stream_processing share_dir);    # Symbols imported by default

#our @EXPORT_OK = qw(foo bar);       # Symbols imported by request

use constant DEVEL_MODE => 0;

# Personalize warn and die functions
$SIG{__WARN__} = sub { warn "Warn: ", @_ };
$SIG{__DIE__}  = sub { die "Error: ", @_ };

# Global variables:
our $VERSION   = '0.29_1';
our $share_dir = dist_dir('Convert-Pheno');

# SQLite database
my @all_sqlites       = qw(ncit icd10 ohdsi cdisc omim hpo);
my @non_ohdsi_sqlites = qw(ncit icd10 cdisc omim hpo);

# Define a subroutine that computes the default username.
my $default_username = sub {
    return $ENV{'LOGNAME'} || $ENV{'USER'} || $ENV{'USERNAME'} || 'dummy-user';
};

############################################
# Start declaring attributes for the class #
############################################

# Complex defaults here
has search => (
    is     => 'ro',
    coerce => sub { $_[0] // 'exact' },
    isa    => Enum [qw(exact mixed fuzzy)]
);

has text_similarity_method => (
    is     => 'ro',
    coerce => sub { $_[0] // 'cosine' },
    isa    => Enum [qw(cosine dice)]
);

has min_text_similarity_score => (
    is     => 'ro',
    coerce => sub { $_[0] // 0.8 },
    isa    => sub {
        die "Only values between 0 .. 1 supported!"
          unless ( $_[0] >= 0.0 && $_[0] <= 1.0 );
    }
);
has levenshtein_weight => (
    is     => 'ro',
    coerce => sub { $_[0] // 0.1 },
    isa    => sub {
        die "Only values between 0 .. 1 supported!"
          unless ( $_[0] >= 0.0 && $_[0] <= 1.0 );
    }
);

has username => (
    is      => 'ro',
    isa     => Str,
    default => $default_username,    # Use the subroutine for the default.
    coerce  => sub {
        $_[0] // $default_username->();
    },
);

has id => (
    is      => 'ro',
    isa     => Str,
    default => sub { time . substr( "00000$$", -5 ) },
    coerce  => sub { $_[0] // time . substr( "00000$$", -5 ) },
);

has max_lines_sql => (
    default => 500,                    # Limit to speed up runtime
    is      => 'ro',
    coerce  => sub { $_[0] // 500 },
    isa     => Int
);

has 'omop_tables' => (
    default => sub { [@omop_essential_tables] },
    coerce  => sub {
        my $tables = shift;

        $tables =
          @$tables
          ? [ uniq( map { uc($_) } ( 'CONCEPT', 'PERSON', @$tables ) ) ]
          : \@omop_essential_tables;

        return $tables;
    },
    is  => 'rw',
    isa => ArrayRef
);

has exposures_file => (
    default =>
      catfile( $share_dir, 'db', 'concepts_candidates_2_exposure.csv' ),
    coerce => sub {
        $_[0]
          // catfile( $share_dir, 'db', 'concepts_candidates_2_exposure.csv' );
    },
    is  => 'ro',
    isa => Str
);

# Miscellanea atributes here
has [qw /test print_hidden_labels self_validate_schema path_to_ohdsi_db/] =>
  ( default => undef, is => 'ro' );

has [qw /stream ohdsi_db/] => ( default => 0, is => 'ro' );

has [qw /in_files/] => ( default => sub { [] }, is => 'ro' );

has [
    qw /out_file out_dir in_textfile in_file sep sql2csv redcap_dictionary mapping_file schema_file debug log verbose/
] => ( is => 'ro' );

has [qw /data method/] => ( is => 'rw' );

##########################################
# End declaring attributes for the class #
##########################################

sub BUILD {
    my $self = shift;
    $self->{databases} =
      $self->{ohdsi_db} ? \@all_sqlites : \@non_ohdsi_sqlites;
}

#############
#############
#  BFF2PXF  #
#############
#############

sub bff2pxf {
    my $self = shift;
    return $self->array_dispatcher;
}

#############
#############
#  BFF2CSV  #
#############
#############

sub bff2csv {
    my $self = shift;
    return $self->array_dispatcher;
}

#############
#############
# BFF2JSONF #
#############
#############

sub bff2jsonf {
    my $self = shift;
    return $self->array_dispatcher;
}

##############
##############
# BFF2JSONLD #
##############
##############

sub bff2jsonld {
    my $self = shift;
    return $self->array_dispatcher;
}

##############
##############
#  BFF2OMOP  #
##############
##############

sub bff2omop {
    my $self = shift;
    return merge_omop_tables( $self->array_dispatcher );
}

################
################
#  REDCAP2BFF  #
################
################

sub redcap2bff {
    my $self = shift;

    my $data = read_csv( { in => $self->{in_file}, sep => $self->{sep} } );
    my $data_redcap_dict = read_redcap_dict_file(
        {
            redcap_dictionary => $self->{redcap_dictionary},
        }
    );
    my $data_mapping_file = read_mapping_file(
        {
            mapping_file         => $self->{mapping_file},
            self_validate_schema => $self->{self_validate_schema},
            schema_file          => $self->{schema_file}
        }
    );

    $self->{data}              = $data;
    $self->{data_redcap_dict}  = $data_redcap_dict;
    $self->{data_mapping_file} = $data_mapping_file;
    $self->{metaData}          = get_metaData($self);
    $self->{convertPheno}      = get_info($self);

    return $self->array_dispatcher;
}

################
################
#  REDCAP2PXF  #
################
################

sub redcap2pxf {
    my $self = shift;

    $self->{method} = 'redcap2bff';
    my $bff = redcap2bff($self);

    $self->{method}      = 'bff2pxf';
    $self->{data}        = $bff;
    $self->{in_textfile} = 0;

    return $self->array_dispatcher;
}

#################
#################
#  REDCAP2OMOP  #
#################
#################

sub redcap2omop {
    my $self = shift;

    $self->{method} = 'redcap2bff';
    my $bff = redcap2bff($self);

    $self->{method}      = 'bff2omop';
    $self->{data}        = $bff;
    $self->{in_textfile} = 0;

    return merge_omop_tables( $self->array_dispatcher );
}

##########################################################
# OMOP helpers - contain state mutation & pipeline       #
##########################################################

sub _with_temp_self_field {
    my ( $self, $field, $value, $code ) = @_;

    my $had = exists $self->{$field} ? 1 : 0;
    my $old = $had ? $self->{$field} : undef;

    $self->{$field} = $value;
    my $ret = $code->();

    if ($had) { $self->{$field} = $old }
    else      { delete $self->{$field} }

    return $ret;
}

sub _omop_collect_input {
    my ($self) = @_;

    # MEMORY input
    if ( exists $self->{data} ) {
        $self->{omop_cli} = 0;
        return {
            kind            => 'memory',
            data            => $self->{data},
            filepath_sql    => undef,
            filepaths_csv   => [],
        };
    }

    # CLI / files input
    $self->{omop_cli} = 1;

    my $data = {};
    my $filepath_sql;
    my @filepaths_csv_stream;

    my @exts = map { $_, $_ . '.gz' } qw(.csv .tsv .sql);

    for my $file ( @{ $self->{in_files} } ) {
        my ( $table_name, undef, $ext ) = fileparse( $file, @exts );

        # SQL dump
        if ( $ext =~ m/\.sql/i ) {
            print "> Param: --max-lines-sql = $self->{max_lines_sql}\n"
              if $self->{verbose};

            if ( !$self->{stream} ) {
                print "> Mode : --no-stream\n\n" if $self->{verbose};
                my $sql_headers;
                ( $data, $sql_headers ) = read_sqldump( { in => $file, self => $self } );
                sqldump2csv( $data, $self->{out_dir}, $sql_headers ) if $self->{sql2csv};
            }
            else {
                print "> Mode : --stream\n\n" if $self->{verbose};

                _with_temp_self_field(
                    $self,
                    'omop_tables',
                    [@stream_ram_memory_tables],
                    sub {
                        ( $data, undef ) = read_sqldump( { in => $file, self => $self } );
                        return 1;
                    }
                );
            }

            print "> Parameter --max-lines-sql set to: $self->{max_lines_sql}\n\n"
              if $self->{verbose};

            $filepath_sql = $file;
            last;
        }

        # CSV/TSV
        warn "<$table_name> is not a valid table in OMOP-CDM\n" and next
          unless any { $_ eq $table_name } @omop_essential_tables;

        my $msg = "Reading <$table_name> and storing it in RAM memory...";

        if ( !$self->{stream} ) {
            say $msg if ( $self->{verbose} || $self->{debug} );
            $data->{$table_name} =
              read_csv( { in => $file, sep => $self->{sep}, self => $self } );
        }
        else {
            if ( any { $_ eq $table_name } @stream_ram_memory_tables ) {
                say $msg if ( $self->{verbose} || $self->{debug} );
                $data->{$table_name} =
                  read_csv( { in => $file, sep => $self->{sep}, self => $self } );
            }
            else {
                push @filepaths_csv_stream, $file;
            }
        }
    }

    return {
        kind            => ( $filepath_sql ? 'sql' : 'csv' ),
        data            => $data,
        filepath_sql    => $filepath_sql,
        filepaths_csv   => \@filepaths_csv_stream,
    };
}

sub _omop_require_concept {
    my ( $self, $data ) = @_;
    die "The table <CONCEPT> is missing from the input files\n"
      unless exists $data->{CONCEPT};
    return 1;
}

sub _omop_init_caches_and_metadata {
    my ( $self, $data ) = @_;

    $self->{data_ohdsi_dict} =
      convert_table_aoh_to_hoh( $data, 'CONCEPT', $self );

    if ( $self->{stream} ) {
        $self->{person} = convert_table_aoh_to_hoh( $data, 'PERSON', $self );
    }

    if ( exists $data->{VISIT_OCCURRENCE} ) {
        $self->{visit_occurrence} =
          convert_table_aoh_to_hoh( $data, 'VISIT_OCCURRENCE', $self );
        delete $data->{VISIT_OCCURRENCE};
    }

    $self->{exposures} = load_exposures( $self->{exposures_file} );

    $self->{metaData}     = get_metaData($self);
    $self->{convertPheno} = get_info($self);

    return 1;
}

sub _omop_prepare_data_shape {
    my ( $self, $data ) = @_;
    $self->{data} =
      $self->{stream} ? $data : transpose_omop_data_structure( $self, $data );
    return 1;
}

##############
##############
#  OMOP2BFF  #
##############
##############

sub omop2bff {
    my $self = shift;

    $self->{method_ori} =
      exists $self->{method_ori} ? $self->{method_ori} : 'omop2bff';
    $self->{prev_omop_tables} = [ @{ $self->{omop_tables} } ];

    my $ctx  = _omop_collect_input($self);
    my $data = $ctx->{data};

    _omop_require_concept( $self, $data );
    _omop_init_caches_and_metadata( $self, $data );
    _omop_prepare_data_shape( $self, $data );

    $data = undef;

    if ( $self->{stream} ) {
        return omop_stream_dispatcher(
            { self => $self, filepath => $ctx->{filepath_sql}, filepaths => $ctx->{filepaths_csv} }
        );
    }

    return $self->array_dispatcher;
}

##############
##############
#  OMOP2PXF  #
##############
##############

sub omop2pxf {
    my $self = shift;

    if ( exists $self->{data} ) {
        $self->{omop_cli} = 0;
        $self->{method}   = 'omop2bff';
        my $bff = omop2bff($self);

        $self->{method}      = 'bff2pxf';
        $self->{data}        = $bff;
        $self->{in_textfile} = 0;

        return $self->array_dispatcher;
    }

    $self->{method_ori} = 'omop2pxf';
    $self->{method}     = 'omop2bff';
    $self->{omop_cli}   = 1;

    return omop2bff($self);
}

###############
###############
#  CDISC2BFF  #
###############
###############

sub cdisc2bff {
    my $self = shift;
    my $str  = path( $self->{in_file} )->slurp_utf8;
    my $hash = xml2hash $str, attr => '-', text => '~';
    my $data = cdisc2redcap($hash);

    my $data_redcap_dict = read_redcap_dict_file(
        {
            redcap_dictionary => $self->{redcap_dictionary},
        }
    );
    my $data_mapping_file = read_mapping_file(
        {
            mapping_file         => $self->{mapping_file},
            self_validate_schema => $self->{self_validate_schema},
            schema_file          => $self->{schema_file}
        }
    );

    $self->{data}              = $data;
    $self->{data_redcap_dict}  = $data_redcap_dict;
    $self->{data_mapping_file} = $data_mapping_file;

    return $self->array_dispatcher;
}

###############
###############
#  CDISC2PXF  #
###############
###############

sub cdisc2pxf {
    my $self = shift;

    $self->{method} = 'cdisc2bff';
    my $bff = cdisc2bff($self);

    $self->{method}      = 'bff2pxf';
    $self->{data}        = $bff;
    $self->{in_textfile} = 0;

    return $self->array_dispatcher;
}

################
################
#  CDISC2OMOP  #
################
################

sub cdisc2omop {
    my $self = shift;

    $self->{method} = 'cdisc2bff';
    my $bff = cdisc2bff($self);

    $self->{method}      = 'bff2omop';
    $self->{data}        = $bff;
    $self->{in_textfile} = 0;

    return merge_omop_tables( $self->array_dispatcher );
}

#############
#############
#  PXF2BFF  #
#############
#############

sub pxf2bff {
    my $self = shift;
    return $self->array_dispatcher;
}

##############
##############
#  PXF2OMOP  #
##############
##############

sub pxf2omop {
    my $self = shift;

    $self->{method} = 'pxf2bff';
    my $bff = pxf2bff($self);

    $self->{method}      = 'bff2omop';
    $self->{data}        = $bff;
    $self->{in_textfile} = 0;

    return merge_omop_tables( $self->array_dispatcher );
}

#############
#############
#  CSV2BFF  #
#############
#############

sub csv2bff {
    my $self = shift;

    my $data = read_csv( { in => $self->{in_file}, sep => $self->{sep} } );

    my $data_mapping_file = read_mapping_file(
        {
            mapping_file         => $self->{mapping_file},
            self_validate_schema => $self->{self_validate_schema},
            schema_file          => $self->{schema_file}
        }
    );

    $self->{data}              = $data;
    $self->{data_mapping_file} = $data_mapping_file;
    $self->{metaData}          = get_metaData($self);
    $self->{convertPheno}      = get_info($self);

    return $self->array_dispatcher;
}

#############
#############
#  CSV2PXF  #
#############
#############

sub csv2pxf {
    my $self = shift;

    $self->{method} = 'csv2bff';
    my $bff = csv2bff($self);

    $self->{method}      = 'bff2pxf';
    $self->{data}        = $bff;
    $self->{in_textfile} = 0;

    return $self->array_dispatcher;
}

##############
##############
#  CSV2OMOP  #
##############
##############

sub csv2omop {
    my $self = shift;

    $self->{method} = 'csv2bff';
    my $bff = csv2bff($self);

    $self->{method}      = 'bff2omop';
    $self->{data}        = $bff;
    $self->{in_textfile} = 0;

    return merge_omop_tables( $self->array_dispatcher );
}

#############
#############
#  PXF2CSV  #
#############
#############

sub pxf2csv {
    my $self = shift;
    return $self->array_dispatcher;
}

#############
#############
# PXFJSONF  #
#############
#############

sub pxf2jsonf {
    my $self = shift;
    return $self->array_dispatcher;
}

##############
##############
# PXF2JSONLD #
##############
##############

sub pxf2jsonld {
    my $self = shift;
    return $self->array_dispatcher;
}

#################
#################
#  HELPER SUBS  #
#################
#################

sub _dispatcher_input_data {
    my ($self) = @_;
    return ( $self->{in_textfile} && $self->{method} !~ m/^(redcap2|omop2|cdisc2|csv)/ )
      ? io_yaml_or_json( { filepath => $self->{in_file}, mode => 'read' } )
      : $self->{data};
}

sub _dispatcher_open_stream_out {
    my ($self) = @_;
    return unless ( $self->{method} eq 'omop2bff' && $self->{omop_cli} );

    my $fh = open_filehandle( $self->{out_file}, 'a' );
    say $fh "[";
    return { fh => $fh, first => 1 };
}

sub array_dispatcher {
    my $self = shift;

    my $in_data = _dispatcher_input_data($self);

    my %func = (
        redcap2bff => \&do_redcap2bff,
        cdisc2bff  => \&do_cdisc2bff,
        omop2bff   => \&do_omop2bff,
        csv2bff    => \&do_csv2bff,
        csv2pxf    => \&do_csv2pxf,
        bff2pxf    => \&do_bff2pxf,
        bff2csv    => \&do_bff2csv,
        bff2jsonf  => \&do_bff2csv,
        bff2jsonld => \&do_bff2jsonld,
        bff2omop   => \&do_bff2omop,
        pxf2bff    => \&do_pxf2bff,
        pxf2csv    => \&do_pxf2csv,
        pxf2jsonf  => \&do_pxf2csv,
        pxf2jsonld => \&do_pxf2jsonld,
    );

    open_connections_SQLite($self) if $self->{method} ne 'bff2pxf';

    my $json   = JSON::XS->new->canonical->pretty;
    my $stream = _dispatcher_open_stream_out($self);

    my $out_data;  # IMPORTANT: can be ARRAYREF or scalar, matching old behavior

    my $emit_array_item = sub {
        my ($obj) = @_;
        return unless $obj;

        if ($stream) {
            print { $stream->{fh} } ",\n" unless $stream->{first};
            _transform_item($self, $obj, $stream->{fh}, 1, $json);
            $stream->{first} = 0;
            return;
        }

        push @{ $out_data }, $obj;
    };

    if (ref($in_data) eq 'ARRAY') {
        say "$self->{method}: ARRAY" if $self->{debug};

        $out_data = [];  # array mode returns arrayref (as before)

        my $total    = 0;
        my $elements = scalar @$in_data;

        for (my $i = 0; $i < $elements; $i++) {
            my $count = $i + 1;
            my $item  = $in_data->[$i];

            say "[$count] ARRAY ELEMENT from $elements" if $self->{debug};

            my $res = $func{ $self->{method} }->($self, $item);
            if ($res) {
                $total++;
                say " * [$count] ARRAY ELEMENT is defined" if $self->{debug};
                $emit_array_item->($res);

                last if ( $self->{method} eq 'omop2bff'
                       && $self->{max_lines_sql}
                       && $total >= $self->{max_lines_sql} );
            }
        }

        @$in_data = ();  # preserve old side effect

        say "==============\nIndividuals total:     $total\n"
          if ( $self->{verbose} && $self->{method} eq 'omop2bff' );
    }
    else {
        say "$self->{method}: NOT ARRAY" if $self->{debug};

        my $res = $func{ $self->{method} }->($self, $in_data);

        if ($stream) {
            # stream mode expects array output; a single object is one element in array
            if ($res) {
                _transform_item($self, $res, $stream->{fh}, 1, $json);
                $stream->{first} = 0;
            }
            $out_data = 1;  # keep your old "return 1" semantics in streaming after closing
        }
        else {
            # scalar mode returns scalar (HASHREF), matching old behavior
            $out_data = $res;
        }
    }

    close_connections_SQLite($self) unless $self->{method} eq 'bff2pxf';

    if ($stream) {
        say { $stream->{fh} } "\n]";
        close $stream->{fh};
        return 1;
    }

    return $out_data;
}

sub _transform_item {
    my ( $self, $method_result, $fh_out, $is_last_item, $json ) = @_;

    $json //= JSON::XS->new->canonical->pretty;

    my $out;

    if ( $self->{method_ori} && $self->{method_ori} eq 'omop2pxf' ) {
        my $pxf = do_bff2pxf( $self, $method_result );
        $out = $json->encode($pxf);
    }
    else {
        $out = $json->encode($method_result);
    }

    chomp $out;
    print $fh_out $out;

    return 1;
}

sub omop_dispatcher {
    my ( $self, $method_result, $json ) = @_;

    $json //= JSON::XS->new->canonical->pretty;

    my $out;

    if ( $self->{method_ori} ne 'omop2pxf' ) {
        $out = $json->encode($method_result);
    }
    else {
        my $pxf = do_bff2pxf( $self, $method_result );
        $out = $json->encode($pxf);
    }
    chomp $out;
    return \$out;
}

sub omop_stream_dispatcher {
    my $arg         = shift;
    my $self        = $arg->{self};
    my $filepath    = $arg->{filepath};
    my $filepaths   = $arg->{filepaths};
    my $omop_tables = $self->{prev_omop_tables};

    open_connections_SQLite($self) if $self->{method} ne 'bff2pxf';

    return @$filepaths
      ? process_csv_files_stream( $self, $filepaths )
      : process_sqldump_stream( $self, $filepath, $omop_tables );
}

sub process_csv_files_stream {
    my ( $self, $filepaths ) = @_;
    my $person = $self->{person};
    for my $file (@$filepaths) {
        say "Processing file ... <$file>" if $self->{verbose};
        read_csv_stream(
            {
                in     => $file,
                sep    => $self->{sep},
                self   => $self,
                person => $person
            }
        );
    }
    return 1;
}

sub process_sqldump_stream {
    my ( $self, $filepath, $omop_tables ) = @_;
    my $person = $self->{person};

    for my $table (@$omop_tables) {
        next if any { $_ eq $table } @stream_ram_memory_tables;
        say "Processing table <$table> line-by-line..." if $self->{verbose};

        _with_temp_self_field(
            $self,
            'omop_tables',
            [$table],
            sub {
                read_sqldump_stream(
                    { in => $filepath, self => $self, person => $person }
                );
                return 1;
            }
        );
    }
    return 1;
}

sub omop2bff_stream_processing {
    my ( $self, $data ) = @_;
    return do_omop2bff( $self, $data );
}

sub Dumper_concise {
    {
        local $Data::Dumper::Terse     = 1;
        local $Data::Dumper::Indent    = 1;
        local $Data::Dumper::Useqq     = 1;
        local $Data::Dumper::Deparse   = 1;
        local $Data::Dumper::Quotekeys = 1;
        local $Data::Dumper::Sortkeys  = 1;
        local $Data::Dumper::Pair      = ' : ';
        print Dumper shift;
    }
}

1;

=head1 NAME

Convert::Pheno - A module to interconvert common data models for phenotypic data

=head1 SYNOPSIS

 use Convert::Pheno;

 my $my_pxf_json_data = {
     "phenopacket" => {
         "id"      => "P0007500",
         "subject" => {
             "id"          => "P0007500",
             "dateOfBirth" => "unknown-01-01T00:00:00Z",
             "sex"         => "FEMALE"
         }
     }
 };

 # Create object
 my $convert = Convert::Pheno->new(
     {
         data   => $my_pxf_json_data,
         method => 'pxf2bff'
     }
 );

 # Apply a method
 my $data = $convert->pxf2bff;

=head1 DESCRIPTION

For a better description, please read the following documentation:

=over

=item General:

L<https://cnag-biomedical-informatics.github.io/convert-pheno>

=item Command-Line Interface:

L<https://github.com/CNAG-Biomedical-Informatics/convert-pheno#readme>

=back

=head1 CITATION

The author requests that any published work that utilizes C<Convert-Pheno> includes a cite to the the following reference:

Rueda, M et al., (2024). Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data. Journal of Biomedical Informatics. L<DOI|https://doi.org/10.1016/j.jbi.2023.104558>

=head1 AUTHOR

Written by Manuel Rueda, PhD. Info about CNAG can be found at L<https://www.cnag.eu>.

=head1 METHODS

See L<https://cnag-biomedical-informatics.github.io/convert-pheno/use-as-a-module>.

=head1 COPYRIGHT

This PERL file is copyrighted. See the LICENSE file included in this distribution.

=cut
