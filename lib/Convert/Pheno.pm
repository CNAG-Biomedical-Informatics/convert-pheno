package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature               qw(say);
use FindBin               qw($Bin);
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use DBI;
use YAML::XS qw(LoadFile DumpFile);
use JSON::XS;
use Path::Tiny;
use File::Basename;
use Text::CSV_XS;
use Scalar::Util qw(looks_like_number);
use Sys::Hostname;
use Cwd         qw(cwd abs_path);
use POSIX       qw(strftime);
use Time::HiRes qw/gettimeofday/;

use constant DEVEL_MODE => 0;
use vars qw{
  $VERSION
  @ISA
  @EXPORT
};

@ISA     = qw( Exporter );
@EXPORT  = qw( $VERSION &write_json &write_yaml );
$VERSION = '0.0.0b';

sub new {

    my ( $class, $self ) = @_;
    bless $self, $class;
    return $self;
}

# NB: In general, we'll only display terms that exist and have content

# Global variables:

my @sqlites = qw(ncit icd10);

############
############
#  PXF2BFF #
############
############

sub pxf2bff {

    # <array_dispatcher> will deal with JSON arrays
    return array_dispatcher(shift);
}

sub do_pxf2bff {

    my ( $self, $data ) = @_;
    my $dbh = $self->{dbh};

    # Get cursors for 1D terms
    my $interpretation = $data->{interpretation};
    my $phenopacket    = $data->{phenopacket};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # NB: In PXF some terms are = []
    my $individual;

    # ========
    # diseases
    # ========

    $individual->{diseases} =
      [ map { $_ = { "diseaseCode" => $_->{term} } }
          @{ $phenopacket->{diseases} } ]
      if exists $phenopacket->{diseases};

    # ==
    # id
    # ==

    $individual->{id} = $phenopacket->{subject}{id}
      if exists $phenopacket->{subject}{id};

    # ====
    # info
    # ====

    # **** $data->{phenopacket} ****
    $individual->{info}{phenopacket}{dateOfBirth} =
      $phenopacket->{subject}{dateOfBirth};
    for my $term (qw (dateOfBirth genes meta_data variants)) {
        $individual->{info}{phenopacket}{$term} = $phenopacket->{$term}
          if exists $phenopacket->{$term};
    }

    # **** $data->{interpretation} ****
    $individual->{info}{interpretation}{phenopacket}{meta_data} =
      $interpretation->{phenopacket}{meta_data};

    # <diseases> and <phenotypicFeatures> are identical to those of $data->{phenopacket}{diseases,phenotypicFeatures}
    for my $term (
        qw (diagnosis diseases resolutionStatus phenotypicFeatures genes variants)
      )
    {
        $individual->{info}{interpretation}{$term} = $interpretation->{$term}
          if exists $interpretation->{$term};
    }

    # ==================
    # phenotypicFeatures
    # ==================

    $individual->{phenotypicFeatures} = [
        map {
            $_ = {
                "excluded" => (
                    exists $_->{negated} ? JSON::XS::true : JSON::XS::false
                ),
                "featureType" => $_->{type}
            }
        } @{ $phenopacket->{phenotypicFeatures} }
      ]
      if exists $phenopacket->{phenotypicFeatures};

    # ===
    # sex
    # ===

    $individual->{sex} = map_db(
        {
            label       => $phenopacket->{subject}{sex},
            ontology    => 'ncit',
            labels_true => $self->{print_hidden_labels},
            dbh         => $dbh->{ncit}
        }
    ) if exists $phenopacket->{subject}{sex};

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    # print Dumper $individual;
    return $individual;
}

############
############
#  BFF2PXF #
############
############

sub bff2pxf {

    # <array_dispatcher> will deal with JSON arrays
    return array_dispatcher(shift);
}

