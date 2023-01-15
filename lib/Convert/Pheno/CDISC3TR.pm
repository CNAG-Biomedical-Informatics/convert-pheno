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

    # uncoverable subroutine
    my $data = shift;    # uncoverable statement
                         # uncoverable statement
     # We take $subject information from the nested data structure # uncoverable statement
    my $subjects =
      $data->{ODM}{ClinicalData}{SubjectData};    # uncoverable statement
                                                  # uncoverable statement
        # Now we iterate over the array of subjects # uncoverable statement
    my $individuals = [];    # uncoverable statement

    for my $subject ( @{$subjects} ) {    # uncoverable statement
                                          # uncoverable statement
         # We'll use $subject->{'-SubjectKey'} = study_id to form the 1D of the hash # uncoverable statement
        my $study_id = $subject->{'-SubjectKey'};       # uncoverable statement
        my $key      = 'study_id' . ':' . $study_id;    # uncoverable statement
                                                        # uncoverable statement
            # We'll store the new data on $individual # uncoverable statement
        my $individual = {};    # uncoverable statement
                                # uncoverable statement
         # The data in CDISC-ODM  has the following hierarchy # uncoverable statement
         # StudyEventData->'-redcap:UniqueEventName'->FormData->ItemGroupData->ItemData # uncoverable statement
         # uncoverable statement
         # StudyEventData # uncoverable statement

        for my $StudyEventData ( @{ $subject->{'StudyEventData'} } )
        {    # uncoverable statement
            my $UniqueEventName =
              $StudyEventData->{'-redcap:UniqueEventName'}
              ;    # uncoverable statement
                   # uncoverable statement
                   # FormData # uncoverable statement
            for my $FormData ( @{ $StudyEventData->{FormData} } )
            {      # uncoverable statement
                   # uncoverable statement
                   # ItemGroupData # uncoverable statement
                for my $ItemGroupData ( @{ $FormData->{ItemGroupData} } )
                {    # uncoverable statement
                     # uncoverable statement
                     # The elements can arrive as {} or [] # uncoverable statement
                     # Both will be loaded as [] # uncoverable statement
                    if ( ref $ItemGroupData->{ItemData} eq ref [] )
                    {    # uncoverable statement
                        for my $ItemData ( @{ $ItemGroupData->{ItemData} } )
                        {    # uncoverable statement
                            push    # uncoverable statement
                              @{
                                $individual->{$key}{ $ItemData->{'-ItemOID'}
                                }    # uncoverable statement
                              },
                              { $UniqueEventName => $ItemData->{'-Value'}
                              };    # uncoverable statement
                        }    # uncoverable statement
                    }    # uncoverable statement
                    else {    # uncoverable statement
                         # Converting from hash to 1-subject array # uncoverable statement
                        $individual->{$key}    # uncoverable statement
                          { $ItemGroupData->{ItemData}{'-ItemOID'} } =
                          [                    # uncoverable statement
                            {                  # uncoverable statement
                                $UniqueEventName =>    # uncoverable statement
                                  $ItemGroupData->{ItemData}
                                  {'-Value'}           # uncoverable statement
                            }    # uncoverable statement
                          ];    # uncoverable statement
                    }    # uncoverable statement
                }    # uncoverable statement
            }    # uncoverable statement
        }    # uncoverable statement
        push @{$individuals}, $individual;    # uncoverable statement
                                              # uncoverable statement
            #print Dumper $individual; # uncoverable statement
    }    # uncoverable statement
    return $individuals;    # uncoverable statement
}    # uncoverable statement

1;
