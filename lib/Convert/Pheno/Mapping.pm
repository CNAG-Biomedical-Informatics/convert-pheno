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
use List::Util   qw(first);
use Convert::Pheno::SQLite;
binmode STDOUT, ':encoding(utf-8)';
use Exporter 'import';
our @EXPORT =
  qw( map_ethnicity map_ontology dotify_and_coerce_number iso8601_time _map2iso8601 map_unit_range map_age_range map2redcap_dic map2ohdsi_dic convert2boolean find_age randStr is_multidimensional);

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

    #return { id => 'dummy', label => 'dummy' } # test speed

    # Checking for existance in %$seen
    my $tmp_query = $_[0]->{query};
    say "Skipping searching for <$tmp_query> as it already exists"
      if DEVEL_MODE && exists $seen->{$tmp_query};

    # return if terms has already been searched and exists
    # Not a big fan of global stuff...
    #  ¯\_(ツ)_/¯
    # Premature return
    return $seen->{$tmp_query} if exists $seen->{$tmp_query};    # global

    say "searching for <$tmp_query>" if DEVEL_MODE;

    # return something if we know 'a priori' that the query won't exist
    #return { id => 'NCIT:NA000', label => $tmp_query } if $tmp_query =~ m/xx/;

    # Ok, now it's time to start the subroutine
    my $arg                       = shift;
    my $column                    = $arg->{column};
    my $ontology                  = $arg->{ontology};
    my $self                      = $arg->{self};
    my $match                     = $self->{match};
    my $print_hidden_labels       = $self->{print_hidden_labels};
    my $text_similarity_method    = $self->{text_similarity_method};
    my $min_text_similarity_score = $self->{min_text_similarity_score};

    # Die if user wants OHDSI w/o flag -ohdsi-db
    confess
"Please use the flag <-ohdsi-db> to enable searching at Athena-OHDSI database"
      if ( $ontology eq 'ohdsi' && !$self->{ohdsi_db} );

    # Perform query
    my ( $id, $label ) = get_ontology(
        {
            sth_column_ref            => $self->{sth}{$ontology}{$column},
            query                     => $tmp_query,
            ontology                  => $ontology,
            column                    => $column,
            match                     => $match,
            text_similarity_method    => $text_similarity_method,
            min_text_similarity_score => $min_text_similarity_score
        }
    );

    # Add result to global $seen
    $seen->{$tmp_query} = { id => $id, label => $label };    # global

# id and label come from <db> _label is the original string (can change on partial matches)
    return $print_hidden_labels
      ? { id => $id, label => $label, _label => $tmp_query }
      : { id => $id, label => $label };
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
    my ( $redcap_dic, $participant, $field, $labels ) = (
        $arg->{redcap_dic}, $arg->{participant},
        $arg->{field},      $arg->{labels}
    );
    return $labels
      ? $redcap_dic->{$field}{_labels}{ $participant->{$field} }
      : $redcap_dic->{$field}{'Field Note'};
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

sub is_multidimensional {

    return ref shift ? 1 : 0;
}

1;