sub do_bff2pxf {

    my ( $self, $data ) = @_;

    # Setting a few variables
    my $user = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
    chomp( my $ncpuhost = qx{/usr/bin/nproc} ) // 1;
    $ncpuhost = 0 + $ncpuhost;    # coercing it to be a number

    my $info = {
        user            => $user,
        ncpuhost        => $ncpuhost,
        cwd             => cwd,
        hostname        => hostname,
        'Convert-Pheno' => $VERSION
    };
    #####################
    # Under development #
    #####################

    # Insert {"phenopacket": { "meta_data"}} in both ARRAY (missing: and single document)
    my $resources = [
        {
            id   => "ICD10",
            name =>
"International Statistical Classification of Diseases and Related Health Problems 10th Revision",
            url             => "https://icd.who.int/browse10/2019/en#",
            version         => "2019",
            namespacePrefix => "ICD-10"

              #iriPrefix => "http://purl.obolibrary.org/obo/HP_"
        },
        {
            id              => "NCIT",
            name            => "NCI Thesaurus",
            url             => " http://purl.obolibrary.org/obo/ncit.owl",
            version         => "22.03d",
            namespacePrefix => "NCIT"
        }
    ];
    my $meta_data =
      { created => iso8601(), resources => $resources, _info => $info };

    $data->{meta_data}      = $meta_data;
    $data->{interpretation} = { phenopacket => {} };
    my $out = { phenopacket => $data };

    return $out;
}

###############
###############
#  REDCAP2BFF #
###############
###############

sub redcap2bff {

    my $self = shift;

    # Read data from REDCap export
    my $data = read_redcap_export( $self->{in_file} );

    # Load (or read) REDCap CSV dictionary
    my $data_rcd = load_redcap_dictionary( $self->{redcap_dictionary} );

    print Dumper $data_rcd if ( $self->{debug} && $self->{debug} > 1 );

    # array_dispatcher will deal with JSON arrays
    $self->{data}     = $data;
    $self->{data_rcd} = $data_rcd;
    return array_dispatcher($self);
}

