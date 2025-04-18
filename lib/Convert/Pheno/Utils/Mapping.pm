package Convert::Pheno::Utils::Mapping;

use strict;
use warnings;
use autodie;
use feature qw(say);
use utf8;
use Data::Dumper;
use JSON::XS;
use Time::HiRes qw(gettimeofday);
use POSIX       qw(strftime);
use DateTime::Format::ISO8601;
use Scalar::Util qw(looks_like_number);
use List::Util   qw(first);
use Cwd          qw(cwd);
use Sys::Hostname;
use Convert::Pheno::DB::SQLite;
use Convert::Pheno::Utils::Default qw(get_defaults);
use Exporter 'import';
use open qw(:std :encoding(UTF-8));

our @EXPORT =
  qw(map_ontology_term dotify_and_coerce_number get_current_utc_iso8601_timestamp map_iso8601_date2timestamp map_iso8601_timestamp2date get_date_component map_reference_range map_reference_range_csv map_age_range map2redcap_dict map2ohdsi convert2boolean get_age_from_date_and_birthday get_date_at_age generate_random_alphanumeric_string map_operator_concept_id map_info_field map_omop_visit_occurrence convert_date_to_iso8601 validate_format get_metaData get_info merge_omop_tables convert_label_to_days string2number number2string);

my $DEFAULT = get_defaults();
use constant DEVEL_MODE => 0;

# Global hash
my %SEEN = ();

#############################
#############################
#  HELPER SUBS FOR MAPPING  #
#############################
#############################

sub map_ontology_term {
    my ($arg)    = @_;
    my $query    = $arg->{query};
    my $ontology = $arg->{ontology};
    my $self     = $arg->{self};

    # 1) Skip pure numbers
    return $DEFAULT->{ontology_term} if looks_like_number($query);

    # 2) If already an object, assume pre‑mapped
    return $query if ref $query eq 'HASH';

    # 3) Fast return on cache hit
    if ( exists $SEEN{$ontology}{$query} ) {
        say "Skipping searching for <$query> in <$ontology> (cached)"
          if DEVEL_MODE;
        return $SEEN{$ontology}{$query};
    }

    # 4) --ohdsi-db
    if ( $ontology eq 'ohdsi' && !$self->{ohdsi_db} ) {

        #If -iomop and term not found in RAM <CONCEPT> die unless --ohdsi-db
        if ( $self->{method} =~ /^omop2bff/ ) {
            die "Could not find concept_id:<$query> in provided CONCEPT table. "
              . "Use --ohdsi-db to enable Athena‑OHDSI lookup.\n";
        }

        # Any search that involves 'ohdsi' as an ontology (e.g., mapping file)
        else {
            die "You have to use --ohdsi-db to perform Athena‑OHDSI lookups.\n";
        }
    }

    # 5) Perform the lookup
    say "Searching for <$query> in <$ontology>…" if DEVEL_MODE;
    my ( $id, $label, $concept_id ) = get_ontology_terms(
        {
            sth_column_ref         => $self->{sth}{$ontology}{ $arg->{column} },
            query                  => $query,
            ontology               => $ontology,
            databases              => $self->{databases},
            column                 => $arg->{column},
            search                 => $self->{search},
            text_similarity_method => $self->{text_similarity_method},
            min_text_similarity_score => $self->{min_text_similarity_score},
            levenshtein_weight        => $self->{levenshtein_weight},
        }
    );

    # 6) Store in cache
    my $entry =
      $arg->{require_concept_id}
      ? { id => $id, label => $label, concept_id => $concept_id }
      : { id => $id, label => $label };

    $SEEN{$ontology}{$query} = $entry;

    # 7) Return (with optional hidden‐label)
    return $arg->{print_hidden_labels}
      ? { %$entry, _label => $query }
      : $entry;
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

sub get_current_utc_iso8601_timestamp {

    # Standard modules (gmtime()===>Coordinated Universal Time(UTC))
    # NB: The T separates the date portion from the time-of-day portion.
    #     The Z on the end means UTC (that is, an offset-from-UTC of zero hours-minutes-seconds).
    #     - The Z is pronounced “Zulu”.
    my $now = time();
    return strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime($now) );
}

sub map_iso8601_date2timestamp {
    my $iso_str = shift;

    # Parse the ISO string into a DateTime object
    $iso_str =~ s/ /T/;
    my $dt = DateTime::Format::ISO8601->parse_datetime($iso_str);

    # Format it to the standardized ISO8601 timestamp,
    # ensuring that if no time was provided, a default is used.
    return $dt->strftime('%Y-%m-%dT%H:%M:%SZ');
}

sub map_iso8601_timestamp2date {
    my $iso_str = shift;
    $iso_str =~ s/\s+/T/;

    # split on 'T' and take the date portion
    my ($date) = split /T/, $iso_str;
    return $date;
}

