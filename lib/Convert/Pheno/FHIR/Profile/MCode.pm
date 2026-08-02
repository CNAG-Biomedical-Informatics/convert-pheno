package Convert::Pheno::FHIR::Profile::MCode;

use strict;
use warnings;

use Exporter 'import';

use Convert::Pheno::FHIR::Util qw(
  codeable_concept_to_term
  resolve_reference
);

our @EXPORT_OK = qw(
  condition_stage
  detected_profile_metadata
  has_profile
);

my $CANONICAL = 'http://hl7.org/fhir/us/mcode';
my $VERSION   = '4.0.0';
my $PROFILE_PREFIX = "$CANONICAL/StructureDefinition/";

sub has_profile {
    my ( $resource, $profile_name ) = @_;
    return 0 unless ref($resource) eq 'HASH';

    my $wanted = $PROFILE_PREFIX . $profile_name;
    for my $profile ( @{ _profile_urls($resource) } ) {
        next if ref($profile);
        my ($canonical) = _supported_profile_identity($profile);
        next unless defined $canonical;
        return 1 if $canonical eq $wanted;
    }

    return 0;
}

sub condition_stage {
    my ( $condition, $resource_index ) = @_;
    return unless has_profile( $condition, 'mcode-primary-cancer-condition' );

    for my $stage ( @{ $condition->{stage} || [] } ) {
        next unless ref($stage) eq 'HASH';

        my $summary = codeable_concept_to_term(
            $stage->{summary},
            'CancerStage',
        );
        return $summary if $summary;

        for my $assessment ( @{ $stage->{assessment} || [] } ) {
            next unless ref($assessment) eq 'HASH';
            my $observation = resolve_reference(
                $resource_index || {},
                $assessment->{reference},
            );
            next unless ref($observation) eq 'HASH'
              && ( $observation->{resourceType} || q{} ) eq 'Observation';

            my $value = codeable_concept_to_term(
                $observation->{valueCodeableConcept},
                'CancerStage',
            );
            return $value if $value;
        }
    }

    return;
}

sub detected_profile_metadata {
    my (@resources) = @_;
    my %profiles;

    for my $resource (@resources) {
        next unless ref($resource) eq 'HASH';
        for my $profile ( @{ _profile_urls($resource) } ) {
            next if ref($profile);
            my ($canonical) = _supported_profile_identity($profile);
            next unless defined $canonical;
            next unless index( $canonical, $PROFILE_PREFIX ) == 0;

            my $name = substr $canonical, length $PROFILE_PREFIX;
            next unless length $name;
            $profiles{$name} = 1;
        }
    }

    return unless keys %profiles;
    return {
        canonical       => $CANONICAL,
        supportedVersion => $VERSION,
        detectedProfiles => [ sort keys %profiles ],
    };
}

sub _supported_profile_identity {
    my ($profile) = @_;
    return if !defined $profile || ref($profile);

    my ( $canonical, $version ) = split /\|/, $profile, 2;
    return if defined $version && $version ne $VERSION;
    return $canonical;
}

sub _profile_urls {
    my ($resource) = @_;
    return [] unless ref( $resource->{meta} ) eq 'HASH';
    return [] unless ref( $resource->{meta}{profile} ) eq 'ARRAY';
    return $resource->{meta}{profile};
}

1;
