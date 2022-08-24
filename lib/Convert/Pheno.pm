package Convert::Pheno;

use strict;
use warnings;
use autodie;
use utf8;
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
binmode STDOUT, ':encoding(utf-8)';

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

# Global variables:
my @sqlites = qw(ncit icd10);
my $seen    = {};

# NB1: In general, we'll only display terms that exist and have content
# NB2: We are using pure OO Perl but we might switch to Moose if things get trickier...

#############
#############
#  PXF2BFF  #
#############
#############

sub pxf2bff {

    # <array_dispatcher> will deal with JSON arrays
    return array_dispatcher(shift);
}

sub do_pxf2bff {

    my ( $self, $data ) = @_;
    my $sth = $self->{sth};

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

    $individual->{sex} = map_ontology(
        {
            label       => $phenopacket->{subject}{sex},
            ontology    => 'ncit',
            labels_true => $self->{print_hidden_labels},
            sth         => $sth->{ncit}
        }
    ) if exists $phenopacket->{subject}{sex};

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    # print Dumper $individual;
    return $individual;
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
      { created => iso8601_time(), resources => $resources, _info => $info };

    $data->{meta_data}      = $meta_data;
    $data->{interpretation} = { phenopacket => {} };
    my $out = { phenopacket => $data };

    return $out;
}

################
################
#  REDCAP2BFF  #
################
################

sub redcap2bff {

    my $self = shift;

    # Read data from REDCap export
    my $data = read_redcap_export( $self->{in_file} );

    # Load (or read) REDCap CSV dictionary
    my $data_rcd = load_redcap_dictionary( $self->{redcap_dictionary} );

    print Dumper $data_rcd if ( $self->{debug} && $self->{debug} > 1 );

    # array_dispatcher will deal with JSON arrays
    $self->{data}     = $data;        # setter
    $self->{data_rcd} = $data_rcd;    # setter
    return array_dispatcher($self);
}

