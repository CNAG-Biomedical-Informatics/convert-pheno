package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature qw(say);
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use Path::Tiny;
use File::Basename;
use File::ShareDir::ProjectDistDir;
use List::Util qw(any uniq);
use Carp qw(confess);
use XML::Fast;
use Moo;
use Types::Standard qw(Str Int Num Enum ArrayRef Undef);
use File::ShareDir::ProjectDistDir qw(dist_dir);

#use Devel::Size     qw(size total_size);
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
our @EXPORT =
  qw($VERSION io_yaml_or_json omop2bff_stream_processing share_dir);    # Symbols imported by default

#our @EXPORT_OK = qw(foo bar);       # Symbols imported by request

use constant DEVEL_MODE => 0;

# Personalize warn and die functions
$SIG{__WARN__} = sub { warn "Warn: ", @_ };
$SIG{__DIE__}  = sub { die "Error: ", @_ };

# Global variables:
our $VERSION   = '0.17';
our $share_dir = dist_dir('Convert-Pheno');

############################################
# Start declaring attributes for the class #
############################################

# Complex defaults here
has search => (

    default => 'exact',
    is      => 'ro',
    coerce  => sub { $_[0] // 'exact' },
    isa     => Enum [qw(exact mixed)]
);

has text_similarity_method => (

    #default => 'cosine',
    is     => 'ro',
    coerce => sub { $_[0] // 'cosine' },
    isa    => Enum [qw(cosine dice)]
);

has min_text_similarity_score => (

    #default => 0.8,
    is     => 'ro',
    coerce => sub { $_[0] // 0.8 },
    isa    => sub {
        die "Only values between 0 .. 1 supported!"
          unless ( $_[0] >= 0.0 && $_[0] <= 1.0 );
    }
);

has username => (

    #default => ( $ENV{LOGNAME} || $ENV{USER} || getpwuid($<) ) , # getpwuid not implemented in Windows
    default => $ENV{'LOGNAME'}
      || $ENV{'USER'}
      || $ENV{'USERNAME'}
      || 'dummy-user',
    is     => 'ro',
    coerce => sub {
        $_[0] // ( $ENV{'LOGNAME'}
              || $ENV{'USER'}
              || $ENV{'USERNAME'}
              || 'dummy-user' );
    },
    isa => Str
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

        # If tables are provided, process them; otherwise, use default essential tables
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
    my ( $data_redcap_dict, $data_mapping_file ) =
      read_redcap_dict_and_mapping_file(
        {
            redcap_dictionary    => $self->{redcap_dictionary},
            mapping_file         => $self->{mapping_file},
            self_validate_schema => $self->{self_validate_schema},
            schema_file          => $self->{schema_file}
        }
      );

    # Load data in $self
    $self->{data}              = $data;                 # Dynamically adding attributes (setter)
    $self->{data_redcap_dict}  = $data_redcap_dict;     # Dynamically adding attributes (setter)
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

    # File Size Considerations for Data Processing
    #
    # For SMALL TO MEDIUM FILES (< 1M rows):
    # Commonly, database downsizing for data sharing results in PostgreSQL dumps or CSVs being less than 1 million rows.
    # With adequate memory (4-16GB), we can efficiently load this data into RAM and effectively consolidate individual data points (e.g., MEASURES, DRUGS).
    #
    # For HUMONGOUS FILES (> 1M rows):
    # As we heavily use hashes, larger files necessitate alternative data loading strategies:
    #
    # * Option A: Parallel Processing (No code modification required)
    #   Users can split their data into smaller chunks or mini-instances, employing parallel processing tools (like GNU parallel, snakemake, HPC, etc.).
    #   Caveat: SQLite’s limitations with concurrent access by multiple threads.
    #
    # * Option B: Data Consolidation at Individual Object Level
    #   --no-stream
    #   Two approaches for this:
    #     a) Externalize the complete hash using DBM:Deep (although it's significantly slower).
    #     b) Initially dump data as CSV (either by the user or automatically), then sort it (using *nix or SQLite) by 'person_id'.
    #        This method doesn't substantially help with data consolidation since we still process one table at a time.
    #
    # * Option C: Line-by-Line File Parsing (One row of CSV/SQL per JSON object) <===== CURRENT IMPLEMENTATION
    #   --stream
    #   Note: BFF / PXF JSON files serve as intermediate stages. They group data by individual for easier inspection but are ultimately stored in Mongo DB.
    #   Similar to the genomicVariations issue in B2RI, multiple JSON objects (like MEASUREMENTS, DRUGS) can correspond to a single individual.
    #
    #   Potential Issues and Solutions:
    #     1. Mandatory <CONCEPT> Table:
    #        It can be extremely large, potentially consuming all available RAM (e.g., a 735 MB <CONCEPT.csv> with over 5.8 million lines).
    #        Solutions:
    #          a) Avoid loading the <CONCEPT> table entirely, using --ohdsi-db instead.
    #          b) Use a temporary SQLite instance for the <CONCEPT> table.
    #     2. Reading SQL Dumps Line-by-Line:
    #        For large SQL dumps (e.g., 20GB), should we convert them into CSV (also ~20GB)?
    #        Solutions:
    #          a) Yes, first export required tables to CSV and then proceed.
    #          b) No, read the PostgreSQL dump twice - first to load specified tables, then the rest.
    #     3. Streaming Mode Restrictions:
    #        In --stream mode, --sql2csv is not allowed to prevent excessive space usage and complexity.
    #
    # Further reading on handling large files: https://www.perlmonks.org/?node_id=1033692

    # Load variables
    my $data;
    my $filepath;
    my @filepaths;
    $self->{method_ori} =
      exists $self->{method_ori} ? $self->{method_ori} : 'omop2bff';    # setter
    $self->{prev_omop_tables} = [ @{ $self->{omop_tables} } ];          # setter - 1D clone

    # Check if data comes from variable or from file
    # Variable
    if ( exists $self->{data} ) {
        $self->{omop_cli} = 0;               # setter
        $data = $self->{data};
    }

    # File(s)
    else {

        # Read and load data from OMOP-CDM export
        $self->{omop_cli} = 1;               # setter

        # First we need to know if we have PostgreSQL dump or a bunch of csv
        # File extensions to check
        my @exts = map { $_, $_ . '.gz' } qw(.csv .tsv .sql);

        # Proceed
        # The idea here is that we'll load ONLY ESSENTIAL TABLES
        # regardless of wheter they are concepts or truly records.
        # Dictionaries (e.g. <CONCEPT>) will be parsed latter from $data

        for my $file ( @{ $self->{in_files} } ) {
            my ( $table_name, undef, $ext ) = fileparse( $file, @exts );
            if ( $ext =~ m/\.sql/i ) {

                #######################
                # Loading OMOP tables #
                #######################

                # --no-stream
                if ( !$self->{stream} ) {

                    # We read all tables in memory
                    $data = read_sqldump( { in => $file, self => $self } );

                    # Exporting to CSV if --sql2csv
                    sqldump2csv( $data, $self->{out_dir} ) if $self->{sql2csv};
                }

                # --stream
                else {

                    # We'll ONLY load @stream_ram_memory_tables
                    # in RAM and the other tables as $fh
                    $self->{omop_tables} = [@stream_ram_memory_tables];    # setter
                    $data = read_sqldump( { in => $file, self => $self } );
                }

                # We keep the filepath for later
                $filepath = $file;

                # Exit loop
                last;
            }
            else {

                # We'll load all OMOP tables that the user is providing as -iomop
                # as long as they have a match in @omop_essential_tables
                # NB: --omop-tables has no effect
                warn "<$table_name> is not a valid table in OMOP-CDM\n" and next

                  #unless (any { $_ eq $table_name } @{ $omop_main_table->{$omop_version} };
                  unless any { $_ eq $table_name } @omop_essential_tables;    # global

                # --no-stream
                if ( !$self->{stream} ) {

                    # We read all tables in memory
                    $data->{$table_name} =
                      read_csv( { in => $file, sep => $self->{sep} } );
                }

                # --stream
                else {
                    # We'll ONLY load @stream_ram_memory_tables
                    # in RAM and the other tables as $fh
                    if ( any { $_ eq $table_name } @stream_ram_memory_tables ) {
                        $data->{$table_name} =
                          read_csv( { in => $file, sep => $self->{sep} } );
                    }
                    else {
                        push @filepaths, $file;
                    }
                }
            }
        }
    }

    #print Dumper_concise($data) and die;
    #print Dumper_concise($self) and die;

    # Primarily with CSVs, it can happen that user does not provide <CONCEPT.csv>
    confess 'We could not find table <CONCEPT> from your input files'
      unless exists $data->{CONCEPT};

    # We create a dictionary for $data->{CONCEPT}
    $self->{data_ohdsi_dic} = transpose_ohdsi_dictionary( $data->{CONCEPT} );  # Dynamically adding attributes (setter)

    # We load the allowed concept_id for exposures as hashref (for --no--stream and --stream)
    $self->{exposures} = load_exposures( $self->{exposures_file} );            # Dynamically adding attributes (setter)

    # We transpose $self->{data}{VISIT_OCCURRENCE} if present
    if ( exists $data->{VISIT_OCCURRENCE} ) {
        $self->{visit_occurrence} =
          transpose_visit_occurrence( $data->{VISIT_OCCURRENCE} );             # Dynamically adding attributes (setter)
        delete $data->{VISIT_OCCURRENCE};
    }

    # Now we need to perform a tranformation of the data where 'person_id' is one row of data
    # NB: Transformation is due ONLY IN $omop_main_table FIELDS, the rest of the tables are not used
    # The transformation is performed in --no-stream mode
    $self->{data} =
      $self->{stream} ? $data : transpose_omop_data_structure($data);    # Dynamically adding attributes (setter)

    # Giving some memory back to the system
    $data = undef;

    # --stream
    if ( $self->{stream} ) {
        omop_stream_dispatcher(
            { self => $self, filepath => $filepath, filepaths => \@filepaths }
        );
    }

    # --no-stream
    else {
        # array_dispatcher will deal with JSON arrays
        return array_dispatcher($self);
    }
}

##############
##############
#  OMOP2PXF  #
##############
##############

sub omop2pxf {

    my $self = shift;

    # We have two possibilities:
    #
    # 1 - Module (Variables)
    # 2 - CLI (I/O files)

    # Variable
    if ( exists $self->{data} ) {

        # First iteration: omop2bff
        $self->{omop_cli} = 0;
        $self->{method}   = 'omop2bff';    # setter - we have to change the value of attr {method}
        my $bff = omop2bff($self);         # array

        # Preparing for second iteration: bff2pxf
        # NB: This 2nd round may take a while if #inviduals > 1000!!!
        $self->{method}      = 'bff2pxf';    # setter
        $self->{data}        = $bff;         # setter
        $self->{in_textfile} = 0;            # setter

        # Run second iteration
        return array_dispatcher($self);

        # CLI
    }
    else {
        # $self->{method} will be always 'omop2bff'
        # $self->{method_ori} will tell us the original one
        $self->{method_ori} = 'omop2pxf';    # setter
        $self->{method}     = 'omop2bff';    # setter
        $self->{omop_cli}   = 1;             # setter

        # Run 1st and 2nd iteration
        return omop2bff($self);
    }
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

    my ( $data_redcap_dict, $data_mapping_file ) =
      read_redcap_dict_and_mapping_file(
        {
            redcap_dictionary    => $self->{redcap_dictionary},
            mapping_file         => $self->{mapping_file},
            self_validate_schema => $self->{self_validate_schema},
            schema_file          => $self->{schema_file}
        }
      );

    # Load data in $self
    $self->{data}              = $data;                 # Dynamically adding attributes (setter)
    $self->{data_redcap_dict}  = $data_redcap_dict;     # Dynamically adding attributes (setter)
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

    # Open filehandle if omop2bff
    my $fh_out;
    if ( $self->{method} eq 'omop2bff' && $self->{omop_cli} ) {
        $fh_out = open_filehandle( $self->{out_file}, 'a' );
        say $fh_out "[";
    }

    # Proceed depending if we have an ARRAY or not
    # NB: Caution with RAM (we store all in memory except for omop2bff)
    my $out_data;
    if ( ref $in_data eq ref [] ) {

        # Print if we have ARRAY
        say "$self->{method}: ARRAY" if $self->{debug};

        # Initialize needed variables
        my $count    = 0;
        my $total    = 0;
        my $elements = scalar @{$in_data};

        # Start looping
        # In $self->{data} we have all participants data, but,
        # WE DELIBERATELY SEPARATE ARRAY ELEMENTS FROM $self->{data}

        for ( @{$in_data} ) {
            $count++;

            # Print imfo
            say "[$count] ARRAY ELEMENT from $elements" if $self->{debug};

            # NB: If we get "null" participants the validator will complain
            # about not having "id" or any other required property
            my $method_result = $func{ $self->{method} }->( $self, $_ );    # Method

            # Only proceeding if we got value from method
            if ($method_result) {
                $total++;
                say " * [$count] ARRAY ELEMENT is defined" if $self->{debug};

                # For omop2bff and omop2pxf we serialize by individual
                if ( exists $self->{omop_cli} && $self->{omop_cli} ) {
                    my $out = omop_dispatcher( $self, $method_result );
                    print $fh_out $$out;
                    print $fh_out ",\n"
                      unless ( $total == $elements
                        || $total == $self->{max_lines_sql} );
                }

                # For the other we have array_ref $out_data and serialize at once
                else {
                    push @{$out_data}, $method_result;

                    #say total_size($out_data);
                }
            }
        }

        say "==============\nIndividuals total:     $total\n"
          if ( $self->{verbose} && $self->{method} eq 'omop2bff' );
    }

    # NOT ARRAY
    else {
        say "$self->{method}: NOT ARRAY" if $self->{debug};
        $out_data = $func{ $self->{method} }->( $self, $in_data );    # Method
    }

    # Close connections ONCE
    close_connections_SQLite($self) unless $self->{method} eq 'bff2pxf';

    # Close filehandle if omop2bff (w/ premature return)
    if ( exists $self->{omop_cli} && $self->{omop_cli} ) {
        say $fh_out "\n]";
        close $fh_out;
        return 1;
    }

    # Return data
    return $out_data;
}

sub omop_dispatcher {

    my ( $self, $method_result ) = @_;

    # For omop2bff and omop2pxf we serialize by individual
    my $out;

    # omop2bff encode directly
    if ( $self->{method_ori} ne 'omop2pxf' ) {
        $out = JSON::XS->new->utf8->canonical->pretty->encode($method_result);
    }

    # omop2pxf convert to PXF
    else {
        my $pxf = do_bff2pxf( $self, $method_result );
        $out = JSON::XS->new->utf8->canonical->pretty->encode($pxf);
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

    # Open a SQLite database connection if required
    open_connections_SQLite($self) if $self->{method} ne 'bff2pxf';

    # Transform Array of Hashes (AoH) to Hash of Hashes (HoH) for faster computation
    my $person = transform_aoh_to_hoh($self);

    # Process files based on the input type (CSV or PostgreSQL dump)
    return @$filepaths
      ? process_csv_files( $self, $filepaths, $person )
      : process_sqldump( $self, $filepath, $omop_tables, $person );
}

sub transform_aoh_to_hoh {

    my $self   = shift;
    my $person = { map { $_->{person_id} => $_ } @{ $self->{data}{PERSON} } };
    delete $self->{data}{PERSON};    # Free up memory
    return $person;
}

sub process_csv_files {

    my ( $self, $filepaths, $person ) = @_;
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

sub process_sqldump {

    my ( $self, $filepath, $omop_tables, $person ) = @_;
    for my $table (@$omop_tables) {
        next if any { $_ eq $table } @stream_ram_memory_tables;
        say "Processing table ... <$table>" if $self->{verbose};
        $self->{omop_tables} = [$table];
        read_sqldump_stream(
            { in => $filepath, self => $self, person => $person } );
    }
    return 1;
}

sub omop2bff_stream_processing {

    my ( $self, $data ) = @_;

    # We have this subroutine here because the class was initiated in Pheno.pm
    return do_omop2bff( $self, $data );    # Method
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

Rueda, M. et al. "Convert-Pheno: A software toolkit for the interconversion of standard data models for phenotypic data", (2023), I<Journal of Biomedical Informatics>.

=head1 AUTHOR

Written by Manuel Rueda, PhD. Info about CNAG can be found at L<https://www.cnag.eu>.

=head1 METHODS

See L<https://cnag-biomedical-informatics.github.io/convert-pheno/use-as-a-module>.

=head1 COPYRIGHT

This PERL file is copyrighted. See the LICENSE file included in this distribution.

=cut
