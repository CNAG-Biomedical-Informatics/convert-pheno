package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature               qw(say);
use FindBin               qw($Bin);
use File::Spec::Functions qw(catdir catfile);
use Data::Dumper;
use DBI;
use JSON::XS;
use Path::Tiny;
use File::Basename;
use Text::CSV_XS;
use Scalar::Util qw(looks_like_number);

=head1 NAME
  
=head1 SYNOPSIS
  
=head1 DESCRIPTION

=head1 AUTHOR

=head1 METHODS

=cut

use constant DEVEL_MODE => 0;
use vars qw{
  $VERSION
  @ISA
  @EXPORT
};

@ISA    = qw( Exporter );
@EXPORT = qw( &write_json );

sub new {

    my ( $class, $self ) = @_;
    bless $self, $class;
    return $self;
}

############
############
#  PXF2BFF #
############
############

sub pxf2bff {

    my $self = shift;
    my $data = read_json( $self->{in_file} );

    # Get cursors for 1D terms
    my $interpretation = $data->{interpretation};
    my $phenopacket    = $data->{phenopacket};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # NB1: In general, we'll only load terms that exist
    # NB2: In PXF some terms are = []
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

    $individual->{sex} =
      map_db( $phenopacket->{subject}{sex}, $self->{print_hidden_labels} )
      if exists $phenopacket->{subject}{sex};

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
    die "Under development";
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
    my $rcd = load_redcap_dictionary( $self->{'redcap_dictionary'} );

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # Data structure (hashref) for all individuals
    my $individuals;

    for my $participant (@$data) {

        print Dumper $participant if $self->{debug};

        # Data structure (hashref) for each individual
        my $individual;

        # ========
        # diseases
        # ========

        $individual->{diseases} = [];
        my %condition = ( 'Inflamatory Bowel Disease' => 'ICD10:K51.90' );
        for my $condition ( keys %condition ) {
            my $disease;
            $disease->{diseaseCode} = {
                id    => $condition{$condition},
                label => $condition
            };
            push @{ $individual->{diseases} }, $disease;
        }

        # =========
        # ethnicity
        # =========

        #print Dumper $participant and die;
        $individual->{ethnicity} = map_ethnicity(
            $rcd->{ethnicity}{_labels}{ $participant->{ethnicity} } )
          if ( exists $participant->{ethnicity}
            && $participant->{ethnicity} ne '' );    # Note that the value can be zero

        # =========
        # exposures
        # =========

        $individual->{exposures} = [];
        for my $agent (qw(alcohol)) {
            my $exposure;

            #$exposure->{ageAtExposure} = undef;
            #$exposure->{date}          = '2010-07-10';
            #$exposure->{duration}      = 'P32Y6M1D';
            $exposure->{exposureCode} = map_exposures($agent);
            $exposure->{quantity}{unit} = {
                "id"    => $participant->{alcohol},
                "label" => $rcd->{alcohol}{_labels}{ $participant->{alcohol} }
            };
            $exposure->{quantity}{value} = undef;
            push @{ $individual->{exposures} }, $exposure;
        }

        # ================
        # geographicOrigin
        # ================

        #$invididual->{geographicOrigin} = undef;

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
        for my $procedure ( qw(endoscopy_performed intestinal_surgery),
            keys %surgery )
        {
            if ( $participant->{$procedure} ) {
                my $intervention;
                $intervention->{ageAtProcedure} = undef;
                $intervention->{bodySite} =
                  { id => 'NCIT:C12736', label => 'intestine' };
                $intervention->{dateOfProcedure} = undef;
                $intervention->{procedureCode} =
                  map_db( $surgery{$procedure}, $self->{print_hidden_labels} )
                  if $surgery{$procedure};
                push @{ $individual->{interventionsOrProcedures} },
                  $intervention;
            }
        }

        # =============
        # karyotypicSex
        # =============

        # ========
        # measures
        # ========

        # =========
        # pedigrees
        # =========

        # ==================
        # phenotypicFeatures
        # ==================

        $individual->{phenotypicFeatures} = [];
        my @phenotypicFeatures = qw ( a b c);
        for my $disease (@phenotypicFeatures) {
            my $phenotypicFeature;
            $phenotypicFeature->{evidence} = undef;    # P32Y6M1D
            $phenotypicFeature->{excluded} =
              { Quantity => { unit => { id => '', label => '' }, value => '' }
              };
            $phenotypicFeature->{featureType} = [];
            $phenotypicFeature->{modifiers}   = { id => '', label => '' };
            $phenotypicFeature->{notes}       = { id => '', label => '' };
            $phenotypicFeature->{onset}       = { id => '', label => '' };
            $phenotypicFeature->{resolution}  = { id => '', label => '' };
            $phenotypicFeature->{severity}    = { id => '', label => '' };

            # Add to array
            push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature;
        }

        # ===
        # sex
        # ===

        $individual->{sex} =
          map_db( $rcd->{sex}{_labels}{ $participant->{sex} },
            $self->{print_hidden_labels} )
          if ( exists $participant->{sex} && $participant->{sex} );

        # ==========
        # treatments
        # ==========

        $individual->{treatments} = [];
        map_db( $rcd->{sex}{_labels}{ $participant->{sex} },
            $self->{print_hidden_labels} );
        my @drugs = qw (budesonide prednisolona asa);
        for my $drug (@drugs) {
            my $treatment;
            $treatment->{ageAtOnset} = undef;    # P32Y6M1D
            $treatment->{cumulativeDose} =
              { Quantity => { unit => { id => '', label => '' }, value => '' }
              };
            $treatment->{doseIntervals}         = [];
            $treatment->{routeOfAdministration} = { id => '', label => '' };
            $treatment->{treatmentCode}         = { id => '', label => '' };
            push @{ $individual->{treatments} }, $treatment;
        }
        push @{$individuals}, $individual;
    }

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individuals;
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

    my ( $file, $json_array ) = @_;
    my $json = JSON::XS->new->utf8->canonical->pretty->encode($json_array);
    path($file)->spew_utf8($json);
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

    my ( $str, $print_hidden_labels ) = @_;
    my $ontology = 'ncit';
    my ( $id, $label ) = get_query_SQLite( $str, $ontology );

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

#######################
#######################
#  SUBROUTINES FOR DB #
#######################
#######################

sub get_query_SQLite {

    my ( $query, $ontology ) = @_;
    my $db     = uc($ontology) . '_table';
    my $dbfile = catfile( $Bin, '../db', "$ontology.db" );
    my $field  = 'exact';
    my $user   = '';
    my $passwd = '';
    my $dsn    = "dbi:SQLite:dbname=$dbfile";
    my $dbh    = DBI->connect(
        $dsn, $user, $passwd,
        {
            PrintError       => 0,
            RaiseError       => 1,
            AutoCommit       => 1,
            FetchHashKeyName => 'NAME_lc',
        }
    );

    my %query = (
        partial =>
qq(SELECT * FROM $db WHERE preferred_label LIKE ? || '%' COLLATE NOCASE),

        #partial => qq(SELECT * FROM $db WHERE instr("preferred_label", ? COLLATE NOCASE) > 1),
        exact => qq(SELECT * FROM $db WHERE preferred_label = ? COLLATE NOCASE)

          #       rs       => 'select * FROM ExAC WHERE rs =  ? COLLATE NOCASE',
          #unknown => "select * from $db like ?"
    );

    my $sth = $dbh->prepare(<<SQL);
$query{$field}
SQL

    # Excute query
    $sth->execute($query);

    my $code            = 'NCIT:NA';
    my $preferred_label = 'NA';
    while ( my $row = $sth->fetchrow_arrayref ) {

        #print Dumper $row;
        $code            = 'NCIT:' . $row->[1];
        $preferred_label = $row->[0];
        last if $field eq 'exact'    # Note that sometime we get more than one
    }
    $sth->finish();
    $dbh->disconnect();

    return ( $code, $preferred_label );
}

1;