sub do_redcap2bff {

    my ( $self, $data ) = @_;
    my $rcd = $self->{data_rcd};
    my $sth = $self->{sth};

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
            $disease->{diseaseCode} = map_ontology(
                {
                    label       => $element,
                    ontology    => 'icd10',                        # ICD-10 ontology (term must be precise)
                    labels_true => $self->{print_hidden_labels},
                    sth         => $sth->{icd10}

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
    my @exposures = (
        qw (alcohol smoking cigarettes_days cigarettes_years packyears smoking_quit)
    );

    for my $element (@exposures) {
        next unless $participant->{$element} ne '';
        my $exposure;

        $exposure->{ageAtExposure} = undef;
        $exposure->{date}          = undef;          #'2010-07-10';
        $exposure->{duration}      = undef;          # 'P32Y6M1D';
        $exposure->{exposureCode}  = map_ontology(
            {
                label       => $element,
                ontology    => 'ncit',
                labels_true => $self->{print_hidden_labels},
                sth         => $sth->{ncit}
            }
        );

        # We first extract 'unit' and %range' for <measurementValue>
        my $unit = map_ontology(
            {
                label => ( $element eq 'alcohol' || $element eq 'smoking' )
                ? map_exposures(
                    {
                        key => $element,
                        str =>
                          $rcd->{$element}{_labels}{ $participant->{$element} }
                    }
                  )
                : $element,
                ontology    => 'ncit',
                labels_true => $self->{print_hidden_labels},
                sth         => $sth->{ncit}
            }
        );
        my $range = map_range($element);
        $exposure->{measurementValue} = [
            {
                Quantity => {
                    unit  => $unit,
                    value => dotify_number( $participant->{$element} ),
                    _note =>
'In many cases the <value> field shows the REDCap selection not the actual #items',
                    referenceRange => {

                        #unit => $unit, # Isn't this redundant (see above)???
                        low  => $range->{low},
                        high => $range->{high}
                    }
                }
            }
        ];
        push @{ $individual->{exposures} }, $exposure;
    }

    # ================
    # geographicOrigin
    # ================

    $individual->{geographicOrigin} = undef;

    # ==
    # id
    # ==

    $individual->{id} = $participant->{first_name}
      if ( exists $participant->{first_name} && $participant->{first_name} );
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
            $intervention->{procedureCode}   = map_ontology(
                {
                    label       => $surgery{$element},
                    ontology    => 'ncit',
                    labels_true => $self->{print_hidden_labels},
                    sth         => $sth->{ncit}
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

    # lab_remarks was removed
    my @measures = (
        qw (leucocytes hemoglobin hematokrit mcv mhc thrombocytes neutrophils lymphocytes eosinophils creatinine gfr bilirubin gpt ggt lipase crp iron il6 calprotectin)
    );
    for my $element (@measures) {
        next unless $participant->{$element} ne '';

        my $measure;
        $measure->{assayCode} = map_ontology(
            {
                label       => $element,
                ontology    => 'ncit',
                labels_true => $self->{print_hidden_labels},
                sth         => $sth->{ncit}
            }
        );
        $measure->{date} = undef;    # iso8601_time();

        # We first extract 'unit' and %range' for <measurementValue>
        my $unit = map_ontology(
            {
                label       => map_quantity( $rcd->{$element}{'Field Note'} ),
                ontology    => 'ncit',
                labels_true => $self->{print_hidden_labels},
                sth         => $sth->{ncit}
            }
        );
        my $range = map_range($element);
        $measure->{measurementValue} = [
            {
                Quantity => {
                    unit           => $unit,
                    value          => dotify_number( $participant->{$element} ),
                    referenceRange => {

                        #unit => $unit, # Isn't this redundant (see above)???
                        low  => $range->{low},
                        high => $range->{high}
                    }
                }
            }
        ];
        $measure->{notes} =
          "$element, Field Label=$rcd->{$element}{'Field Label'}";
        $measure->{observationMoment} = undef;          # Age
        $measure->{procedure}         = map_ontology(
            {
                label => $element ne 'calprotectin'
                ? 'Blood Test Result'
                : 'Feces',
                ontology    => 'ncit',
                labels_true => $self->{print_hidden_labels},
                sth         => $sth->{ncit}
            }
        );

        # Add to array
        push @{ $individual->{measures} }, $measure;    # SWITCHED OFF on 072622

    }

    # =========
    # pedigrees
    # =========

    $individual->{pedigrees} = [];

    # disease, id, members, numSubjects
    my @pedigrees = (qw ( x y ));
    for my $element (@pedigrees) {

        #next unless $participant->{$element} ne '';

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
    my @phenotypicFeatures = qw ( a b);
    for my $element (@phenotypicFeatures) {

        #next unless $participant->{$element} ne '';
        my $phenotypicFeature;
        $phenotypicFeature->{evidence} = undef;    # P32Y6M1D
        $phenotypicFeature->{excluded} =
          { Quantity => { unit => { id => '', label => '' }, value => undef } };
        $phenotypicFeature->{featureType} = [];
        $phenotypicFeature->{modifiers}   = { id => '', label => '' };
        $phenotypicFeature->{notes}       = { id => '', label => '' };
        $phenotypicFeature->{onset}       = { id => '', label => '' };
        $phenotypicFeature->{resolution}  = { id => '', label => '' };
        $phenotypicFeature->{severity}    = { id => '', label => '' };

        # Add to array
        #push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature;    # SWITCHED OFF on 072622
    }

    # ===
    # sex
    # ===

    $individual->{sex} = map_ontology(
        {
            label       => $rcd->{sex}{_labels}{ $participant->{sex} },
            ontology    => 'ncit',
            labels_true => $self->{print_hidden_labels},
            sth         => $sth->{ncit}

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

        #next unless $participant->{$element} ne '';
        my $treatment;

        my $tmp_var = $element . '_status';
        $treatment->{info} = {
            drug   => $element,
            status => $rcd->{$tmp_var}{_labels}{ $participant->{$tmp_var} }
        };    # ***** INTERNAL FIELD
        $treatment->{ageAtOnset} = undef;    # P32Y6M1D
        $treatment->{cumulativeDose} =
          { Quantity => { unit => { id => '', label => '' }, value => undef } };
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

########################
########################
#  READ REDCAP EXPORT  #
########################
########################

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

############################
############################
#  LOAD REDCAP DICTIONARY  #
############################
############################

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

            # For the key having labels, we create a new ad hoc key '_labels'
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

#########################
#########################
#  SUBROUTINES FOR I/O  #
#########################
#########################

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

#############################
#############################
#  SUBROUTINES FOR MAPPING  #
#############################
#############################

sub map_ethnicity {

    my $str       = shift;
    my %ethnicity = ( map { $_ => 'NCIT:C41261' } ( 'caucasian', 'white' ) );

    # 1, Caucasian | 2, Hispanic | 3, Asian | 4, African/African-American | 5, Indigenous American | 6, Mixed | 9, Other";
    return { id => $ethnicity{ lc($str) }, label => $str };
}

sub map_ontology {

    # Most of the execution time goes to this subroutine
    # We will adopt two estragies to gain speed:
    #  1 - Prepare once, excute often (almost no gain in speed :/ )
    #  2 - Create a global hash with "seen" queries (+++huge gain)

    #return { id => 'dummy', label => 'dummy' };    # test speed
    # Not a big fan of global stuff and premature return, but it works here...
    #  ¯\_(ツ)_/¯

    # Labels come in many forms, before checking existance we map to NCIT ones
    # Ad hoc modifications for 3TR
    my $tmp_label = $_[0]->{label};
    my $map_3tr   = 1;                # Boolean
    if ($map_3tr) {
        $tmp_label = map_3tr($tmp_label);
        ($tmp_label) = keys %{$tmp_label} if ref $tmp_label eq 'HASH';    # Only 1 key
    }

    # return if exists
    return $seen->{$tmp_label} if exists $seen->{$tmp_label};

    # return if we know 'a priori' that the label won't exist
    return { id => 'NCIT:NA', label => $tmp_label } if $tmp_label =~ m/xx/;

    # Ok, now it's time to start the subroutine
    my $arg                 = shift;
    my $ontology            = $arg->{ontology};
    my $print_hidden_labels = $arg->{labels_true};
    my $sth                 = $arg->{sth};

    # Perform query
    my ( $id, $label ) = execute_query_SQLite( $sth, $tmp_label, $ontology );

    # Add result to global $seen
    $seen->{$label} = { id => $id, label => $label };

    # id and label come from <db> _label is the original string (can change on partial matches)
    return $print_hidden_labels
      ? { id => $id, label => $label, _label => $tmp_label }
      : { id => $id, label => $label };
}

sub map_exposures {

    #alcohol;anamnesis;;radio;"Alcohol drinking habits";"0, Non-drinker | 1, Ex-drinker | 2, occasional drinking | 3, regular drinking | 4, unknown";;;;;;;y;;;;;
    #smoking;anamnesis;;radio;"Smoking habits";"0, Never smoked | 1, Ex-smoker | 2, Current smoker";;;;;;;y;;;;;

    my $arg      = shift;
    my $key      = $arg->{key};
    my $str      = $arg->{str};
    my $exposure = {
        smoking => {
            'Never smoked'   => 'Never Smoker',
            'Ex-smoker'      => 'Former Smoker',
            'Current smoker' => 'Current Smoker'
        },
        alcohol => {
            'Non-drinker' => 'Non-Drinker',
            'Ex-drinker' => 'Current non-drinker with Past Alcohol Consumption',
            'occasional drinking' =>
'Alcohol Consumption Equal to or Less than 2 Drinks per Day for Men and 1 Drink or Less per Day for Women',
            'regular drinking' =>
'Alcohol Consumption More than 2 Drinks per Day for Men and More than 1 Drink per Day for Women',
            unknown => 'Unknown'
        }
    };
    return exists $exposure->{$key} ? $exposure->{$key}{$str} : $str;
}

sub map_quantity {

    # https://phenopacket-schema.readthedocs.io/en/latest/quantity.html
    # https://www.ebi.ac.uk/ols/ontologies/ncit/terms?iri=http%3A%2F%2Fpurl.obolibrary.org%2Fobo%2FNCIT_C25709
    # Some SI units are in ncit but others aren't.
    # what do we do?
    #  - Hard coded in Hash? ==> Fast
    #  - Search every time on DB? ==> Slow
    my $str = shift;

    # SI UNITS (10^9/L)
    # hemoglobin;routine_lab_values;;text;Hemoglobin;;"xx.x g/dl";number;0;20;;;y;;;;;
    #leucocytes;routine_lab_values;;text;Leucocytes;;"xx.xx /10^-9 l";number;0;200;;;y;;;;;
    #hematokrit;routine_lab_values;;text;Hematokrit;;"xx.x %";number;0;100;;;y;;;;;
    #mcv;routine_lab_values;;text;"Mean red cell volume (MCV)";;"xx.x fl";number;0;200;;;y;;;;;
    #mhc;routine_lab_values;;text;"Mean red cell haemoglobin (MCH)";;"xx.x pg";number;0;100;;;y;;;;;
    #thrombocytes;routine_lab_values;;text;Thrombocytes;;"xxxx /10^-9 l";number;0;2000;;;y;;;;;
    #neutrophils;routine_lab_values;;text;Neutrophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
    #lymphocytes;routine_lab_values;;text;Lymphocytes;;"x.xx /10^-9 l";number;0;100;;;;;;;;
    #eosinophils;routine_lab_values;;text;Eosinophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
    #creatinine;routine_lab_values;;text;Creatinine;;"xxx µmol/l";number;0;10000;;;y;;;;;
    #gfr;routine_lab_values;;text;"GFR CKD-Epi";;"xxx ml/min/1.73";number;0;200;;;y;;;;;
    #bilirubin;routine_lab_values;;text;Bilirubin;;"xxx.x µmol/l";number;0;10000;;;y;;;;;
    #gpt;routine_lab_values;;text;GPT;;"xx.x U/l";number;0;10000;;;y;;;;;
    #ggt;routine_lab_values;;text;gammaGT;;"xx.x U/l";number;0;10000;;;y;;;;;
    #lipase;routine_lab_values;;text;Lipase;;"xx.x U/l";number;0;10000;;;;;;;;
    #crp;routine_lab_values;;text;CRP;;"xxx.x mg/l";number;0;1000;;;y;;;;;
    #iron;routine_lab_values;;text;Iron;;"xx.x µmol/l";number;0;1000;;;;;;;;
    #il6;routine_lab_values;;text;IL-6;;"xxxx.x ng/l";number;0;10000;;;;;;;;
    #calprotectin;routine_lab_values;;text;Calprotectin;;"mg/kg stool";integer;;;;;;;;;;

    # http://purl.obolibrary.org/obo/NCIT_C64783
    my %unit = (
        'xx.xx /10^-9 l' => 'Cells per Microliter',       # '10^9/L',
        'xx.x g/dl'      => 'Gram per Deciliter',         # 'g/dL',
        'xx.x fl'        => 'Femtoliter',                 # 'fL'
        'xx.x'           => 'Picogram',                   # 'pg',         #picograms
        'xx.x pg'        => 'Picogram',
        'xx.x µmol/l'    => 'Micromole per Liter',
        'xxx.x µmol/l'   => 'Micromole per Liter',
        'xxx µmol/l'     => 'Micromole per Liter',        # 'µmol/l',
        'ml/min/1.73'    => 'mL/min/1.73',
        'xx.x U/l'       => 'Units per Liter',
        'pg/dl'          => 'Picogram per Deciliter',     #'pg/dL',
        'mg/dl'          => 'Milligram per Deciliter',    #'mg/L',
        'µg/dl'          => 'Microgram per Deciliter',    #'µg/dL',
        'ng/dl'          => 'Nanogram per Deciliter',     #'ng/L'
        'mg/kg stool'    => 'Miligram per Kilogram',
        'xx.x %'         => 'Percentage'
    );

    #say "#{$str}# ====>  $unit{$str}" if  exists $unit{$str};
    return exists $unit{$str} ? $unit{$str} : $str;
}

sub dotify_number {

    my $val = shift;
    ( my $tr_val = $val ) =~ tr/,/./;

    # looks_like_number does not work with commas so we must tr first
    #say "$val === ",  looks_like_number($val);
    # coercing to number $tr_val and avoiding value = ""
    return
        looks_like_number($tr_val) ? 0 + $tr_val
      : $val eq ''                 ? undef
      :                              $val;
}

sub iso8601_time {

    my ( $s, $f ) = split( /\./, gettimeofday );
    return strftime( '%Y-%m-%dT%H:%M:%S.' . $f . '%z', localtime($s) );
}

sub map_3tr {

    my $str  = shift;
    my $term = {

        # hemoglobin leucocytes hematokrit mcv mhc thrombocytes neutrophils lymphocytes eosinophils creatinine gfr bilirubin gpt ggt lipase crp iron il6 calprotectin
        #hemoglobin;routine_lab_values;;text;Hemoglobin;;"xx.x g/dl";number;0;20;;;y;;;;;
        #leucocytes;routine_lab_values;;text;Leucocytes;;"xx.xx /10^-9 l";number;0;200;;;y;;;;;
        #hematokrit;routine_lab_values;;text;Hematokrit;;"xx.x %";number;0;100;;;y;;;;;
        #mcv;routine_lab_values;;text;"Mean red cell volume (MCV)";;"xx.x fl";number;0;200;;;y;;;;;
        #mhc;routine_lab_values;;text;"Mean red cell haemoglobin (MCH)";;"xx.x pg";number;0;100;;;y;;;;;
        #thrombocytes;routine_lab_values;;text;Thrombocytes;;"xxxx /10^-9 l";number;0;2000;;;y;;;;;
        #neutrophils;routine_lab_values;;text;Neutrophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
        #lymphocytes;routine_lab_values;;text;Lymphocytes;;"x.xx /10^-9 l";number;0;100;;;;;;;;
        #eosinophils;routine_lab_values;;text;Eosinophils;;"x.xx /10^-9 l";number;0;100;;;;;;;;
        #creatinine;routine_lab_values;;text;Creatinine;;"xxx µmol/l";number;0;10000;;;y;;;;;
        #gfr;routine_lab_values;;text;"GFR CKD-Epi";;"xxx ml/min/1.73";number;0;200;;;y;;;;;
        #bilirubin;routine_lab_values;;text;Bilirubin;;"xxx.x µmol/l";number;0;10000;;;y;;;;;
        #gpt;routine_lab_values;;text;GPT;;"xx.x U/l";number;0;10000;;;y;;;;;
        #ggt;routine_lab_values;;text;gammaGT;;"xx.x U/l";number;0;10000;;;y;;;;;
        #lipase;routine_lab_values;;text;Lipase;;"xx.x U/l";number;0;10000;;;;;;;;
        #crp;routine_lab_values;;text;CRP;;"xxx.x mg/l";number;0;1000;;;y;;;;;
        #iron;routine_lab_values;;text;Iron;;"xx.x µmol/l";number;0;1000;;;;;;;;
        #il6;routine_lab_values;;text;IL-6;;"xxxx.x ng/l";number;0;10000;;;;;;;;
        #calprotectin;routine_lab_values;;text;Calprotectin;;"mg/kg stool";integer;;;;;;;;;;

        hemoglobin => { 'Hemoglobin Measurement' => { low => 0, high => 20 } },
        leucocytes => { 'Leukocyte Count'        => { low => 0, high => 200 } },
        hematokrit => { 'Hematocrit Measurement' => { low => 0, high => 100 } },
        mcv        => {
            'Erythrocyte Mean Corpuscular Volume' => { low => 0, high => 200 }
        },
        mhc => {
            'Erythrocyte Mean Corpuscular Hemoglobin' =>
              { low => 0, high => 100 }
        },
        thrombocytes => { 'Platelet Count'   => { low => 0, high => 2000 } },
        neutrophils  => { 'Neutrophil Count' => { low => 0, high => 100 } },
        lymphocytes  => { 'Lymphocyte Count' => { low => 0, high => 100 } },
        eosinophils  => { 'Eosinophil Count' => { low => 0, high => 100 } },
        creatinine   =>
          { 'Creatinine Measurement' => { low => 0, high => 10_000 } },
        gfr => { 'Glomerular Filtration Rate' => { low => 0, high => 200 } },
        bilirubin =>
          { 'Total Bilirubin Measurement' => { low => 0, high => 10_000 } },
        gpt => {
            'Serum Glutamic Pyruvic Transaminase, CTCAE' =>
              { low => 0, high => 10_000 }
        },
        ggt => {
            'Serum Gamma Glutamyl Transpeptidase Measurement' =>
              { low => 0, high => 10_000 }
        },
        lipase => { 'Lipase Measurement' => { low => 0, high => 10_000 } },
        crp    =>
          { 'C-Reactive Protein Measurement' => { low => 0, high => 1000 } },
        iron         => { 'Iron Measurement' => { low => 0, high => 1000 } },
        il6          => { 'Interleukin-6'    => { low => 0, high => 10_000 } },
        calprotectin =>
          { 'Calprotectin Measurement' => { low => 0, high => 150 } },

        #cigarettes_days;anamnesis;;text;"On average, how many cigarettes do/did you smoke per day?";;;integer;0;300;;"[smoking] = '2' or [smoking] = '1'";;;;;;
        #cigarettes_years;anamnesis;;text;"For how many years have you been smoking/did you smoke?";;;integer;0;100;;"[smoking] = '2' or [smoking] = '1'";;;;;;
        #packyears;anamnesis;;text;"Pack Years";;;integer;0;300;;"[smoking] = '2' or [smoking] = '1'";;;;;;
        #smoking_quit;anamnesis;;text;"When did you quit smoking?";;year;integer;1980;2030;;"[smoking] = '2'";;;;;;
        cigarettes_days => {
            'Average Number Cigarettes Smoked a Day' =>
              { low => 0, high => 300 }
        },
        cigarettes_years =>
          { 'Total Years Have Smoked Cigarettes' => { low => 0, high => 100 } },
        packyears    => { 'Pack Year' => { low => 0, high => 300 } },
        smoking_quit =>
          { 'Smoking Cessation Year' => { low => 1980, high => 2030 } }
    };
    return exists $term->{$str} ? $term->{$str} : $str;
}

sub map_range {

    my $element = shift;
    my $map_3tr = map_3tr($element);
    my $hash   = { map { $_ => undef } qw(low high) };    # Initialize to undef
    if ( ref $map_3tr eq 'HASH' ) {
        my ($key) = keys %{$map_3tr};
        for my $range (qw (low high)) {
            $hash->{$range} = $map_3tr->{$key}{$range};
        }
    }
    return $hash;
}

########################
########################
#  SUBROUTINES FOR DB  #
########################
########################

sub open_connections_SQLite {

    my $self = shift;

    # Opening the DB once (instead that on each call) improves speed ~15%
    my $dbh;
    $dbh->{$_} = open_db_SQLite($_) for (@sqlites);    # global

    # Add $dbh HANDLE to $self
    $self->{dbh} = $dbh;                               # setter

    # Prepare the query once
    prepare_query_SQLite($self);

    return 1;
}

sub close_connections_SQLite {

    my $self = shift;
    my $dbh  = $self->{dbh};
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

sub prepare_query_SQLite {

    my $self  = shift;
    my $field = 'exact_match';

    for my $ontology (@sqlites) {    #global
        my $db         = uc($ontology) . '_table';
        my $dbh        = $self->{dbh}{$ontology};
        my %query_type = (
            contains =>
qq(SELECT * FROM $db WHERE label LIKE '%' || ? || '%' COLLATE NOCASE),
            contains_word =>
qq(SELECT * FROM $db WHERE label LIKE '% ' || ? || ' %' COLLATE NOCASE),
            exact_match => qq(SELECT * FROM $db WHERE label = ? COLLATE NOCASE),
            begins_with =>
              qq(SELECT * FROM $db WHERE label LIKE ? || '%' COLLATE NOCASE)
        );
        my $sth = $dbh->prepare(<<SQL);
$query_type{$field}
SQL
        $self->{sth}{$ontology} = $sth;    # setter
    }
    return 1;
}

sub execute_query_SQLite {

    my ( $sth, $query, $ontology ) = @_;
    my $field = 'exact_match';

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
    open_connections_SQLite($self) if $self->{method} ne 'bff2pxf';

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
    close_connections_SQLite($self) unless $self->{method} eq 'bff2pxf';

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
