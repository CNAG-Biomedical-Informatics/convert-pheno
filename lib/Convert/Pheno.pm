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
use Convert::Pheno::Context;
use Convert::Pheno::Runner qw(run_operation);
use Convert::Pheno::Emit::OMOP qw(
  dispatcher_open_stream_out
  transform_item
  finalize_stream_out
);
use Convert::Pheno::OMOP::Source qw(collect_omop_input);
use Convert::Pheno::OMOP::ParticipantStream qw(
  omop_require_concept
  omop_init_caches_and_metadata
  omop_prepare_data_shape
);
use Convert::Pheno::OMOP::Definitions;
use Convert::Pheno::DB::SQLite;
use Convert::Pheno::Mapping::Shared;
use Convert::Pheno::CSV;
use Convert::Pheno::JSONLD qw(do_bff2jsonld do_pxf2jsonld);
use Convert::Pheno::OMOP::ToBFF qw(do_omop2bff);
use Convert::Pheno::PXF::ToBFF;
use Convert::Pheno::BFF::ToPXF;
use Convert::Pheno::BFF::ToOMOP;
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
    qw /out_file out_dir in_textfile in_file sep sql2csv redcap_dictionary mapping_file schema_file debug log verbose search_audit_file/
] => ( is => 'ro' );

has [qw /data method/] => ( is => 'rw' );
has entities => ( is => 'ro', default => sub { ['individuals'] } );

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
    return _run_primary_view($self);
}

#############
#############
#  BFF2CSV  #
#############
#############

sub bff2csv {
    my $self = shift;
    return _run_primary_view($self);
}

#############
#############
# BFF2JSONF #
#############
#############

sub bff2jsonf {
    my $self = shift;
    return _run_primary_view($self);
}

##############
##############
# BFF2JSONLD #
##############
##############

sub bff2jsonld {
    my $self = shift;
    return _run_primary_view($self);
}

##############
##############
#  BFF2OMOP  #
##############
##############

sub bff2omop {
    my $self = shift;
    return merge_omop_tables( _run_primary_view($self) );
}

################
################
#  REDCAP2BFF  #
################
################

sub redcap2bff {
    my $self = shift;

    my $data = read_csv(
        {
            in             => $self->{in_file},
            sep            => $self->{sep},
            coerce_numbers => 0,
        }
    );
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

    return _run_primary_view($self);
}

################
################
#  REDCAP2PXF  #
################
################

sub redcap2pxf {
    my $self = shift;
    return _convert_via_bff(
        $self,
        via_method => 'redcap2bff',
        to_method  => 'bff2pxf',
    );
}

#################
#################
#  REDCAP2OMOP  #
#################
#################

sub redcap2omop {
    my $self = shift;
    return _convert_via_bff(
        $self,
        via_method => 'redcap2bff',
        to_method  => 'bff2omop',
        merge_omop => 1,
    );
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
    return collect_omop_input($self);
}

sub _omop_require_concept {
    return omop_require_concept(@_);
}

sub _omop_init_caches_and_metadata {
    return omop_init_caches_and_metadata(@_);
}

sub _omop_prepare_data_shape {
    return omop_prepare_data_shape(@_);
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
    $self->{conversion_context} = Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => 'omop',
            target_format => 'beacon',
            entities      => ['individuals'],
        }
    );

    $data = undef;

    if ( $self->{stream} ) {
        return omop_stream_dispatcher(
            { self => $self, filepath => $ctx->{filepath_sql}, filepaths => $ctx->{filepaths_csv} }
        );
    }

    return _run_primary_view($self);
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
        return _convert_via_bff(
            $self,
            via_method => 'omop2bff',
            to_method  => 'bff2pxf',
        );
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
    $self->{metaData}          = get_metaData($self);
    $self->{convertPheno}      = get_info($self);

    return _run_primary_view($self);
}

###############
###############
#  CDISC2PXF  #
###############
###############

sub cdisc2pxf {
    my $self = shift;
    return _convert_via_bff(
        $self,
        via_method => 'cdisc2bff',
        to_method  => 'bff2pxf',
    );
}

################
################
#  CDISC2OMOP  #
################
################

sub cdisc2omop {
    my $self = shift;
    return _convert_via_bff(
        $self,
        via_method => 'cdisc2bff',
        to_method  => 'bff2omop',
        merge_omop => 1,
    );
}

#############
#############
#  PXF2BFF  #
#############
#############

