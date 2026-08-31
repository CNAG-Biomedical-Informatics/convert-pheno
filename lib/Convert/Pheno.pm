package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature               qw(say);
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use File::Basename;
use File::ShareDir::ProjectDistDir;
use List::Util qw(any uniq);
use Moo;
use Types::Standard                qw(Str Int Num Enum ArrayRef Undef);
use File::ShareDir::ProjectDistDir qw(dist_dir);
#use Devel::Size     qw(size total_size);
use Convert::Pheno::IO::CSVHandler;
use Convert::Pheno::IO::FileIO;
use Convert::Pheno::Context;
use Convert::Pheno::Pipeline qw(run_conversion_pipeline);
use Convert::Pheno::Runner qw(run_operation);
use Convert::Pheno::Source qw(prepare_source source_adapter);
use Convert::Pheno::Operations qw(conversion_spec);
use Convert::Pheno::Emit::OMOP qw(
  dispatcher_open_stream_out
  transform_item
  finalize_stream_out
  omop_stream_targets_open
  omop_stream_targets_write
  omop_stream_targets_finalize
  omop_streams_multiple_entities
);
use Convert::Pheno::OMOP::Definitions;
use Convert::Pheno::DB::SQLite;
use Convert::Pheno::Mapping::Shared;
use Convert::Pheno::CSV;
use Convert::Pheno::JSONLD qw(do_bff2jsonld do_pxf2jsonld);
use Convert::Pheno::OMOP::ToBFF qw(do_omop2bff);
use Convert::Pheno::BFF::ToPXF;
use Convert::Pheno::BFF::ToOMOP;

use Exporter 'import';
our @EXPORT =
  qw($VERSION io_yaml_or_json omop2bff_stream_processing share_dir);    # Symbols imported by default

#our @EXPORT_OK = qw(foo bar);       # Symbols imported by request

use constant DEVEL_MODE => 0;

# Global variables:
our $VERSION   = '0.34_1';
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
    is      => 'ro',
    default => sub { 'exact' },
    coerce  => sub { $_[0] // 'exact' },
    isa     => Enum [qw(exact mixed fuzzy)]
);

has text_similarity_method => (
    is      => 'ro',
    default => sub { 'cosine' },
    coerce  => sub { $_[0] // 'cosine' },
    isa     => Enum [qw(cosine dice)]
);

has min_text_similarity_score => (
    is      => 'ro',
    default => sub { 0.8 },
    coerce  => sub { $_[0] // 0.8 },
    isa     => sub {
        die "Only values between 0 .. 1 supported!"
          unless ( $_[0] >= 0.0 && $_[0] <= 1.0 );
    }
);
has levenshtein_weight => (
    is      => 'ro',
    default => sub { 0.1 },
    coerce  => sub { $_[0] // 0.1 },
    isa     => sub {
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

# Internal safety limit used by HTTP uploads. A value of zero leaves local
# CLI and module conversions unrestricted.
has max_archive_uncompressed_bytes => (
    is      => 'ro',
    default => sub { 0 },
    coerce  => sub { $_[0] // 0 },
    isa     => Int,
);

has 'omop_tables' => (
    default => sub { [@omop_supported_tables] },
    coerce  => sub {
        my $tables = shift;

        $tables =
          @$tables
          ? [ uniq( map { uc($_) } ( 'CONCEPT', 'PERSON', @$tables ) ) ]
          : \@omop_supported_tables;

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
has [qw /test self_validate_schema path_to_ohdsi_db/] =>
  ( default => undef, is => 'ro' );

has [qw /stream ohdsi_db/] => ( default => 0, is => 'ro' );
has source_info => ( default => 1, is => 'ro' );

has default_vital_status => (
    is     => 'ro',
    coerce => sub { $_[0] // 'ALIVE' },
    isa    => Enum [qw(ALIVE DECEASED UNKNOWN_STATUS)]
);

has [qw /in_files/] => ( default => sub { [] }, is => 'ro' );

has [
    qw /out_file out_dir in_textfile in_file sep sql2csv redcap_dictionary mapping_file schema_file define_xml debug log verbose term_audit_file/
] => ( is => 'ro' );

has [qw /data method/] => ( is => 'rw' );
has entities => ( is => 'ro', default => sub { ['individuals'] } );
has derived_entity_overrides => ( is => 'ro', default => sub { {} } );
has output_name_overrides => ( is => 'ro', default => sub { {} } );

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
    return _run_source_to_bff( $self, 'redcap' );
}

################
################
#  REDCAP2PXF  #
################
################

sub redcap2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

#################
#################
#  REDCAP2OMOP  #
#################
#################

sub redcap2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

###################
###################
# CBIOPORTAL2BFF   #
###################
###################

sub cbioportal2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'cbioportal' );
}

###################
###################
# CBIOPORTAL2PXF   #
###################
###################

sub cbioportal2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

###################
###################
# CBIOPORTAL2OMOP  #
###################
###################

sub cbioportal2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

########################
# RELATIONAL CDM INPUTS #
########################

sub i2b22bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'i2b2' );
}

sub i2b22pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

sub i2b22omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

sub sentinel2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'sentinel' );
}

sub sentinel2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

sub sentinel2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

sub pcornet2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'pcornet' );
}