sub get_date_component {
    my ( $date, $component ) = @_;
    $component //= 'year';
    $date =~ s/T.*//;    # get rid of 'T00:00:00Z'

    my @parts   = split /-/, $date;
    my %indexes = ( year => 0, month => 1, day => 2 );

    # Return the requested component if valid; otherwise, warn and return the year.
    return exists $indexes{$component}
      ? $parts[ $indexes{$component} ]
      : do {
        warn
"Invalid component <$component> requested. Returning year by default.\n";
        $parts[ $indexes{'year'} ];
      };
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

    # NB1: Here we don't win any speed over using %SEEN as ...
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

sub get_age_from_date_and_birthday {
    my $arg          = shift;
    my $birth_date   = $arg->{birth_day} or return;
    my $current_date = $arg->{date}      or return;

    # Assuming both dates are in a format like "YYYY-MM-DD" (or with spaces instead of a dash separator for the birth date)
    # Split the dates into year, month, and day.
    my ( $birth_year, $birth_month, $birth_day ) = split /[-\s]+/, $birth_date;
    my ( $current_year, $current_month, $current_day ) = split /-/,
      $current_date;

    # Calculate age based on year difference.
    my $age = $current_year - $birth_year;

    # If the current month/day is before the birthday month/day, subtract one year.
    if ( $current_month < $birth_month
        or ( $current_month == $birth_month && $current_day < $birth_day ) )
    {
        $age--;
    }

    # Return the age in ISO8601 duration format (e.g. "P31Y").
    return "P${age}Y";
}

sub get_date_at_age {
    my ( $duration_iso, $birthdate_iso ) = @_;

    # Parse the birth date using ISO8601 format.
    my $birthdate = DateTime::Format::ISO8601->parse_datetime($birthdate_iso);

    # Here we only handle durations expressed solely in years.
    # For a string like "P31Y", extract the number 31.
    my $years;
    if ( $duration_iso =~ /^P(\d+)Y/ ) {
        $years = $1;
    }
    else {
        warn
"Unsupported duration format: $duration_iso. Only durations in full years (P<number>Y) are supported.";
    }

    # Create a duration object for the extracted number of years.
    my $duration = DateTime::Duration->new( years => $years );

    # Add the duration to the birth date.
    my $date_at_age = $birthdate->clone->add_duration($duration);

    # Return the result in ISO format (YYYY-MM-DD)
    return $date_at_age->ymd;
}

sub generate_random_alphanumeric_string {

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
    my $start_date = map_iso8601_date2timestamp( $hashref->{visit_start_date} );
    my $end_date   = map_iso8601_date2timestamp( $hashref->{visit_end_date} );
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

sub convert_date_to_iso8601 {
    my $date = shift // '';

    # Trim any accidental whitespace
    $date =~ s/^\s+|\s+$//g;

    # Return default if input is empty
    return '1900-01-01' if $date eq '';

    # If already in ISO format (YYYY-MM-DD), return as-is
    if ( $date =~ /^\d{4}-\d{2}-\d{2}$/ ) {
        return $date;
    }

    # If dot-separated format with four-digit first element (YYYY.MM.DD)
    if ( $date =~ /^(\d{4})\.(\d{2})\.(\d{2})$/ ) {
        return "$1-$2-$3";
    }

    # If dot-separated format with two-digit first element (DD.MM.YYYY)
    if ( $date =~ /^(\d{2})\.(\d{2})\.(\d{4})$/ ) {
        return "$3-$2-$1";
    }

    # Optionally, handle any other unexpected format gracefully
    warn "Invalid date format: $date";
}

sub is_multidimensional {
    return ref shift ? 1 : 0;
}

sub validate_format {
    my ( $data, $format ) = @_;
    return ( $format eq 'pxf' )
      ? !!( exists $data->{subject} )
      : !( exists $data->{subject} );
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
        created                  => get_current_utc_iso8601_timestamp(),
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

sub merge_omop_tables {
    my $individuals = shift;    # Expect an arrayref of individual OMOP structures
    die "Expected an array reference" unless ref($individuals) eq 'ARRAY';

    my %merged;
    foreach my $ind (@$individuals) {

        # Ensure each individual record is a hashref.
        next unless ref($ind) eq 'HASH';

        # For each table in this individual...
        foreach my $table ( keys %$ind ) {

            # If the table is stored as an arrayref, merge its rows.
            if ( ref( $ind->{$table} ) eq 'ARRAY' ) {
                push @{ $merged{$table} }, @{ $ind->{$table} };
            }
            else {
                # If it's a single hash (one row), add it as a single element.
                push @{ $merged{$table} }, $ind->{$table};
            }
        }
    }
    return \%merged;
}

sub convert_label_to_days {
    my ( $label, $count ) = @_;

    # return undef on missing args
    return undef
      unless defined $label && defined $count && looks_like_number($count);

    my $key = lc $label;

    # normalize plural to singular
    $key =~ s/s$//;

    my %mult = (
        day   => 1,
        week  => 7,
        month => 30,
        year  => 365,
    );

    # lookup multiplier
    my $factor = $mult{$key};
    return undef unless defined $factor;

    return $factor * $count;
}

# hex‑encoding the bytes, then parsing that hex as a BigInt.
sub string2number {
    my $str = shift;

    # Do nothing if we already have integer
    return $str if is_strict_integer($str);

    # 1) turn "Hello" into "48656c6c6f"
    my $hex = unpack( 'H*', $str ); 

    # 2) parse that hex as a BigInt 
    my $big = Math::BigInt->from_hex("0x$hex");

    # 3) return its decimal string 
    return $big->bstr;
}

sub is_strict_integer {
    my ($val) = @_;
    return 0 unless looks_like_number($val);
    return $val == int($val);
}

# Turn the decimal BigInt back into the original string
sub number2string {
    my $num = shift;

    # 1) lift into a BigInt
    my $big = Math::BigInt->new($num);

    # 2) get back the hex digits, e.g. "0x48656c6c6f"
    my $hex = $big->as_hex;
    
    # 3) strip the "0x" and unpack back into raw bytes
    $hex =~ s/^0[xX]//;
    return pack( 'H*', $hex );
}

1;