sub pxf2bff {
    my $self = shift;
    $self->{convertPheno} = get_info($self);
    $self->{conversion_context} = Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => 'pxf',
            target_format => 'beacon',
            entities      => ['individuals'],
        }
    );
    return _run_primary_view($self);
}

##############
##############
#  PXF2OMOP  #
##############
##############

sub pxf2omop {
    my $self = shift;
    return _convert_via_bff(
        $self,
        via_method => 'pxf2bff',
        to_method  => 'bff2omop',
        merge_omop => 1,
    );
}

#############
#############
#  CSV2BFF  #
#############
#############

sub csv2bff {
    my $self = shift;

    my $data = read_csv(
        {
            in             => $self->{in_file},
            sep            => $self->{sep},
            coerce_numbers => 0,
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
    $self->{data_mapping_file} = $data_mapping_file;
    $self->{metaData}          = get_metaData($self);
    $self->{convertPheno}      = get_info($self);

    return _run_primary_view($self);
}

#############
#############
#  CSV2PXF  #
#############
#############

sub csv2pxf {
    my $self = shift;
    return _convert_via_bff(
        $self,
        via_method => 'csv2bff',
        to_method  => 'bff2pxf',
    );
}

##############
##############
#  CSV2OMOP  #
##############
##############

sub csv2omop {
    my $self = shift;
    return _convert_via_bff(
        $self,
        via_method => 'csv2bff',
        to_method  => 'bff2omop',
        merge_omop => 1,
    );
}

#############
#############
#  PXF2CSV  #
#############
#############

sub pxf2csv {
    my $self = shift;
    return _run_primary_view($self);
}

#############
#############
# PXFJSONF  #
#############
#############

sub pxf2jsonf {
    my $self = shift;
    return _run_primary_view($self);
}

##############
##############
# PXF2JSONLD #
##############
##############

sub pxf2jsonld {
    my $self = shift;
    return _run_primary_view($self);
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
    return dispatcher_open_stream_out(@_);
}

sub _run_primary_view {
    my ($self) = @_;
    return run_operation(
        $self,
        _dispatcher_input_data($self),
        view => 'primary',
    );
}

sub _run_bundle_view {
    my ($self) = @_;
    return run_operation(
        $self,
        _dispatcher_input_data($self),
        view => 'bundle',
    );
}

sub _with_temp_self_fields {
    my ( $self, $fields, $code ) = @_;

    my %state;
    for my $field ( keys %{$fields} ) {
        $state{$field} = {
            had   => exists $self->{$field} ? 1 : 0,
            value => exists $self->{$field} ? $self->{$field} : undef,
        };
        $self->{$field} = $fields->{$field};
    }

    my ( $ok, $err, @ret );
    my $wantarray = wantarray;
    $ok = eval {
        if ( !defined $wantarray ) {
            $code->();
            @ret = ();
        }
        elsif ($wantarray) {
            @ret = $code->();
        }
        else {
            $ret[0] = $code->();
        }
        1;
    };
    $err = $@;

    for my $field ( keys %{$fields} ) {
        if ( $state{$field}{had} ) {
            $self->{$field} = $state{$field}{value};
        }
        else {
            delete $self->{$field};
        }
    }

    die $err unless $ok;
    return if !defined $wantarray;
    return $wantarray ? @ret : $ret[0];
}

sub _convert_via_bff {
    my ( $self, %arg ) = @_;
    my $via_method = $arg{via_method};

    my $bff = _with_temp_self_fields(
        $self,
        { method => $via_method },
        sub {
            return $self->$via_method();
        }
    );

    # Compound CLI commands stay stable, but internally they are a
    # simple two-step pipeline through the BFF intermediate.
    return _with_temp_self_fields(
        $self,
        {
            method      => $arg{to_method},
            data        => $bff,
            in_textfile => 0,
        },
        sub {
            my $out = _run_primary_view($self);
            return $arg{merge_omop} ? merge_omop_tables($out) : $out;
        }
    );
}

sub _transform_item {
    return transform_item(@_);
}

sub omop_dispatcher {
    return Convert::Pheno::Emit::OMOP::omop_dispatcher(@_);
}

sub omop_stream_dispatcher {
    return Convert::Pheno::OMOP::ParticipantStream::omop_stream_dispatcher(@_);
}

sub process_csv_files_stream {
    return Convert::Pheno::OMOP::ParticipantStream::process_csv_files_stream(@_);
}

sub process_sqldump_stream {
    return Convert::Pheno::OMOP::ParticipantStream::process_sqldump_stream(@_);
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
