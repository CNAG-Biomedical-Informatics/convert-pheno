package Convert::Pheno::Mapping;

use strict;
use warnings;
use autodie;
use Carp    qw(confess);
use feature qw(say);
use utf8;
use Data::Dumper;
use JSON::XS;
use Time::HiRes  qw(gettimeofday);
use POSIX        qw(strftime);
use Scalar::Util qw(looks_like_number);
use Convert::Pheno::SQLite;
binmode STDOUT, ':encoding(utf-8)';
use Exporter 'import';
our @EXPORT =
  qw( map_ethnicity map_ontology map_quantity dotify_and_coerce_number iso8601_time _map2iso8601 map_3tr map_unit_range map_age_range map2redcap_dic map2ohdsi_dic convert2boolean find_age randStr);

use constant DEVEL_MODE => 0;

# Global hasref
my $seen = {};

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

    # Before checking existance we map to 3TR to -NCIT
    my $tmp_query = map_3tr( $_[0]->{query} );

    say "Skipping searching for <$tmp_query> as it already exists" if DEVEL_MODE && exists $seen->{$tmp_query};
    # return if terms has already been searched and exists
    # Not a big fan of global stuff...
    #  ¯\_(ツ)_/¯
    # Premature return
    return $seen->{$tmp_query} if exists $seen->{$tmp_query};    # global

    say "searching for <$tmp_query>" if DEVEL_MODE;
 
    # return something if we know 'a priori' that the query won't exist
    #return { id => 'NCIT:NA000', label => $tmp_query } if $tmp_query =~ m/xx/;

    # Ok, now it's time to start the subroutine
    my $arg      = shift;
    my $column   = $arg->{column};
    my $ontology = $arg->{ontology};
    my $match =
      exists $arg->{match}
      ? $arg->{match}
      : 'exact_match';    # Only option as of 090422
    my $self                = $arg->{self};
    my $print_hidden_labels = $self->{print_hidden_labels};
    my $sth = $self->{sth}{$ontology}{$column}{$match};    # IMPORTANT STEP

    # Die if user wants OHDSI w/o flag -ohdsi-db
    confess
"Please use the flag <-ohdsi-db> to enable searching at Athena-OHDSI database"
      if ( $ontology eq 'ohdsi' && !$self->{ohdsi_db} );

    # Perform query
    my ( $id, $label ) = execute_query_SQLite(
        {
            sth      => $sth,
            query    => $tmp_query,
            ontology => $ontology,
            match    => $match
        }
    );

    # Add result to global $seen
    $seen->{$tmp_query} = { id => $id, label => $label };    # global

# id and label come from <db> _label is the original string (can change on partial matches)
    return $print_hidden_labels
      ? { id => $id, label => $label, _label => $tmp_query }
      : { id => $id, label => $label };
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

    # http://purl.obolibrary.org/obo/NCIT_C64783          # SI units
    # label => NCIT
    my %unit = (
        'xx.xx /10^-9 l' => 'Cells per Microliter',   # '10^9/L',
        'x.xx /10^-9 l'  => 'Cells per Microliter',   #
        'xxxx /10^-9 l'  => 'Cells per Microliter',
        'xx.x g/dl'      => 'Gram per Deciliter',     # 'g/dL',
        'xx.x fl'        => 'Femtoliter',             # 'fL'
        'xx.x'           => 'Picogram',               # 'pg',         #picograms
        'xx.x pg'        => 'Picogram',
        'xx.x µmol/l'    => 'Micromole per Liter',
        'xxx.x µmol/l'   => 'Micromole per Liter',
        'xxx µmol/l'     => 'Micromole per Liter',    # 'µmol/l',

        #        'ml/min/1.73'    => 'mL/min/1.73',
        #        'xxx ml/min/1.73' => 'mL/min/1.73',
        'xx.x U/l' => 'Units per Liter',
        'pg/dl'    => 'Picogram per Deciliter',     #'pg/dL',
        'mg/dl'    => 'Milligram per Deciliter',    #'mg/dL',

        #       'xxx.x mg/l'     => 'Milligram per Liter',
        'µg/dl'       => 'Microgram per Deciliter',    #'µg/dL',
        'ng/dl'       => 'Nanogram per Deciliter',     #'ng/dL'
        'xxxx.x ng/l' => 'Nanogram per Liter',
        'mg/kg stool' => 'Miligram per Kilogram',
        'xx.x %'      => 'Percentage'
    );

    #say "#{$str}# ====>  $unit{$str}" if  exists $unit{$str};
    return exists $unit{$str} ? $unit{$str} : $str;
}

