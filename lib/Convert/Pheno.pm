package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature qw(say);
use FindBin qw($Bin);
use Data::Dumper;
use Path::Tiny;
use File::Basename;
use List::Util qw(any);
use Carp       qw(confess);
use XML::Fast;
use Moo;
use Convert::Pheno::CSV;
use Convert::Pheno::IO;
use Convert::Pheno::SQLite;
use Convert::Pheno::Mapping;
use Convert::Pheno::OMOP;
use Convert::Pheno::PXF;
use Convert::Pheno::BFF;
use Convert::Pheno::CDISC;
use Convert::Pheno::REDCap;

use Exporter 'import';
our @EXPORT = qw($VERSION io_yaml_or_json);    # Symbols imported by default

#our @EXPORT_OK = qw(foo bar);       # Symbols imported by request

use constant DEVEL_MODE => 0;

# Global variables:
our $VERSION = '0.0.0_alpha';

# Declaring attributes for the class
has search => (

    #default => 'exact',
    is     => 'ro',
    coerce => sub { defined $_[0] ? $_[0] : 'exact' },
    isa    => sub {
        die "Only <exact|mixed> values supported!"
          unless ( $_[0] eq 'exact' || $_[0] eq 'mixed' );
    }
);

has text_similarity_method => (

    #default => 'cosine',
    is     => 'ro',
    coerce => sub { defined $_[0] ? $_[0] : 'cosine' },
    isa    => sub {
        die "Only <cosine|dice> values supported!"
          unless ( $_[0] eq 'cosine' || $_[0] eq 'dice' );
    }
);

has min_text_similarity_score => (

    #default => 0.8,
    is     => 'ro',
    coerce => sub { defined $_[0] ? $_[0] : 0.8 },
    isa    => sub {
        die "Only values between 0 .. 1 supported!"
          unless ( $_[0] >= 0.0 && $_[0] <= 1.0 );
    }
);

has username => (
    default => ( $ENV{LOGNAME} || $ENV{USER} || getpwuid($<) ),
    is      => 'ro'
);

has $_ => ( default => undef, is => 'ro' )
  for (qw /test ohdsi_db print_hidden_labels self_validate_schema/);

has $_ => ( default => 1, is => 'ro' )
  for (qw /stream/);

has $_ => ( is => 'rw' )
  for (
    qw /data out_dir in_textfile in_file in_files method sep sql2csv redcap_dictionary mapping_file max_lines_sql schema_file debug log verbose/
  );

# NB: In general, we'll only display terms that exist and have content

#############
#############
#  PXF2BFF  #
#############
#############

sub pxf2bff {

    # <array_dispatcher> will deal with JSON arrays
    return array_dispatcher(shift);
}

#############
#############
#  BFF2PXF  #
#############
#############

sub bff2pxf {

    # <array_dispatcher> will deal with JSON arrays
    return array_dispatcher(shift);
}

################
################
#  REDCAP2BFF  #
################
################

sub redcap2bff {

    my $self = shift;

    # Read and load data from REDCap export
    my $data = read_csv( { in => $self->{in_file}, sep => undef } );
    my ( $data_redcap_dic, $data_mapping_file ) =
      read_redcap_dic_and_mapping_file(
        {
            redcap_dictionary    => $self->{redcap_dictionary},
            mapping_file         => $self->{mapping_file},
            self_validate_schema => $self->{self_validate_schema},
            schema_file          => $self->{schema_file}
        }
      );

    # Load data in $self
    $self->{data}              = $data;                 # Dynamically adding attributes (setter)
    $self->{data_redcap_dic}   = $data_redcap_dic;      # Dynamically adding attributes (setter)
    $self->{data_mapping_file} = $data_mapping_file;    # Dynamically adding attributes (setter)

    # array_dispatcher will deal with JSON arrays
    return array_dispatcher($self);
}

################
################
#  REDCAP2PXF  #
################
################

sub redcap2pxf {

    my $self = shift;

    # First iteration: redcap2bff
    $self->{method} = 'redcap2bff';    # setter - we have to change the value of attr {method}
    my $bff = redcap2bff($self);       # array

    # Preparing for second iteration: bff2pxf
    $self->{method}      = 'bff2pxf';    # setter
    $self->{data}        = $bff;         # setter
    $self->{in_textfile} = 0;            # setter

    # Run second iteration
    return array_dispatcher($self);
}

##############
##############
#  OMOP2BFF  #
##############
##############