sub pcornet2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

sub pcornet2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

##############
##############
#  OMOP2BFF  #
##############
##############

sub omop2bff {
    my $self = shift;
    _prepare_source_to_bff( $self, 'omop' );
    _set_bff_context( $self, 'omop' );

    if ( $self->{stream} ) {
        return _with_prepared_data_cleanup(
            $self,
            sub {
                return omop_stream_dispatcher(
                    {
                        self      => $self,
                        filepath  => $self->{filepath_sql},
                        filepaths => $self->{filepaths_csv},
                    }
                );
            }
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
    return run_conversion_pipeline($self);
}

###############
###############
# CDISCODM2BFF #
###############
###############

sub cdiscodm2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'cdisc-odm' );
}

###############
###############
# CDISCODM2PXF #
###############
###############

sub cdiscodm2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

################
################
# CDISCODM2OMOP #
################
################

sub cdiscodm2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

####################
####################
# DATASETJSON2BFF   #
####################
####################

sub datasetjson2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'dataset-json' );
}

####################
####################
# DATASETJSON2PXF   #
####################
####################

sub datasetjson2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

####################
####################
# DATASETJSON2OMOP  #
####################
####################

sub datasetjson2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

###################
###################
# DATASETXML2BFF   #
###################
###################

sub datasetxml2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'dataset-xml' );
}

###################
###################
# DATASETXML2PXF   #
###################
###################

sub datasetxml2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

###################
###################
# DATASETXML2OMOP  #
###################
###################

sub datasetxml2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

##############
##############
#  FHIR2BFF  #
##############
##############

sub fhir2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'fhir' );
}

##############
##############
#  FHIR2PXF  #
##############
##############

sub fhir2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

##############
##############
# FHIR2OMOP  #
##############
##############

sub fhir2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

#############
#############
#  PXF2BFF  #
#############
#############

sub pxf2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'pxf' );
}

##############
##############
#  PXF2OMOP  #
##############
##############

sub pxf2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
}

#################
#################
# OPENEHR2BFF   #
#################
#################

sub openehr2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'openehr' );
}

#################
#################
# OPENEHR2PXF   #
#################
#################

sub openehr2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

#############
#############
#  CSV2BFF  #
#############
#############

sub csv2bff {
    my $self = shift;
    return _run_source_to_bff( $self, 'csv' );
}

#############
#############
#  CSV2PXF  #
#############
#############

sub csv2pxf {
    my $self = shift;
    return run_conversion_pipeline($self);
}

##############
##############
#  CSV2OMOP  #
##############
##############

sub csv2omop {
    my $self = shift;
    return run_conversion_pipeline($self);
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
    return $self->{data} if exists $self->{data};
    return $self->{data}
      unless $self->{in_textfile}
      && $self->{method} !~ m/^(redcap2|omop2|cdiscodm2|csv)/;

    my $spec = conversion_spec( $self->{method} )
      or die "Unsupported conversion <$self->{method}>\n";
    return source_adapter( $self, $spec->{source} )->load->data;
}

sub _dispatcher_open_stream_out {
    return dispatcher_open_stream_out(@_);
}

sub _run_primary_view {
    my ($self) = @_;
    return _run_view( $self, 'primary' );
}

sub _prepare_source_to_bff {
    my ( $self, $format ) = @_;
    prepare_source( $self, $format );
    $self->{convertPheno} ||= get_info($self);
    return 1;
}

sub _set_bff_context {
    my ( $self, $format ) = @_;
    $self->{conversion_context} = Convert::Pheno::Context->from_self(
        $self,
        {
            source_format => $format,
            target_format => 'beacon',
            entities      => $self->{entities} || ['individuals'],
        }
    );
    return 1;
}

sub _run_source_to_bff {
    my ( $self, $format ) = @_;
    _prepare_source_to_bff( $self, $format );
    _set_bff_context( $self, $format );
    return _run_primary_view($self);
}