sub do_redcap2bff {

    my ( $self, $data ) = @_;
    my $rcd = $self->{data_rcd};
    my $dbh = $self->{dbh};

    ##############################
    # <Variable> names in REDCap #
    ##############################
    #
    # REDCap does not enforce any particular "Variable" name.
    # Extracted from https://www.ctsi.ufl.edu/wordpress/files/2019/02/Project-Creation-User-Guide.pdf
    # ---
    # "Variable Names: Variable names are critical in the data analysis process. If you export your data to a
    # statistical software program, the variable names are what you or your statistician will use to conduct
    # the analysis"
    #
    # "We always recommend reviewing your variable names with a statistician or whoever will be
    # analyzing your data. This is especially important if this is the first time you are building a
    # database"
    #---
    # If "Variable" names are not consensuated, then we need to do the mapping manually "a posteriori".
    # This is what we are attempting here:

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    my $participant = $data;

    print Dumper $rcd if $self->{debug};

    # Data structure (hashref) for each individual
    my $individual;

    # ========
    # diseases
    # ========

    $individual->{diseases} = [];
    my %disease = ( 'Inflamatory Bowel Disease' => 'ICD10:K51.90' );

    #my @diseases = ('Unspecified asthma, uncomplicated', 'Inflamatory Bowel Disease', "Crohn's disease, unspecified, without complications");
    my @diseases = ('Inflamatory Bowel Disease');

    #( 'Unspecified asthma, uncomplicated', 'Inflamatory Bowel Disease' );
    for my $element (@diseases) {
        my $disease;
        if ( $element ne 'Inflamatory Bowel Disease' ) {
            $disease->{diseaseCode} = map_db(
                {
                    label       => $element,
                    ontology    => 'icd10',                        # ICD-10 ontology (term must be precise)
                    labels_true => $self->{print_hidden_labels},
                    dbh         => $dbh->{icd10}

                }
            );
        }
        else {
            $disease->{diseaseCode} = {
                id    => $disease{$element},
                label => $element
            };
        }
        push @{ $individual->{diseases} }, $disease;
    }

    # =========
    # ethnicity
    # =========

    #print Dumper $participant and die;
    $individual->{ethnicity} =
      map_ethnicity( $rcd->{ethnicity}{_labels}{ $participant->{ethnicity} } )
      if ( exists $participant->{ethnicity}
        && $participant->{ethnicity} ne '' );    # Note that the value can be zero

    # =========
    # exposures
    # =========

    $individual->{exposures} = [];
    for my $element (qw(alcohol)) {
        my $exposure;

        $exposure->{ageAtExposure}  = undef;
        $exposure->{date}           = undef;                     #'2010-07-10';
        $exposure->{duration}       = undef;                     # 'P32Y6M1D';
        $exposure->{exposureCode}   = map_exposures($element);
        $exposure->{quantity}{unit} = {
            id    => $participant->{alcohol},
            label => $rcd->{alcohol}{_labels}{ $participant->{alcohol} }
        };
        $exposure->{quantity}{value} = undef;
        push @{ $individual->{exposures} }, $exposure;
    }

    # ================
    # geographicOrigin
    # ================

    $individual->{geographicOrigin} = undef;

    # ==
    # id
    # ==

    #$individual->{id} = $participant->{first_name}
    #  if ( exists $participant->{first_name}
    #    && $participant->{first_name} );
    $individual->{id} = $participant->{ids_complete}
      if $participant->{ids_complete};

    # ====
    # info
    # ====

    for (qw(study_id redcap_event_name dob)) {
        $individual->{info}{$_} = $participant->{$_}
          if exists $participant->{$_};
    }

    # =========================
    # interventionsOrProcedures
    # =========================

    $individual->{interventionsOrProcedures} = [];

    #my @surgeries = map { $_ = 'surgery_details___' . $_ } ( 1 .. 8, 99 );
    my %surgery = ();
    for ( 1 .. 8, 99 ) {
        $surgery{ 'surgery_details___' . $_ } =
          $rcd->{surgery_details}{_labels}{$_};
    }
    for
      my $element ( qw(endoscopy_performed intestinal_surgery), keys %surgery )
    {
        if ( $participant->{$element} ) {
            my $intervention;
            $intervention->{ageAtProcedure} = undef;
            $intervention->{bodySite} =
              { id => 'NCIT:C12736', label => 'intestine' };
            $intervention->{dateOfProcedure} = undef;
            $intervention->{procedureCode}   = map_db(
                {
                    label       => $surgery{$element},
                    ontology    => 'ncit',
                    labels_true => $self->{print_hidden_labels},
                    dbh         => $dbh->{ncit}
                }
            ) if $surgery{$element};
            push @{ $individual->{interventionsOrProcedures} }, $intervention;
        }
    }

    # =============
    # karyotypicSex
    # =============

    # ========
    # measures
    # ========

    $individual->{measures} = [];
    my @measures = (qw ( a b c));
    for my $element (@measures) {
        my $measure;
        $measure->{assayCode} = undef;    # P32Y6M1D
        $measure->{date} =
          { Quantity => { unit => { id => '', label => '' }, value => '' } };
        $measure->{measurementValue}  = [];
        $measure->{notes}             = { id => '', label => '' };
        $measure->{observationMoment} = { id => '', label => '' };
        $measure->{procedure}         = { id => '', label => '' };

        # Add to array
        #push @{ $individual->{measures} }, $measure; # SWITCHED OFF on 072622

    }

    # =========
    # pedigrees
    # =========

    $individual->{pedigrees} = [];

    # disease, id, members, numSubjects
    my @pedigrees = (qw ( a b c));
    for my $element (@pedigrees) {
        my $pedigree;
        $pedigree->{disease}     = {};      # P32Y6M1D
        $pedigree->{id}          = undef;
        $pedigree->{members}     = [];
        $pedigree->{numSubjects} = 0;

        # Add to array
        #push @{ $individual->{pedigrees} }, $pedigree; # SWITCHED OFF on 072622

    }

    # ==================
    # phenotypicFeatures
    # ==================

    $individual->{phenotypicFeatures} = [];
    my @phenotypicFeatures = qw ( a b c);
    for my $element (@phenotypicFeatures) {
        my $phenotypicFeature;
        $phenotypicFeature->{evidence} = undef;    # P32Y6M1D
        $phenotypicFeature->{excluded} =
          { Quantity => { unit => { id => '', label => '' }, value => '' } };
        $phenotypicFeature->{featureType} = [];
        $phenotypicFeature->{modifiers}   = { id => '', label => '' };
        $phenotypicFeature->{notes}       = { id => '', label => '' };
        $phenotypicFeature->{onset}       = { id => '', label => '' };
        $phenotypicFeature->{resolution}  = { id => '', label => '' };
        $phenotypicFeature->{severity}    = { id => '', label => '' };

        # Add to array
        #push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature; # SWITCHED OFF on 072622
    }

    # ===
    # sex
    # ===

    $individual->{sex} = map_db(
        {
            label       => $rcd->{sex}{_labels}{ $participant->{sex} },
            ontology    => 'ncit',
            labels_true => $self->{print_hidden_labels},
            dbh         => $dbh->{ncit}

        }
    ) if ( exists $participant->{sex} && $participant->{sex} );

    # ==========
    # treatments
    # ==========

    $individual->{treatments} = [];
    my @drugs = qw (budesonide_oral budesonide_rectal prednisolone);    #prednisolone asa);

    #
    #        '_labels' => {
    #                                                       '1' => 'never treated',
    #                                                       '2' => 'former treatment',
    #                                                       '3' => 'current treatment'
    #                                                     }

    for my $element (@drugs) {
        my $treatment;

        my $tmp_var = $element . '_status';
        $treatment->{info} = {
            drug   => $element,
            status => $rcd->{$tmp_var}{_labels}{ $participant->{$tmp_var} }
        };    # ***** INTERNAL FIELD
        $treatment->{ageAtOnset} = undef;    # P32Y6M1D
        $treatment->{cumulativeDose} =
          { Quantity => { unit => { id => '', label => '' }, value => '' } };
        $treatment->{doseIntervals}         = [];
        $treatment->{routeOfAdministration} = { id => '', label => '' };
        $treatment->{treatmentCode}         = { id => '', label => '' };
        push @{ $individual->{treatments} }, $treatment;
    }

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individual;
}

