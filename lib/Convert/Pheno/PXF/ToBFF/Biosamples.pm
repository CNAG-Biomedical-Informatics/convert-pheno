package Convert::Pheno::PXF::ToBFF::Biosamples;

use strict;
use warnings;
use autodie;

use Exporter 'import';

use Convert::Pheno::Utils::Default qw(get_defaults);

our @EXPORT_OK = qw(extract_pxf_biosamples map_pxf_to_biosample);

my $DEFAULT = get_defaults();

sub extract_pxf_biosamples {
    my ( $self, $phenopacket, $individual_id ) = @_;

    return []
      unless exists $phenopacket->{biosamples}
      && ref( $phenopacket->{biosamples} ) eq 'ARRAY';

    my @biosamples;
    for my $biosample ( @{ $phenopacket->{biosamples} } ) {
        push @biosamples,
          map_pxf_to_biosample( $self, $biosample, $individual_id );
    }

    return \@biosamples;
}

sub map_pxf_to_biosample {
    my ( $self, $source, $individual_id ) = @_;

    my %biosample = %{$source};
    _normalize_biosample_aliases( \%biosample );

    my $mapped = {
        id             => $biosample{id},
        individualId   => $biosample{individualId} // $individual_id,
        biosampleStatus =>
          $biosample{materialSample} // $DEFAULT->{ontology_term},
        sampleOriginType =>
          $biosample{sampleType} // $DEFAULT->{ontology_term},
    };

    if ( exists $biosample{timeOfCollection} ) {
        my $collection_date = _map_collection_date( $biosample{timeOfCollection} );
        my $collection_moment =
          _map_collection_moment( $biosample{timeOfCollection} );

        $mapped->{collectionDate}   = $collection_date if defined $collection_date;
        $mapped->{collectionMoment} = $collection_moment if defined $collection_moment;
    }

    $mapped->{diagnosticMarkers}     = $biosample{diagnosticMarkers}
      if exists $biosample{diagnosticMarkers};
    $mapped->{histologicalDiagnosis} = $biosample{histologicalDiagnosis}
      if exists $biosample{histologicalDiagnosis};
    $mapped->{notes} = $biosample{description}
      if exists $biosample{description};
    $mapped->{pathologicalStage} = $biosample{pathologicalStage}
      if exists $biosample{pathologicalStage};
    $mapped->{pathologicalTnmFinding} = $biosample{pathologicalTnmFinding}
      if exists $biosample{pathologicalTnmFinding};
    $mapped->{phenotypicFeatures} = _map_phenotypic_features( $biosample{phenotypicFeatures} )
      if exists $biosample{phenotypicFeatures};
    $mapped->{sampleOriginDetail} = $biosample{sampledTissue}
      if exists $biosample{sampledTissue};
    $mapped->{sampleProcessing} = $biosample{sampleProcessing}
      if exists $biosample{sampleProcessing};
    $mapped->{sampleStorage} = $biosample{sampleStorage}
      if exists $biosample{sampleStorage};
    $mapped->{tumorGrade} = $biosample{tumorGrade}
      if exists $biosample{tumorGrade};
    $mapped->{tumorProgression} = $biosample{tumorProgression}
      if exists $biosample{tumorProgression};
    $mapped->{measurements} = _map_measurements( $biosample{measurements} )
      if exists $biosample{measurements};
    $mapped->{obtentionProcedure} = _map_procedure( $biosample{procedure} )
      if exists $biosample{procedure};

    my $extra = _build_info_payload( \%biosample );
    $mapped->{info} = { phenopacket => $extra } if %{$extra};

    return $mapped;
}

sub _normalize_biosample_aliases {
    my ($biosample) = @_;

    my %alias = (
        individual_id          => 'individualId',
        derived_from_id        => 'derivedFromId',
        sampled_tissue         => 'sampledTissue',
        sample_type            => 'sampleType',
        phenotypic_features    => 'phenotypicFeatures',
        time_of_collection     => 'timeOfCollection',
        histological_diagnosis => 'histologicalDiagnosis',
        tumor_progression      => 'tumorProgression',
        tumor_grade            => 'tumorGrade',
        pathological_stage     => 'pathologicalStage',
        pathological_tnm_finding => 'pathologicalTnmFinding',
        diagnostic_markers       => 'diagnosticMarkers',
        material_sample          => 'materialSample',
        sample_processing        => 'sampleProcessing',
        sample_storage           => 'sampleStorage',
    );

    for my $source_key ( keys %alias ) {
        my $target_key = $alias{$source_key};
        next unless exists $biosample->{$source_key};
        next if exists $biosample->{$target_key};
        $biosample->{$target_key} = delete $biosample->{$source_key};
    }

    return 1;
}