sub omop2bff {

    my $self = shift;

    #############
    # IMPORTANT #
    #############

    # SMALL TO MEDIUM FILES < 1GB
    #
    # In many cases, since people are downsizing their DBs for data sharing,
    # PostgreSQL dumps or CSVs will be <500MB. If that's the case, providing we
    # have enough memory (4-16GB), we'll able to load stuff in RAM memory, 
    # and still merge values (MEASURES, DRUGS) for each individual and serialize ALL at once.
    # It's just a matter of only loading ESSENTIAL tables and not duplicating data structures (unless necessary)
    
    # HUMONGOUS FILES > 1GB 
    # NB: Interesting read on the topic
    #     https://www.perlmonks.org/?node_id=1033692
    # Since we're relying heavily on hashes we need to resort to another strategy(es) to load the data
    #
    # * Option A *: Parellel processing - No change in our code
    #    Without changing the code, we ask the user to create mini-instances (or split CSV's in chunks) and use 
    #    some sort of parallel processing (e.g., GNU parallel, snakemake, HPC, etc.)
    #
    # * Option B *: Keeping data grouped at the individual-object level (as we do with small to medium files)
    #   --no-stream
    #   To do this, the only option is to first dump CSV (me or users) and then use *nix to sort by person_id.
    #   Then, since rows for each individual are adjacent, we can load individual data together. Still, 
    #   we'll by reading one table (e.g. MEASUREMENTS) at a time, so this is not relly helping much.
    #
    # * Option C *: Parsing files line by line (one row of CSV/SQL per JSON object)
    #   --stream 
    #   This option seems the more feasible because BFF / PXF JSONs are just intermediate files. It's nice that they
    #   contain data grouped by individual (for visually inspection and display), but at the end of the day they'll 
    #   end up in MongoDB. If all entries contain the primary key 'person_id' then it's up to the Beacon v2 API to deal with them.
    #   It's a similar issue to the one we had with genomicVariations in the B2RI, where a given variant belong to many individuals.
    #   Here, multiple JSON documents/objects (MEASUREMENTS, DRUGS, etc.) will belong to the same individual.
    #   Now, since we allow for CSV and SQL as an input, we need to minimize the numer of steps to a minimum.
    #
    #   - Problems that may arise:
    #     1 - <CONCEPT> table is mandatory, but it can be so huge that it takes all RAM memory.
    #         For instance, <CONCEPT.csv> with 5_808_095 lines = 735 MB
    #                       <CONCEPT_light.csv> with 5_808_094 lines but only 4 columns = 501 MB 
    #                       Anything more than 2M lines kills a 8GB Ram machine.
    #         Solutions: 
    #           a) Not loading the table at all (using SQLite version <ohdsi.db>  
    #           b) Creating a temporary SQLite DB for <CONCEPT>
    #     2 - How to read line-by-line from an SQL dump
    #          If the PostgreSQL dump weights, say, 20GB, do we create CSV tables from it (another ~20GB)? 
    #         Solutions: 
    #           a) Yep, we read <CONCEPT> and <PERSON> and export the needed tables to CSV and go from there.
    #           b) Nope, we read PostgreSQL file twice, one time to load <CONCEPT> and <PERSON> and the second time to load the remaining TABLES.
    #     3 - In --stream mode, do we still allow for --sql2csv? 
    #           We would need to go from functional mode (csv) to filehandlesi and it will take tons of space. 
    #           Then, --stream and -sql2csv are mutually exclusive.
    #
    # Additional info:
    # The idea here is that we'll load ONLY ESSENTIAL TABLES $omop_main_table and @omop_extra_tables in $data,
    # regardless of wheter they are concepts or truly records. 
    # Dictionaries (e.g. <CONCEPT>) will be parsed latter from $data

    # Check if data comes from variable or from file
    my $data;

    # Variable
    if ( exists $self->{data} ) {
        $data = $self->{data};
    }

    # File(s)
    else {

        # Read and load data from OMOP-CDM export
        # First we need to know if we have PostgreSQL dump or a bunch of csv
        my @exts = qw(.csv .tsv .sql);
        for my $file ( @{ $self->{in_files} } ) {
            my ( $table_name, undef, $ext ) = fileparse( $file, @exts );
            if ( $ext eq '.sql' ) {

                # We'll load all OMOP tables ('main' and 'extra') as long as they're not empty
                $data = read_sqldump( $file, $self );
                sqldump2csv( $data, $self->{out_dir} ) if $self->{sql2csv};
                last;
            }
            else {

                # We'll load all OMOP tables (as CSV) as long they have a match in 'main' or 'extra'
                warn "<$table_name> is not a valid table in OMOP-CDM"
                  and next
                  unless any { /^$table_name$/ }
                  ( @{ $omop_main_table->{$omop_version} },
                    @omop_extra_tables );    # global
                $data->{$table_name} =
                  read_csv( { in => $file, sep => $self->{sep} } );
            }
        }
    }

    #print Dumper_concise($data);

    # Primarily with CSVs, it can happen that user does not provide <CONCEPT.csv>
    confess 'We could not find table <CONCEPT> from your input files'
      unless exists $data->{CONCEPT};

    # We create a dictionary for $data->{CONCEPT}
    $self->{data_ohdsi_dic} = remap_ohdsi_dictionary( $data->{CONCEPT} );    # Dynamically adding attributes (setter)

    # Now we need to perform a tranformation of the data where 'person_id' is one row of data
    # NB: Transformation is due ONLY IN $omop_main_table FIELDS, the rest of the tables are not used
    $self->{data} = transpose_omop_data_structure($data);    # Dynamically adding attributes (setter)
    
    # Giving some memory back to the system
    $data = undef;

    # array_dispatcher will deal with JSON arrays
    return array_dispatcher($self);
}

