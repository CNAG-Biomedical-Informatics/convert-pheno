package Convert::Pheno::Mapping;

use strict;
use warnings;
use autodie;

#use Carp    qw(confess);
use feature qw(say);
use utf8;
use Data::Dumper;
use JSON::XS;
use Time::HiRes  qw(gettimeofday);
use POSIX        qw(strftime);
use Scalar::Util qw(looks_like_number);
use List::Util   qw(first);
use Cwd          qw(cwd);
use Sys::Hostname;
use Convert::Pheno::SQLite;
use Convert::Pheno::Default qw(get_defaults);
use Exporter 'import';
our @EXPORT =
  qw(map_ontology_term dotify_and_coerce_number iso8601_time _map2iso8601 map_reference_range map_reference_range_csv map_age_range map2redcap_dict map2ohdsi convert2boolean find_age randStr map_operator_concept_id map_info_field map_omop_visit_occurrence dot_date2iso validate_format get_metaData get_info);

my $DEFAULT = get_defaults();
use constant DEVEL_MODE => 0;

# Global hash
my %seen = ();

#############################
#############################
#  HELPER SUBS FOR MAPPING  #
#############################
#############################

sub map_ontology_term {

    # Most of the execution time goes to this subroutine
    # We will adopt two estragies to gain speed:
    #  1 - Prepare once, excute often (almost no gain in speed :/ )
    #  2 - Create a global hash with "seen" queries (+++huge gain)

    #return { id => 'dummy', label => 'dummy' } # test speed

    # We will return quickly when nothing has to be done
    my $query = $_[0]->{query};

    # Skipping numbers
    return $DEFAULT->{ontology_term} if looks_like_number($query);

    # If the ontology term is an object we assume it comes
    # from "terminology" property in the mapping file
    return $query if ref $query eq 'HASH';

    # Checking for existance in %seen
    say "Skipping searching for <$query> as it already exists"
      if DEVEL_MODE && exists $seen{$query};

    # return if terms has already been searched and exists
    # Not a big fan of global stuff...
    #  ¯\_(ツ)_/¯
    # Premature return
    return $seen{$query} if exists $seen{$query};    # global

    # return something if we know 'a priori' that the query won't exist
    #return { id => 'NCIT:NA000', label => $query } if $query =~ m/xx/;

    # Ok, now it's time to start the subroutine
    my $arg                       = shift;
    my $column                    = $arg->{column};
    my $ontology                  = $arg->{ontology};
    my $self                      = $arg->{self};
    my $databases                 = $self->{databases};
    my $search                    = $self->{search};
    my $print_hidden_labels       = $self->{print_hidden_labels};
    my $text_similarity_method    = $self->{text_similarity_method};
    my $min_text_similarity_score = $self->{min_text_similarity_score};

    # DEVEL_MODE
    say "searching for query <$query> in ontology <$ontology>" if DEVEL_MODE;

    # Die if user wants OHDSI w/o flag -ohdsi-db
    die
"Could not find the concept_id:<$query> in the provided <CONCEPT> table.\nPlease use the flag <--ohdsi-db> to enable searching at Athena-OHDSI database\n"
      if ( $ontology eq 'ohdsi' && !$self->{ohdsi_db} );

    # Perform query
    my ( $id, $label ) = get_ontology_terms(
        {
            sth_column_ref            => $self->{sth}{$ontology}{$column},
            query                     => $query,
            ontology                  => $ontology,
            databases                 => $databases,
            column                    => $column,
            search                    => $search,
            text_similarity_method    => $text_similarity_method,
            min_text_similarity_score => $min_text_similarity_score
        }
    );

    # Add result to global %seen
    $seen{$query} = { id => $id, label => $label };    # global

    # id and label come from <db> _label is the original string (can change on partial matches)
    return $print_hidden_labels
      ? { id => $id, label => $label, _label => $query }
      : { id => $id, label => $label };
}

