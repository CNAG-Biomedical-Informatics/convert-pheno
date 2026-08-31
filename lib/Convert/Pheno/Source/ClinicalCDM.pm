package Convert::Pheno::Source::ClinicalCDM;

use strict;
use warnings;

use Storable qw(dclone);

use Convert::Pheno::Mapping::Shared qw(get_info);
use Convert::Pheno::Source::Result;
use Convert::Pheno::Source::TablePackage qw(load_table_package);

my %PROFILE = (
    i2b2 => {
        label          => 'i2b2',
        person_table   => 'PATIENT_DIMENSION',
        person_keys    => [qw(PATIENT_NUM PATID PATIENT_ID)],
        required       => [qw(PATIENT_DIMENSION OBSERVATION_FACT)],
        concept_table  => 'CONCEPT_DIMENSION',
        concept_key    => 'CONCEPT_CD',
        visit_table    => 'VISIT_DIMENSION',
        visit_keys     => [qw(ENCOUNTER_NUM ENCOUNTERID VISIT_ID)],
        patient_tables => [qw(OBSERVATION_FACT VISIT_DIMENSION)],
    },
    sentinel => {
        label          => 'Sentinel CDM',
        person_table   => 'DEMOGRAPHIC',
        person_keys    => [qw(PATID PATIENT_ID PATIENT_NUM)],
        required       => ['DEMOGRAPHIC'],
        visit_table    => 'ENCOUNTER',
        visit_keys     => [qw(ENCOUNTERID ENCOUNTER_NUM VISIT_ID)],
        patient_tables => [qw(DEATH DIAGNOSIS DISPENSING ENCOUNTER INPATIENT_PHARMACY LAB_RESULT PRESCRIBING PROCEDURE VITAL_SIGNS)],
    },
    pcornet => {
        label          => 'PCORnet CDM',
        person_table   => 'DEMOGRAPHIC',
        person_keys    => [qw(PATID PATIENT_ID PATIENT_NUM)],
        required       => ['DEMOGRAPHIC'],
        visit_table    => 'ENCOUNTER',
        visit_keys     => [qw(ENCOUNTERID ENCOUNTER_NUM VISIT_ID)],
        patient_tables => [qw(CONDITION DEATH DIAGNOSIS DISPENSING ENCOUNTER EXTERNAL_MEDS IMMUNIZATION LAB_RESULT_CM MED_ADMIN OBS_CLIN OBS_GEN PRESCRIBING PROCEDURES VITAL)],
    },
);

