package Convert::Pheno::CDISC;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Data::Dumper;
use Convert::Pheno::REDCap;
use Convert::Pheno::Mapping;
use Exporter 'import';
our @EXPORT = qw(do_cdisc2bff cdisc2redcap);
$Data::Dumper::Sortkeys = 1;

###############
###############
#  CDISC2BFF  #
###############
###############

sub do_cdisc2bff {
    my ( $self, $participant ) = @_;
    return do_redcap2bff( $self, $participant );
}

sub cdisc2redcap {
    my $data = shift;

    # Extract subject information from nested data structure
    my $subjects    = $data->{ODM}{ClinicalData}{SubjectData};
    my $individuals = [];

  # The data in CDISC-ODM  has the following hierarchy
  # StudyEventData->'-redcap:UniqueEventName'->FormData->ItemGroupData->ItemData

    # Iterate over each subject
    foreach my $subject ( @{$subjects} ) {
        process_subject( $subject, $individuals );
    }

    return $individuals;
}

#----------------------------------------------------------------------
# Helper subs
#----------------------------------------------------------------------

sub process_subject {
    my ( $subject, $individuals ) = @_;

    # Iterate over StudyEventData for each subject
    foreach my $StudyEventData ( @{ $subject->{'StudyEventData'} } ) {

        # Initialize individual's data structure
        my $individual = {
            study_id          => $subject->{'-SubjectKey'},
            redcap_event_name => $StudyEventData->{'-redcap:UniqueEventName'}
        };

        # Process each Study Event Data
        process_study_event_data( $StudyEventData, $individual );
        push @{$individuals}, $individual;
    }
}

sub process_study_event_data {
    my ( $StudyEventData, $individual ) = @_;

    # Iterate over FormData
    foreach my $FormData ( @{ $StudyEventData->{FormData} } ) {

        # Iterate over ItemGroupData
        foreach my $ItemGroupData ( @{ $FormData->{ItemGroupData} } ) {
            process_item_group_data( $ItemGroupData, $individual );
        }
    }
}

sub process_item_group_data {
    my ( $ItemGroupData, $individual ) = @_;

    # Handle both array and hash structures for ItemData
    my $items =
      ref $ItemGroupData->{ItemData} eq 'ARRAY'
      ? $ItemGroupData->{ItemData}
      : [ $ItemGroupData->{ItemData} ];

    # Iterate over ItemData
    foreach my $ItemData ( @{$items} ) {

        # Store each item in the individual's data
        $individual->{ $ItemData->{'-ItemOID'} } =
          dotify_and_coerce_number( $ItemData->{'-Value'} );
    }
}

1;