sub dotify_and_coerce_number {

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

# Standard modules (gmtime()===>Coordinated Universal Time(UTC))
# NB: The T separates the date portion from the time-of-day portion.
#     The Z on the end means UTC (that is, an offset-from-UTC of zero hours-minutes-seconds).
#     - The Z is pronounced “Zulu”.
    my $now = time();
    return strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime($now) );
}

sub _map2iso8601 {

    my ( $date, $time ) = split /\s+/, shift;

    # UTC
    return $date
      . ( ( defined $time && $time =~ m/^T(.+)Z$/ ) ? $time : 'T00:00:00Z' );
}

sub map_3tr {

    my $str  = shift;
    my %term = (

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

        # Field => NCIT Term
        hemoglobin   => 'Hemoglobin Measurement',
        leucocytes   => 'Leukocyte Count',
        hematokrit   => 'Hematocrit Measurement',
        mcv          => 'Erythrocyte Mean Corpuscular Volume',
        mhc          => 'Erythrocyte Mean Corpuscular Hemoglobin',
        thrombocytes => 'Platelet Count',
        neutrophils  => 'Neutrophil Count',
        lymphocytes  => 'Lymphocyte Count',
        eosinophils  => 'Eosinophil Count',
        creatinine   => 'Creatinine Measurement',
        gfr          => 'Glomerular Filtration Rate',
        bilirubin    => 'Total Bilirubin Measurement',
        gpt          => 'Serum Glutamic Pyruvic Transaminase, CTCAE',
        ggt          => 'Serum Gamma Glutamyl Transpeptidase Measurement',
        lipase       => 'Lipase Measurement',
        crp          => 'C-Reactive Protein Measurement',
        iron         => 'Iron Measurement',
        il6          => 'Interleukin-6',
        calprotectin => 'Calprotectin Measurement',

#cigarettes_days;anamnesis;;text;"On average, how many cigarettes do/did you smoke per day?";;;integer;0;300;;"[smoking] = '2' or [smoking] = '1'";;;;;;
#cigarettes_years;anamnesis;;text;"For how many years have you been smoking/did you smoke?";;;integer;0;100;;"[smoking] = '2' or [smoking] = '1'";;;;;;
#packyears;anamnesis;;text;"Pack Years";;;integer;0;300;;"[smoking] = '2' or [smoking] = '1'";;;;;;
#smoking_quit;anamnesis;;text;"When did you quit smoking?";;year;integer;1980;2030;;"[smoking] = '2'";;;;;;
        cigarettes_days  => 'Average Number Cigarettes Smoked a Day',
        cigarettes_years => 'Total Years Have Smoked Cigarettes',
        packyears        => 'Pack Year',
        smoking_quit     => 'Smoking Cessation Year',

#nancy_index_ulceration;endoscopy;;radio;"Nancy histology index: Ulceration";"0, 0 - none|2, 2 - yes";;;;;;"[endoscopy_performed] = '1' AND [week_0_arm_1][diagnosis] = '2'";y;;;;;
#nancy_index_acute;endoscopy;;radio;"Nancy histology index: Acute inflammatory cell infiltrate";"0, 0 - none|2, 2 - mild|3, 3 - moderate|4, 4 - severe";;;;;;"[endoscopy_performed] = '1' AND [week_0_arm_1][diagnosis] = '2'";y;;;;;
# nancy_index_chronic;endoscopy;;radio;"Nancy histology index: Chronic inflammatory infiltrates";"0, 0 - none|1, 1 - mild|3, 3 - moderate or marked increase";;;;;;"[endoscopy_performed] = '1' AND [week_0_arm_1][diagnosis] = '2'";y;;;;;
        nancy_index_ulceration => 'Nancy Index Ulceration',
        nancy_index_acute      =>
          'Nancy histology index: Acute inflammatory cell infiltrate',
        nancy_index_chronic =>
          'Nancy histology index: Chronic inflammatory infiltrates'
    );
    return exists $term{$str} ? $term{$str} : $str;
}