sub new {
    my ( $class, $converter, %arg ) = @_;
    my $profile = lc( $arg{profile} // q{} );
    die "Unknown clinical CDM source profile <$profile>\n"
      unless exists $PROFILE{$profile};
    return bless {
        converter => $converter,
        profile   => $profile,
    }, $class;
}

sub load {
    my ($self) = @_;
    my $profile = $self->{profile};
    my $config  = $PROFILE{$profile};
    my $package = load_table_package( $self->{converter}, $profile );
    my $tables  = $package->{tables};

    for my $required ( @{ $config->{required} } ) {
        die "$config->{label} input requires table <$required>\n"
          unless exists $tables->{$required};
    }

    my $records = _group_patients( $tables, $profile, $config );
    my %counts = map { $_ => scalar @{ $tables->{$_} } } sort keys %{$tables};

    return Convert::Pheno::Source::Result->new(
        {
            data      => $records,
            owned     => 1,
            artifacts => {
                profile        => $profile,
                table_counts   => \%counts,
                table_sources  => dclone( $package->{sources} ),
                source_kind    => $package->{kind},
            },
        }
    );
}

sub prepare {
    my ($self) = @_;
    my $converter = $self->{converter};
    my $profile = $self->{profile};
    my $prepared_key = $profile . '_input_prepared';
    my $source_key   = '_' . $profile . '_source_data';
    return 1 if $converter->{$prepared_key} && exists $converter->{data};

    $converter->{$source_key} = $converter->{data}
      if exists $converter->{data} && !exists $converter->{$source_key};
    $converter->{data} = $converter->{$source_key}
      if !exists $converter->{data} && exists $converter->{$source_key};

    my $source = $self->load;
    $source->apply_to($converter);
    $converter->{clinical_cdm_metadata}{$profile} = {
        table_counts  => $source->artifact('table_counts'),
        table_sources => $source->artifact('table_sources'),
        source_kind   => $source->artifact('source_kind'),
    };
    $converter->{convertPheno} ||= get_info($converter);
    $converter->{$prepared_key} = 1;
    return 1;
}

sub _group_patients {
    my ( $tables, $profile, $config ) = @_;
    my $person_table = $config->{person_table};
    my ( %record_for, @order, %concepts );

    if ( $config->{concept_table} && exists $tables->{ $config->{concept_table} } ) {
        for my $row ( @{ $tables->{ $config->{concept_table} } } ) {
            my $code = _first_value( $row, $config->{concept_key} );
            next unless defined $code;
            die "$config->{label} table <$config->{concept_table}> contains duplicate concept <$code>\n"
              if exists $concepts{$code};
            $concepts{$code} = $row if defined $code;
        }
    }

    for my $row ( @{ $tables->{$person_table} } ) {
        my $person_id = _required_identifier(
            $row,
            $config->{person_keys},
            "$config->{label} $person_table",
        );
        die "$config->{label} table <$person_table> contains duplicate patient <$person_id>\n"
          if exists $record_for{$person_id};
        my $record = {
            model     => $profile,
            personId  => $person_id,
            patient   => $row,
            tables    => {},
            visits    => {},
            # Concept metadata is read-only and can be very large in i2b2.
            # Share one index rather than cloning it once per patient.
            concepts  => \%concepts,
        };
        $record_for{$person_id} = $record;
        push @order, $person_id;
    }
    die "$config->{label} table <$person_table> contains no patients\n"
      unless @order;

    if ( exists $tables->{ $config->{visit_table} } ) {
        for my $row ( @{ $tables->{ $config->{visit_table} } } ) {
            my $person_id = _row_person_id( $row, $config->{person_keys} );
            die "$config->{label} table <$config->{visit_table}> row is missing a patient identifier\n"
              unless defined $person_id;
            _require_known_patient( $profile, $config, $person_id, $config->{visit_table}, \%record_for );
            my $visit_id = _first_value( $row, @{ $config->{visit_keys} } );
            next unless defined $visit_id;
            die "$config->{label} table <$config->{visit_table}> contains duplicate encounter <$visit_id> for patient <$person_id>\n"
              if exists $record_for{$person_id}{visits}{$visit_id};
            $record_for{$person_id}{visits}{$visit_id} = $row;
        }
    }

    my %patient_scoped = map { $_ => 1 } @{ $config->{patient_tables} || [] };
    for my $table ( sort keys %{$tables} ) {
        next if $table eq $person_table;
        next if $config->{concept_table} && $table eq $config->{concept_table};

        for my $row ( @{ $tables->{$table} } ) {
            my $person_id = _row_person_id( $row, $config->{person_keys} );
            if ( !defined $person_id ) {
                die "$config->{label} table <$table> row is missing a patient identifier\n"
                  if $patient_scoped{$table};
                next;
            }
            _require_known_patient( $profile, $config, $person_id, $table, \%record_for );
            push @{ $record_for{$person_id}{tables}{$table} }, $row;
        }
    }

    my @records = map { $record_for{$_} } @order;
    for my $index ( 0 .. $#records ) {
        $records[$index]{isFirst} = $index == 0 ? 1 : 0;
    }
    return \@records;
}

sub _require_known_patient {
    my ( $profile, $config, $person_id, $table, $records ) = @_;
    die "$config->{label} table <$table> references unknown patient <$person_id>\n"
      unless exists $records->{$person_id};
    return 1;
}

sub _required_identifier {
    my ( $row, $keys, $context ) = @_;
    my $value = _first_value( $row, @{$keys} );
    die "$context row is missing a patient identifier\n"
      unless defined $value;
    return $value;
}

sub _row_person_id {
    my ( $row, $keys ) = @_;
    return _first_value( $row, @{$keys} );
}

sub _first_value {
    my ( $row, @keys ) = @_;
    for my $key (@keys) {
        next unless exists $row->{$key};
        my $value = $row->{$key};
        next unless defined $value && !ref($value);
        $value =~ s/^\s+|\s+$//g;
        next unless length $value;
        next if $value =~ /\A(?:NULL|\\N|\.)\z/i;
        return $value;
    }
    return;
}

1;