###############
###############
#  REDCAP2PXF #
###############
###############

sub redcap2pxf {

    my $self = shift;

    # First iteration: redcap2bff
    my $bff = redcap2bff($self);    # array

    # Second iteration: bff2pxf
    my $pxf;
    for ( @{$bff} ) {
        push @{$pxf}, do_bff2pxf( undef, $_ );
    }

    return $pxf;
}

######################
######################
# READ REDCAP EXPORT #
######################
######################

sub read_redcap_export {

    my $in_file = shift;

    # Define split record separator
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    open my $fh, '<:encoding(utf8)', $in_file;

    # We'll read the header to assess separators in <txt> files
    chomp( my $tmp_header = <$fh> );

    # Defining separator
    my $separator = $ext eq '.csv'
      ? ';'    # Note we don't use comma but semicolon
      : $ext eq '.tsv' ? "\t"
      :                  ' ';

    # Defining variables
    my $data = [];                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Loading header fields into $header
    $csv->parse($tmp_header);
    my $header = [ $csv->fields() ];

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh) ) {

        # We store the data as an AoH $data
        my $tmp_hash;
        for my $i ( 0 .. $#{$header} ) {
            $tmp_hash->{ $header->[$i] } = $row->[$i];
        }
        push @$data, $tmp_hash;
    }

    close $fh;

    #########################################
    #     END READING CSV|TSV|TXT FILE      #
    #########################################

    return $data;
}

##########################
##########################
# LOAD REDCAP DICTIONARY #
##########################
##########################

