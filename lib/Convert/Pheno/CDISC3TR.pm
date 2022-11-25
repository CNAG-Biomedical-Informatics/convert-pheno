package Convert::Pheno::CDISC3TR;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Data::Dumper;
use Convert::Pheno::REDCap3TR;
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

    # We take $subject information from the nested data structure
    my $subjects = $data->{ODM}{ClinicalData}{SubjectData};

    # Now we iterate over the array of subjects
    my $individuals = [];
    for my $subject ( @{$subjects} ) {

        # The data in CDISC-ODM  has the following hierarchy
        # StudyEventData->'-redcap:UniqueEventName'->FormData->ItemGroupData->ItemData

        # StudyEventData
        for my $StudyEventData ( @{ $subject->{'StudyEventData'} } ) {

            # We'll store the new data on $individual
            my $individual = {
                study_id          => $subject->{'-SubjectKey'},
                redcap_event_name =>
                  $StudyEventData->{'-redcap:UniqueEventName'}
            };

            # FormData
            for my $FormData ( @{ $StudyEventData->{FormData} } ) {

                # ItemGroupData
                for my $ItemGroupData ( @{ $FormData->{ItemGroupData} } ) {

                    # The elements can arrive as {} or []
                    # Both will be loaded as []
                    if ( ref $ItemGroupData->{ItemData} eq ref [] ) {
                        for my $ItemData ( @{ $ItemGroupData->{ItemData} } ) {
                            $individual->{ $ItemData->{'-ItemOID'} } =
                              $ItemData->{'-Value'};
                        }
                    }
                    else {
                        # Converting from hash to 1-subject array
                        $individual->{ $ItemGroupData->{ItemData}{'-ItemOID'} }
                          = $ItemGroupData->{ItemData}{'-Value'};
                    }
                }
            }
            push @{$individuals}, $individual;
        }
    }
    return $individuals;
}

sub _cdisc2redcap_longitudinal {

    ##############
    # Deprecated #
    ##############

    # This sobroutine was built to store longitudinal data as an array
    # Unfortunately, there is no way to add longitudinal info (redcap_event) on Beacon v2

    my $data = shift;

    # We take $subject information from the nested data structure
    my $subjects = $data->{ODM}{ClinicalData}{SubjectData};

    # Now we iterate over the array of subjects
    my $individuals = [];
    for my $subject ( @{$subjects} ) {

        # We'll use $subject->{'-SubjectKey'} = study_id to form the 1D of the hash
        my $study_id = $subject->{'-SubjectKey'};
        my $key      = 'study_id' . ':' . $study_id;

        # We'll store the new data on $individual
        my $individual = {};

        # The data in CDISC-ODM  has the following hierarchy
        # StudyEventData->'-redcap:UniqueEventName'->FormData->ItemGroupData->ItemData

        # StudyEventData
        for my $StudyEventData ( @{ $subject->{'StudyEventData'} } ) {
            my $UniqueEventName = $StudyEventData->{'-redcap:UniqueEventName'};

            # FormData
            for my $FormData ( @{ $StudyEventData->{FormData} } ) {

                # ItemGroupData
                for my $ItemGroupData ( @{ $FormData->{ItemGroupData} } ) {

                    # The elements can arrive as {} or []
                    # Both will be loaded as []
                    if ( ref $ItemGroupData->{ItemData} eq ref [] ) {
                        for my $ItemData ( @{ $ItemGroupData->{ItemData} } ) {
                            push
                              @{ $individual->{$key}{ $ItemData->{'-ItemOID'} }
                              }, { $UniqueEventName => $ItemData->{'-Value'} };
                        }
                    }
                    else {
                        # Converting from hash to 1-subject array
                        $individual->{$key}
                          { $ItemGroupData->{ItemData}{'-ItemOID'} } = [
                            {
                                $UniqueEventName =>
                                  $ItemGroupData->{ItemData}{'-Value'}
                            }
                          ];
                    }
                }
            }
        }
        push @{$individuals}, $individual;

        #print Dumper $individual;
    }
    return $individuals;
}

1;