##############
##############
#  OMOP2PXF  #
##############
##############

sub omop2pxf {

    my $self = shift;

    # First iteration: omop2bff
    $self->{method} = 'omop2bff';    # setter - we have to change the value of attr {method}
    my $bff = omop2bff($self);       # array

    # Preparing for second iteration: bff2pxf
    # NB: This 2nd round may take a while if #inviduals > 1000!!!
    $self->{method}      = 'bff2pxf';    # setter
    $self->{data}        = $bff;         # setter
    $self->{in_textfile} = 0;            # setter

    # Run second iteration
    return array_dispatcher($self);
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

    my ( $data_redcap_dic, $data_mapping_file ) =
      read_redcap_dic_and_mapping_file(
        {
            redcap_dictionary    => $self->{redcap_dictionary},
            mapping_file         => $self->{mapping_file},
            self_validate_schema => $self->{self_validate_schema},
            schema_file          => $self->{schema_file}
        }
      );

    # Load data in $self
    $self->{data}              = $data;                 # Dynamically adding attributes (setter)
    $self->{data_redcap_dic}   = $data_redcap_dic;      # Dynamically adding attributes (setter)
    $self->{data_mapping_file} = $data_mapping_file;    # Dynamically adding attributes (setter)

    # array_dispatcher will deal with JSON arrays
    return array_dispatcher($self);
}

###############
###############
#  CDISC2PXF  #
###############
###############

sub cdisc2pxf {

    my $self = shift;

    # First iteration: cdisc2bff
    $self->{method} = 'cdisc2bff';    # setter - we have to change the value of attr {method}
    my $bff = cdisc2bff($self);       # array

    # Preparing for second iteration: bff2pxf
    $self->{method}      = 'bff2pxf';    # setter
    $self->{data}        = $bff;         # setter
    $self->{in_textfile} = 0;            # setter

    # Run second iteration
    return array_dispatcher($self);
}

######################
######################
#  MISCELLANEA SUBS  #
######################
######################

sub array_dispatcher {

    my $self = shift;

    # Load the input data as Perl data structure
    my $in_data =
      ( $self->{in_textfile} && $self->{method} !~ m/^redcap2|^omop2|^cdisc2/ )
      ? io_yaml_or_json( { filepath => $self->{in_file}, mode => 'read' } )
      : $self->{data};

    # Define the methods to call (naming 'func' to avoid confussion with $self->{method})
    my %func = (
        pxf2bff    => \&do_pxf2bff,
        redcap2bff => \&do_redcap2bff,
        cdisc2bff  => \&do_cdisc2bff,
        omop2bff   => \&do_omop2bff,
        bff2pxf    => \&do_bff2pxf
    );

    # Open connection to SQLlite databases ONCE
    open_connections_SQLite($self) if $self->{method} ne 'bff2pxf';

    # Proceed depending if we have an ARRAY or not
    my $out_data;
    if ( ref $in_data eq ref [] ) {
        say "$self->{method}: ARRAY" if $self->{debug};

        # Caution with the RAM (we store all in memory)
        my $counter = 0;
        for ( @{$in_data} ) {
            say "[$counter] ARRAY ELEMENT" if $self->{debug};
            $counter++;

            # In $self->{data} we have all participants data, but,
            # WE DELIBERATELY SEPARATE ARRAY ELEMENTS FROM $self->{data}

            # NB: If we get "null" participants the validator will complain
            # about not having "id" or any other required property
            my $method_result = $func{ $self->{method} }->( $self, $_ );    # Method
            push @{$out_data}, $method_result if $method_result;
        }
    }
    else {
        say "$self->{method}: NOT ARRAY" if $self->{debug};
        $out_data = $func{ $self->{method} }->( $self, $in_data );          # Method
    }

    # Close connections ONCE
    close_connections_SQLite($self) unless $self->{method} eq 'bff2pxf';

    return $out_data;
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

 # Create a new object
 
 my $convert = Convert::Pheno->new($input);
 
 # Apply a method 
 
 my $data = $convert->redcap2bff;

=head1 DESCRIPTION

=head1 CITATION

The author requests that any published work that utilizes C<Convert-Pheno> includes a cite to the the following reference:

Rueda, M. "Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data". I<iManuscript in preparation>.

=head1 AUTHOR

Written by Manuel Rueda, PhD. Info about CNAG can be found at L<https://www.cnag.crg.eu>.

=head1 METHODS

=head2 COMMON ERRORS AND SOLUTIONS

 * Error message: Foo
   Solution: Bar

 * Error message: Foo
   Solution: Bar

=head1 COPYRIGHT

This PERL file is copyrighted. See the LICENSE file included in this distribution.

=cut