sub load_redcap_dictionary {

    my $in_file = shift;

    # Define split record separator
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    open my $fh, '<:encoding(utf8)', $in_file;

    # We'll read the header to assess separators in <txt> files
    chomp( my $tmp_header = <$fh> );

    # Defining separator
    my $separator =
        $ext eq '.csv' ? ';'
      : $ext eq '.tsv' ? "\t"
      :                  ' ';

    # Defining variables
    my $data = {};                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Loading header fields into $header
    $csv->parse($tmp_header);
    my $header = [ $csv->fields() ];

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh) ) {

        # We store the data as an AoH $data
        my $tmp_hash;

        for my $i ( 0 .. $#{$header} ) {

            # We keep key>/value as they are
            $tmp_hash->{ $header->[$i] } = $row->[$i];

            # For the key having lavels, we create a new ad hoc key '_labels'
            # 'Choices, Calculations, OR Slider Labels' => '1, Female|2, Male|3, Other|4, not available',
            if ( $header->[$i] eq 'Choices, Calculations, OR Slider Labels' ) {
                my @tmp =
                  map { s/^\s//; s/\s+$//; $_; } ( split /\||,/, $row->[$i] );
                $tmp_hash->{_labels} = {@tmp} if @tmp % 2 == 0;
            }
        }

        # Now we create the 1D of the hash with 'Variable / Field Name'
        my $key = $tmp_hash->{'Variable / Field Name'};

        # And we nest the hash inside
        $data->{$key} = $tmp_hash;
    }

    close $fh;

    #######################################
    #     END READING CSV|TSV|TXT FILE    #
    #######################################

    return $data;
}

########################
########################
#  SUBROUTINES FOR I/O #
########################
########################

sub read_json {

    my $json_file = shift;
    my $str       = path($json_file)->slurp_utf8;
    my $json      = decode_json($str);              # Decode to Perl data structure
    return $json;
}

sub write_json {

    my $arg        = shift;
    my $file       = $arg->{filename};
    my $json_array = $arg->{data};
    my $json = JSON::XS->new->utf8->canonical->pretty->encode($json_array);
    path($file)->spew_utf8($json);
    return 1;
}

sub write_yaml {

    my $arg        = shift;
    my $file       = $arg->{filename};
    my $json_array = $arg->{data};
    DumpFile( $file, $json_array );
    return 1;
}

############################
############################
#  SUBROUTINES FOR MAPPING #
############################
############################

sub map_ethnicity {

    my $str       = shift;
    my %ethnicity = ( map { $_ => 'NCIT:C41261' } ( 'caucasian', 'white' ) );

    # 1, Caucasian | 2, Hispanic | 3, Asian | 4, African/African-American | 5, Indigenous American | 6, Mixed | 9, Other";
    return { id => $ethnicity{ lc($str) }, label => $str };
}

sub map_db {

    my $arg                 = shift;
    my $str                 = $arg->{label};
    my $ontology            = $arg->{ontology};
    my $print_hidden_labels = $arg->{labels_true};
    my $dbh                 = $arg->{dbh};

    # Perform query
    my ( $id, $label ) = get_query_SQLite( $dbh, $str, $ontology );

    # id and label come from <db> _label is the original string (can change on partial matches)
    return $print_hidden_labels
      ? { id => $id, label => $label, _label => $str }
      : { id => $id, label => $label };
}

sub map_exposures {

    my $str      = shift;
    my $exposure = {
        cigarretes => {
            cigarettes_days                => 'NCIT: C127064',
            'Years Have Smoked Cigarettes' => 'NCIT:C127063',
            packyears                      => 'NCIT: C73993'
        },
        alcohol => { id => 'NCIT:C16273', label => 'alcohol consumption' }
    };
    return $exposure->{$str};
}

sub iso8601 {

    my ( $s, $f ) = split( /\./, gettimeofday );
    return strftime( '%Y-%m-%dT%H:%M:%S.' . $f . '%z', localtime($s) );
}

#######################
#######################
#  SUBROUTINES FOR DB #
#######################
#######################