sub dotify_and_coerce_number {
    my $val = shift;

    # Premature return
    return undef unless ( defined $val && $val ne '' );

    # looks_like_number does not work with commas so we must tr first
    ( my $tr_val = $val ) =~ tr/,/./;

    #print "#$val#$tr_val#\n";

    # coercing to number $tr_val
    return looks_like_number($tr_val)
      ? 0 + $tr_val
      : $val;
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

sub map_reference_range {
    my $arg         = shift;
    my $field       = $arg->{field};
    my $redcap_dict = $arg->{redcap_dict};
    my $unit        = $arg->{unit};
    my %hash = ( low => 'Text Validation Min', high => 'Text Validation Max' );
    my $hashref = {
        unit => $unit,
        map { $_ => undef } qw(low high)
    };    # Initialize low,high to undef
    for my $range (qw (low high)) {
        $hashref->{$range} =
          dotify_and_coerce_number( $redcap_dict->{$field}{ $hash{$range} } );
    }

    return $hashref;
}

sub map_reference_range_csv {
    my ( $unit, $range ) = @_;
    $range->{unit} = $unit;
    return $range;
}

sub map_age_range {
    my $str = shift;

    # Premature return if not range
    return { age =>
          { iso8601duration => 'P' . dotify_and_coerce_number($str) . 'Y' } }
      unless $str =~ m/\-|\+/;

    # if range
    $str =~ s/\+/\-999/;    # from '70+' '70-999'
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

sub map2redcap_dict {
    my $arg = shift;
    my ( $redcap_dict, $participant, $field, $labels ) = (
        $arg->{redcap_dict}, $arg->{participant},
        $arg->{field},       $arg->{labels}
    );

    # Options:
    #  labels = 1
    #     _labels
    #  labels = 0
    #    'Field Note'

    # NB: Some numeric fields will get stringified at $participant->{$field}
    return $labels
      ? $redcap_dict->{$field}{_labels}{ $participant->{$field} }
      : $redcap_dict->{$field}{'Field Note'};
}

sub map2ohdsi {
    my $arg = shift;
    my ( $ohdsi_dict, $concept_id, $self ) =
      ( $arg->{ohdsi_dict}, $arg->{concept_id}, $arg->{self} );

    #######################
    # OPTION A: <CONCEPT> #
    #######################

    # NB1: Here we don't win any speed over using %seen as ...
    # .. we are already searching in a hash
    # NB2: $concept_id is stringified by hash
    my ( $data, $id, $label, $vocabulary ) = ( (undef) x 4 );
    if ( exists $ohdsi_dict->{$concept_id} ) {
        $id         = $ohdsi_dict->{$concept_id}{concept_code};
        $label      = $ohdsi_dict->{$concept_id}{concept_name};
        $vocabulary = $ohdsi_dict->{$concept_id}{vocabulary_id};
        $data       = { id => qq($vocabulary:$id), label => $label };
    }

    ######################
    # OPTION B: External #
    ######################

    else {
        $data = map_ontology_term(
            {
                query    => $concept_id,
                column   => 'concept_id',
                ontology => 'ohdsi',
                self     => $self
            }
        );
    }
    return $data;
}

sub convert2boolean {
    my $val = lc(shift);
    return
        ( $val eq 'true'  || $val eq 'yes' ) ? JSON::XS::true
      : ( $val eq 'false' || $val eq 'no' )  ? JSON::XS::false
      :                                        undef;            # unknown = undef

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

sub map_operator_concept_id {
    my $arg  = shift;
    my $id   = $arg->{operator_concept_id};
    my $val  = $arg->{value_as_number};
    my $unit = $arg->{unit};

    # Define hash for possible values
    my %operator_concept_id = ( 4172704 => 'GT', 4172756 => 'LT' );

    #  4172703 => 'EQ';

    # $hasref will be used for return
    my $hashref = undef;

    # Only for GT || LT
    if ( exists $operator_concept_id{$id} ) {
        $hashref = {
            unit => $unit,
            map { $_ => undef } qw(low high)
        };    # Initialize low,high to undef
        if ( $operator_concept_id{$id} eq 'GT' ) {
            $hashref->{high} = dotify_and_coerce_number($val);
        }
        else {
            $hashref->{low} = dotify_and_coerce_number($val);
        }
    }
    return $hashref;
}

sub map_omop_visit_occurrence {
    # key eq 'visit_occurrence_id'
    # { '85' =>
    #    {
    #          'admitting_source_concept_id' => 0,
    #          'admitting_source_value' => undef,
    #          'care_site_id' => '\\N',
    #          'discharge_to_concept_id' => 0,
    #          'discharge_to_source_value' => undef,
    #          'person_id' => 1,
    #          'preceding_visit_occurrence_id' => 82,
    #          'provider_id' => '\\N',
    #          'visit_concept_id' => 9201,
    #          'visit_end_date' => '1981-08-19',
    #          'visit_end_datetime' => '1981-08-19 00:00:00',
    #          'visit_occurrence_id' => 85,
    #          'visit_source_concept_id' => 0,
    #          'visit_source_value' => '7879d5b2-1af2-49a7-a801-121de124c6af',
    #          'visit_start_date' => '1981-08-18',
    #          'visit_start_datetime' => '1981-08-18 00:00:00',
    #          'visit_type_concept_id' => 44818517
    #        }
    # }

    my $arg                 = shift;
    my $self                = $arg->{self};
    my $ohdsi_dict          = $arg->{ohdsi_dict};
    my $person_id           = $arg->{person_id};
    my $visit_occurrence_id = $arg->{visit_occurrence_id};
    my $visit_occurrence    = $self->{visit_occurrence};

    # Premature return
    return undef if $visit_occurrence_id eq '\\N';    # perlcritic Severity: 5

    # *** IMPORTANT ***
    # EUNOMIA instance has mismatches between the person_id -- visit_occurrence_id
    # For instance, person_id = 1 has only visit_occurrence_id = 85, but on tables it has:
    # 82, 84, 42, 54, 41, 25, 76 and 81

    # warn if we don't have $visit_occurrence_id in VISIT_OCCURRENCE
    unless ( exists $visit_occurrence->{$visit_occurrence_id} ) {
        warn
"Sorry, but <visit_occurrence_id:$visit_occurrence_id> does not exist for <person_id:$person_id>\n"
          if DEVEL_MODE;

        # Premature return
        return undef;    # perlcritic Severity: 5
    }

    # Getting pointer to the hash element
    my $hashref = $visit_occurrence->{$visit_occurrence_id};

    my $concept = map2ohdsi(
        {
            ohdsi_dict => $ohdsi_dict,
            concept_id => $hashref->{visit_concept_id},
            self       => $self

        }
    );

    # *** IMPORTANT ***
    # Ad hoc to avoid using --ohdsi-db while we find a solution to EUNOMIA not being self-contained
    my $ad_hoc_44818517 = {
        id    => "Visit Type:OMOP4822465",
        label => "Visit derived from encounter on claim"
    };
    my $type =
        $hashref->{visit_type_concept_id} == 44818517
      ? $ad_hoc_44818517
      : map2ohdsi(
        {
            ohdsi_dict => $ohdsi_dict,
            concept_id => $hashref->{visit_type_concept_id},
            self       => $self

        }
      );
    my $start_date = _map2iso8601( $hashref->{visit_start_date} );
    my $end_date   = _map2iso8601( $hashref->{visit_end_date} );
    my $info       = { VISIT_OCCURRENCE => { OMOP_columns => $hashref } };

    return {
        _info         => $info,
        id            => $visit_occurrence_id,
        concept       => $concept,
        type          => $type,
        start_date    => $start_date,
        end_date      => $end_date,
        occurrence_id => $hashref->{visit_occurrence_id}
    };
}

sub dot_date2iso {

    # We can get
    # '', '1990.12.25',  '1990-12-25'
    my $date = shift // '';

    # Premature returns
    return '1900-01-01' if $date eq '';
    return $date        if $date =~ m/^(\d{4})\-(\d{2})\-(\d{2})$/;

    # Split '1990.12.25'
    my ( $d, $m, $y ) = split /\./, $date;

    # YYYYMMDD
    return qq/$y-$m-$d/;
}

sub is_multidimensional {
    return ref shift ? 1 : 0;
}

sub validate_format {
    my ( $data, $format ) = @_;

    my $result;

    # PXF
    if ( $format eq 'pxf' ) {
        $result = exists $data->{subject} ? 1 : 0;

        # BFF
    }
    else {
        $result = !exists $data->{subject} ? 1 : 0;
    }
    return $result;
}

sub get_info {
    my $self = shift;

    # Detecting the number of logical CPUs across different OSes
    my $os = $^O;
    chomp(
        my $threadshost =
          lc($os) eq 'darwin' ? qx{/usr/sbin/sysctl -n hw.logicalcpu}
        : lc($os) eq 'freebsd' ? qx{sysctl -n hw.ncpu}
        : $os eq 'MSWin32'     ? qx{wmic cpu get NumberOfLogicalProcessors}
        :                        qx{/usr/bin/nproc} // 1
    );

    # For the Windows command, the result will also contain the string
    # "NumberOfLogicalProcessors" which is the header of the output.
    # So we need to extract the actual number from it:
    if ( $os eq 'MSWin32' ) {
        ($threadshost) = $threadshost =~ /(\d+)/;
    }
    $threadshost = 0 + $threadshost;    # coercing it to be a number

    return {
        user => $ENV{'LOGNAME'}
          || $ENV{'USER'}
          || $ENV{'USERNAME'}
          || 'dummy-user',
        username    => $self->{username},
        threadshost => $threadshost,
        cwd         => cwd,
        id          => $self->{id},
        hostname    => hostname,
        version     => $::VERSION
    };
}

sub get_metaData {
    my $self = shift;

    # Setting a few variables
    my $username = $self->{username};

    # Setting resources
    my $resources = [
        {
            id   => 'icd10',
            name =>
'International Statistical Classification of Diseases and Related Health Problems 10th Revision',
            url             => 'https://icd.who.int/browse10/2019/en#',
            version         => '2019',
            namespacePrefix => 'ICD10',
            iriPrefix       => 'https://icd.who.int/browse10/2019/en#/'
        },
        {
            id              => 'ncit',
            name            => 'NCI Thesaurus',
            url             => 'http://purl.obolibrary.org/obo/ncit.owl',
            version         => '22.03d',
            namespacePrefix => 'NCIT',
            iriPrefix       => 'http://purl.obolibrary.org/obo/NCIT_'
        },
        {
            id              => 'athena-ohdsi',
            name            => 'Athena-OHDSI',
            url             => 'https://athena.ohdsi.org',
            version         => 'v5.3.1',
            namespacePrefix => 'OHDSI',
            iriPrefix       => 'http://www.fakeurl.com/OHDSI_'
        },
        {
            id              => 'hp',
            name            => 'Human Phenotype Ontology',
            url             => 'http://purl.obolibrary.org/obo/hp.owl',
            version         => '2023-04-05',
            namespacePrefix => 'HP',
            iriPrefix       => 'http://purl.obolibrary.org/obo/HP_'
        },
        {
            id              => 'omim',
            name            => 'Online Mendelian Inheritance in Man',
            url             => 'https://www.omim.org',
            version         => '2023-05-22',
            namespacePrefix => 'OMIM',
            iriPrefix       => 'http://omim.org/entry/'
        },
        {
            id   => 'cdisc-terminology',
            name => 'CDISC Terminology',
            url  =>
'https://www.cdisc.org/standards/terminology/controlled-terminology',
            version         => '2023-01-24',
            namespacePrefix => 'CDISC',
            iriPrefix       => 'http://www.fakeurl.com/CDISC_'
        }
    ];
    return {
        created                  => iso8601_time(),
        createdBy                => $username,
        submittedBy              => $username,
        phenopacketSchemaVersion => '2.0',
        resources                => $resources,
        externalReferences       => [
            {
                id        => 'PMID: 26262116',
                reference =>
                  'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4815923',
                description =>
'Observational Health Data Sciences and Informatics (OHDSI): Opportunities for Observational Researchers'
            }
        ]
    };
}

1;