sub map_unit_range {

    my $arg        = shift;
    my $field      = $arg->{field};
    my $redcap_dic = $arg->{redcap_dic};
    my %hash = ( low => 'Text Validation Min', high => 'Text Validation Max' );
    my $hashref = { map { $_ => undef } qw(low high) };    # Initialize to undef
    for my $range (qw (low high)) {
        $hashref->{$range} =
          dotify_and_coerce_number( $redcap_dic->{$field}{ $hash{$range} } );
    }
    return $hashref;
}

sub map_age_range {

    my $str = shift;
    $str =~ s/\+/-9999/;                                   #60+#
    my ( $start, $end ) = split /\-/, $str;

    return {
        ageRange => {
            start => {
                iso8601duration => 'P' . dotify_and_coerce_number($start) . 'Y'
            },
            end =>
              { iso8601duration => 'P' . dotify_and_coerce_number($end) . 'Y' }
        }
    };
}

sub map2redcap_dic {

    my $arg = shift;
    my ( $redcap_dic, $participant, $field ) =
      ( $arg->{redcap_dic}, $arg->{participant}, $arg->{field} );
    return $redcap_dic->{$field}{_labels}{ $participant->{$field} };
}

sub map2ohdsi_dic {

    my $arg = shift;
    my ( $ohdsi_dic, $concept_id ) = ( $arg->{ohdsi_dic}, $arg->{concept_id} );

# NB: Here we don't win any speed over $seen as we are already searching in a hash
    my ( $id, $label, $vocabulary ) = ( undef, undef, undef );
    if ( exists $ohdsi_dic->{$concept_id} ) {
        $id         = $ohdsi_dic->{$concept_id}{concept_code};
        $label      = $ohdsi_dic->{$concept_id}{concept_name};
        $vocabulary = $ohdsi_dic->{$concept_id}{vocabulary_id};
        return { id => "$vocabulary:$id", label => $label };
    }
    else {
        return 0;    # A priori ALL concept_id MUST be in CONCEPTS table
    }
}

sub convert2boolean {

    my $val = lc(shift);
    return
        ( $val eq 'true'  || $val eq 'yes' ) ? JSON::XS::true
      : ( $val eq 'false' || $val eq 'no' )  ? JSON::XS::false
      :                                        undef;          # unknown = undef

}

sub find_age {

    # Not using any CPAN module for now
    # Adapted from https://www.perlmonks.org/?node_id=9995

    # Assuming $birth_month is 0..11
    my $arg   = shift;
    my $birth = $arg->{birth_day};
    my $date  = $arg->{date};

    # Not a big fan of premature return, but it works here...
    #  ¯\_(ツ)_/¯
    return unless ( $birth && $date );

    my ( $birth_year, $birth_month, $birth_day ) =
      ( split /\-|\s+/, $birth )[ 0 .. 2 ];
    my ( $year, $month, $day ) = ( split /\-/, $date )[ 0 .. 2 ];

    #my ($day, $month, $year) = (localtime)[3..5];
    #$year += 1900;

    my $age = $year - $birth_year;
    $age--
      unless sprintf( "%02d%02d", $month, $day ) >=
      sprintf( "%02d%02d", $birth_month, $birth_day );
    return $age . 'Y';
}

sub randStr {

    #https://www.perlmonks.org/?node_id=233023
    return join( '',
        map { ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 )[ rand 62 ] } 0 .. shift );
}
1;