sub open_connection_SQLite {

    # Opening the DB once (instead that on each call) improves speed ~15%
    my $dbh;
    $dbh->{$_} = open_db_SQLite($_) for (@sqlites);    # global
    return $dbh;
}

sub close_connection_SQLite {

    my $dbh = shift;
    close_db_SQLite( $dbh->{$_} ) for (@sqlites);      #global
    return 1;
}

sub open_db_SQLite {

    my $ontology = shift;
    my $dbfile   = catfile( $Bin, '../db', "$ontology.db" );
    my $user     = '';
    my $passwd   = '';
    my $dsn      = "dbi:SQLite:dbname=$dbfile";
    my $dbh      = DBI->connect(
        $dsn, $user, $passwd,
        {
            PrintError       => 0,
            RaiseError       => 1,
            AutoCommit       => 1,
            FetchHashKeyName => 'NAME_lc',
        }
    );

    return $dbh;
}

sub close_db_SQLite {

    my $dbh = shift;
    $dbh->disconnect();
    return 1;
}

sub get_query_SQLite {

    my ( $dbh, $query, $ontology ) = @_;
    my $field = 'exact_match';
    my $db    = uc($ontology) . '_table';
    my %query = (
        contains =>
          qq(SELECT * FROM $db WHERE label LIKE '%' || ? || '%' COLLATE NOCASE),
        contains_word =>
qq(SELECT * FROM $db WHERE label LIKE '% ' || ? || ' %' COLLATE NOCASE),
        exact_match => qq(SELECT * FROM $db WHERE label = ? COLLATE NOCASE),
        begins_with =>
          qq(SELECT * FROM $db WHERE label LIKE ? || '%' COLLATE NOCASE)
    );

    my $sth = $dbh->prepare(<<SQL);
$query{$field}
SQL

    # Excute query
    $sth->execute($query);

    # Parse query
    $ontology = uc($ontology);
    my $id    = $ontology . ':NA';
    my $label = 'NA';
    while ( my $row = $sth->fetchrow_arrayref ) {
        $id    = $ontology . ':' . $row->[1];
        $label = $row->[0];
        last if $field eq 'exact_match';    # Note that sometimes we get more than one
    }
    $sth->finish();

    return ( $id, $label );
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
      ( $self->{in_textfile} && $self->{method} !~ m/^redcap2/ )
      ? read_json( $self->{in_file} )
      : $self->{data};

    # Define the methods to call
    my %func = (
        pxf2bff    => \&do_pxf2bff,
        bff2pxf    => \&do_bff2pxf,
        redcap2bff => \&do_redcap2bff
    );

    # Open connection to SQLlite databases ONCE
    my $dbh = open_connection_SQLite() unless $self->{method} eq 'bff2pxf';

    # Add $dbh HANDLE to $self
    $self->{dbh} = $dbh;

    # Proceed depending if we have an ARRAY or not
    my $out_data;
    if ( ref $in_data eq 'ARRAY' ) {
        say "$self->{method}: ARRAY" if $self->{debug};

        # Caution with the RAM (we store all in memory)
        for ( @{$in_data} ) {
            say "ARRAY ELEMENT" if $self->{debug};

            # We DELIBERATLEY separate array elements from $self
            push @{$out_data}, $func{ $self->{method} }->( $self, $_ );
        }
    }
    else {
        say "$self->{method}: NOT ARRAY" if $self->{debug};
        $out_data = $func{ $self->{method} }->( $self, $_ );
    }

    # Close connections ONCE
    close_connection_SQLite($dbh) unless $self->{method} eq 'bff2pxf';

    return $out_data;
}

1;

=head1 NAME

Convert::Pheno -  Interconvert phenotypic data between different CDM formats
  
=head1 SYNOPSIS

 use Convert::Pheno;

 # Create a new object
 
 my $convert = Convert::Pheno->new($input);
 
 # Apply a method 
 
 my $data = $convert->redcap2bff;

=head1 DESCRIPTION

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