sub _map_collection_date {
    my ($time) = @_;
    return unless defined $time;

    return substr( $time->{timestamp}, 0, 10 )
      if ref($time) eq 'HASH' && exists $time->{timestamp};

    return substr( $time->{interval}{start}, 0, 10 )
      if ref($time) eq 'HASH'
      && exists $time->{interval}
      && ref( $time->{interval} ) eq 'HASH'
      && exists $time->{interval}{start};

    return;
}

sub _map_collection_moment {
    my ($time) = @_;
    return unless defined $time && ref($time) eq 'HASH';

    return $time->{age}{iso8601duration}
      if exists $time->{age}
      && ref( $time->{age} ) eq 'HASH'
      && exists $time->{age}{iso8601duration};

    return;
}

sub _map_phenotypic_features {
    my ($features) = @_;
    return unless ref($features) eq 'ARRAY';

    my @mapped;
    for my $feature ( @{$features} ) {
        next unless ref($feature) eq 'HASH';

        my %mapped = %{$feature};
        $mapped{featureType} = delete $mapped{type} if exists $mapped{type};

        if ( exists $mapped{evidence} && ref( $mapped{evidence} ) eq 'ARRAY' ) {
            for my $evidence ( @{ $mapped{evidence} } ) {
                next unless ref($evidence) eq 'HASH';
                $evidence->{reference}{notes} = delete $evidence->{reference}{description}
                  if exists $evidence->{reference}
                  && ref( $evidence->{reference} ) eq 'HASH'
                  && exists $evidence->{reference}{description}
                  && !exists $evidence->{reference}{notes};
            }
        }

        push @mapped, \%mapped;
    }

    return \@mapped;
}

sub _map_measurements {
    my ($measurements) = @_;
    return unless ref($measurements) eq 'ARRAY';

    my @mapped;
    for my $measurement ( @{$measurements} ) {
        next unless ref($measurement) eq 'HASH';

        my %mapped = %{$measurement};
        $mapped{assayCode}        = delete $mapped{assay} if exists $mapped{assay};
        $mapped{measurementValue} = delete $mapped{value} if exists $mapped{value};
        $mapped{measurementValue} = delete $mapped{complexValue}
          if !exists $mapped{measurementValue} && exists $mapped{complexValue};
        $mapped{observationMoment} = delete $mapped{timeObserved}
          if exists $mapped{timeObserved};
        $mapped{procedure} = _map_procedure( $mapped{procedure} )
          if exists $mapped{procedure};

        push @mapped, \%mapped;
    }

    return \@mapped;
}

sub _map_procedure {
    my ($procedure) = @_;
    return unless ref($procedure) eq 'HASH';

    my %mapped = %{$procedure};
    $mapped{procedureCode} = delete $mapped{code} if exists $mapped{code};

    if ( exists $mapped{performed} ) {
        my $performed = delete $mapped{performed};

        if ( ref($performed) eq 'HASH' ) {
            $mapped{ageAtProcedure} = $performed->{age}
              if exists $performed->{age};
            $mapped{dateOfProcedure} = substr( $performed->{timestamp}, 0, 10 )
              if exists $performed->{timestamp};
        }
    }

    return \%mapped;
}

sub _build_info_payload {
    my ($biosample) = @_;

    my %info;
    for my $key (
        qw(
          derivedFromId
          files
          taxonomy
          timeOfCollection
          procedure
          measurements
          description
          sampledTissue
          sampleType
          materialSample
          phenotypicFeatures
          pathologicalStage
          pathologicalTnmFinding
          diagnosticMarkers
          histologicalDiagnosis
          tumorProgression
          tumorGrade
          sampleProcessing
          sampleStorage
        )
      )
    {
        $info{$key} = $biosample->{$key} if exists $biosample->{$key};
    }

    return \%info;
}

1;
