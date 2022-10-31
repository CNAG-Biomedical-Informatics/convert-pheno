package Convert::Pheno::CDISC;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Data::Dumper;
use Exporter 'import';
our @EXPORT = qw(cdisc2redcap_longitudinal);
$Data::Dumper::Sortkeys = 1;

###############
###############
#  CDISC2BFF  #
###############
###############

sub do_cdisc2bff {

    my ( $self, $participant ) = @_;

#    ####################################
#    # START MAPPING TO BEACON V2 TERMS #
#    ####################################
#    my $individual;
#
#    # Get cursors for 1D terms
#    my $person = $participant->{PERSON};
#
#    # $participant = input data
#    # $person = cursor to $participant->PERSON
#    # $individual = output data
#
# # ABOUT REQUIRED PROPERTIES
# # 'id' and 'sex' are required properties in <individuals> entry type
# # 'person_id' must exist at this point otherwise it would have not been created
# # Premature return
#    return
#      unless ( exists $person->{gender_concept_id}
#        && $person->{gender_concept_id} ne '' );
#
#
#    ##################################
#    # END MAPPING TO BEACON V2 TERMS #
#    ##################################
#
#    return $individual;
}

sub cdisc2redcap_longitudinal {

    # We're taking advantage that REDCap uses the same key, just changes the value
    # Unlike OMOP_CDM that can change the whole row (multiple keys and values)
    my $data = shift;

    # We take $subject information from the nested data structure
    my $subjects = $data->{ODM}{ClinicalData}{SubjectData};

    # Now we iteratte over the array of subjects
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