sub _run_bundle_view {
    my ($self) = @_;
    my $spec = conversion_spec( $self->{method} )
      or die "Unsupported conversion <$self->{method}>\n";
    _prepare_source_to_bff( $self, $spec->{source} );
    delete $self->{conversion_context};
    return _run_view( $self, 'bundle' );
}

sub _run_view {
    my ( $self, $view ) = @_;
    my $input = _dispatcher_input_data($self);

    return _with_prepared_data_cleanup(
        $self,
        sub {
            return run_operation(
                $self,
                $input,
                view => $view,
            );
        }
    );
}

sub _with_prepared_data_cleanup {
    my ( $self, $code ) = @_;
    my $owns_prepared_data = delete $self->{_owns_prepared_data};

    my ( $ok, $error, $result );
    $ok = eval {
        $result = $code->();
        1;
    };
    $error = $@ unless $ok;

    # Module callers own their references. Only release buffers loaded or
    # derived internally; clearing a caller's array corrupts reusable input.
    delete $self->{data} if $owns_prepared_data;
    delete $self->{_source_cleanup_guards};

    die $error unless $ok;
    return $result;
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
    return Convert::Pheno::OMOP::ToBFF::run_omop_to_bundle(
        $self, $data, $self->{conversion_context}
      )
      if omop_streams_multiple_entities($self);

    return do_omop2bff( $self, $data );
}

sub omop_stream_targets_open_wrapper {
    return omop_stream_targets_open(@_);
}

sub omop_stream_targets_write_wrapper {
    return omop_stream_targets_write(@_);
}

sub omop_stream_targets_finalize_wrapper {
    return omop_stream_targets_finalize(@_);
}

sub omop_streams_multiple_entities_wrapper {
    return omop_streams_multiple_entities(@_);
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

Convert::Pheno - Convert clinical and phenotypic data between supported models

=head1 SYNOPSIS

 use Convert::Pheno;

 my $pxf = {
     "phenopacket" => {
         "id"      => "P0007500",
         "subject" => {
             "id"          => "P0007500",
             "dateOfBirth" => "2000-01-01T00:00:00Z",
             "sex"         => "FEMALE"
         }
     }
 };

 my $converter = Convert::Pheno->new(
     {
         data   => $pxf,
         method => 'pxf2bff'
     }
 );

 my $individual = $converter->pxf2bff;

=head1 DESCRIPTION

C<Convert::Pheno> is the conversion engine used by the C<convert-pheno>
command-line program. It converts supported in-memory data structures and
route-specific file inputs between Beacon v2 Models Format (BFF),
Phenopackets v2 (PXF), OMOP-CDM, REDCap, cBioPortal clinical study packages,
CDISC-ODM, CDISC Dataset-JSON, CDISC Dataset-XML, FHIR R4, i2b2, PCORnet CDM,
Sentinel CDM, openEHR, and tabular representations.

Conversion availability and required arguments depend on the selected route.
Mapping-file conversions use the Mapping V2 contract and require
C<mappingVersion: 2>; pre-V2 mapping files are rejected.

=head1 METHODS

=head2 new

 my $converter = Convert::Pheno->new(\%arguments);

Creates a converter. C<method> identifies the public conversion method.
In-memory routes receive decoded input under C<data>; file-based routes use
the arguments documented for that conversion.

=head2 Conversion methods

 my $result = $converter->$method;

In-memory conversions return Perl data structures. Streaming and file-output
routes write to their configured destinations and may instead return a
completion status. See the module guide for supported methods, arguments,
multi-entity results, and Python interoperability.

=head1 DOCUMENTATION

=over

=item Project documentation

L<https://cnag-biomedical-informatics.github.io/convert-pheno>

=item Module usage

L<https://cnag-biomedical-informatics.github.io/convert-pheno/use-as-a-module>

=item Command-line interface

L<https://cnag-biomedical-informatics.github.io/convert-pheno/use-as-a-command-line-interface>

=back

=head1 ERRORS

Invalid input, unsupported routes, and conversion failures raise exceptions.
Callers that need recovery should invoke conversion methods inside C<eval> or
another exception-handling mechanism.

=head1 CITATION

Please cite the following reference in published work that uses
C<Convert-Pheno>:

Rueda, M et al., (2024). Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data. Journal of Biomedical Informatics. L<DOI|https://doi.org/10.1016/j.jbi.2023.104558>

=head1 AUTHOR

Written by Manuel Rueda, PhD. Info about CNAG can be found at L<https://www.cnag.eu>.

=head1 COPYRIGHT AND LICENSE

Copyright 2022-2026 Manuel Rueda and CNAG.

This software is distributed under the Artistic License 2.0. See the LICENSE
file included in this distribution.

=cut
