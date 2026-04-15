package Convert::Pheno::OMOP::ToBFF::Biosamples;

use strict;
use warnings;
use autodie;

use Exporter 'import';
use Convert::Pheno::Mapping::Shared qw(get_age_from_date_and_birthday map2ohdsi);
use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(extract_participant_biosamples map_specimen_to_biosample);

my $DEFAULT = get_defaults();

sub extract_participant_biosamples {
    my ( $self, $participant, $individual ) = @_;
    my $table = 'SPECIMEN';

    return []
      unless exists $participant->{$table}
      && ref( $participant->{$table} ) eq 'ARRAY';

    my $individual_id =
        defined $individual
      && ref($individual) eq 'HASH'
      && defined $individual->{id}
      ? $individual->{id}
      : _stringify_if_defined( $participant->{PERSON}{person_id} );

    my @biosamples;
    for my $specimen ( @{ $participant->{$table} } ) {
        push @biosamples,
          map_specimen_to_biosample( $self, $specimen, $participant->{PERSON}, $individual_id );
    }

    return \@biosamples;
}

sub map_specimen_to_biosample {
    my ( $self, $specimen, $person, $individual_id ) = @_;
    my $ohdsi_dict = $self->{data_ohdsi_dict};

    my $biosample = {
        id               => _stringify_if_defined( $specimen->{specimen_id} ),
        biosampleStatus  => $DEFAULT->{ontology_term},
        sampleOriginType => _map_concept_or_default(
            $self,
            $ohdsi_dict,
            $specimen->{specimen_concept_id},
        ),
        info => {
            SPECIMEN => {
                OMOP_columns => $specimen,
            },
        },
    };
    $biosample->{individualId} = $individual_id if defined $individual_id;

    if ( _has_value( $specimen->{specimen_date} ) ) {
        $biosample->{collectionDate} = $specimen->{specimen_date};

        my $collection_moment = get_age_from_date_and_birthday(
            {
                date      => $specimen->{specimen_date},
                birth_day => $person->{birth_datetime},
            }
        );
        $biosample->{collectionMoment} = $collection_moment
          if defined $collection_moment;
    }

    my $sample_origin_detail = _map_concept(
        $self,
        $ohdsi_dict,
        $specimen->{anatomic_site_concept_id},
    );
    $biosample->{sampleOriginDetail} = $sample_origin_detail
      if defined $sample_origin_detail;

    my $histological_diagnosis = _map_concept(
        $self,
        $ohdsi_dict,
        $specimen->{disease_status_concept_id},
    );
    $biosample->{histologicalDiagnosis} = $histological_diagnosis
      if defined $histological_diagnosis;

    $biosample->{notes} = $specimen->{specimen_source_value}
      if _has_value( $specimen->{specimen_source_value} );

    return $biosample;
}

sub _map_concept_or_default {
    my ( $self, $ohdsi_dict, $concept_id ) = @_;
    my $mapped = _map_concept( $self, $ohdsi_dict, $concept_id );
    return defined $mapped ? $mapped : $DEFAULT->{ontology_term};
}

sub _map_concept {
    my ( $self, $ohdsi_dict, $concept_id ) = @_;
    return unless _has_concept_id($concept_id);

    return map2ohdsi(
        {
            ohdsi_dict => $ohdsi_dict,
            concept_id => $concept_id,
            self       => $self,
        }
    );
}

sub _has_concept_id {
    my ($value) = @_;
    return 0 unless _has_value($value);
    return 0 if $value =~ /\A0+\z/;
    return 1;
}

sub _has_value {
    my ($value) = @_;
    return 0 unless defined $value;
    return 0 if ref $value;
    return 0 if $value eq q{};
    return 0 if $value eq '\\N';
    return 1;
}

sub _stringify_if_defined {
    my ($value) = @_;
    return unless defined $value;
    return qq{$value};
}

1;
