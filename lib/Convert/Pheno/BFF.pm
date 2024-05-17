package Convert::Pheno::BFF;

use strict;
use warnings;
use autodie;
use feature                 qw(say);
use Convert::Pheno::Default qw(get_defaults);
use Convert::Pheno::Mapping;
use Exporter 'import';
our @EXPORT = qw(do_bff2pxf);

my $DEFAULT = get_defaults();

#############
#############
#  BFF2PXF  #
#############
#############

sub do_bff2pxf {

    my ( $self, $bff ) = @_;

    # Premature return
    return unless defined($bff);

    # Validate format
    die "Are you sure that your input is not already a pxf?\n"
      unless validate_format( $bff, 'bff' );

    #########################################
    # START MAPPING TO PHENOPACKET V2 TERMS #
    #########################################

# We need to shuffle a bit some Beacon v2 properties to be Phenopacket compliant
# Order of terms (not alphabetical) taken from:
# - https://phenopacket-schema.readthedocs.io/en/latest/phenopacket.html

    # Initiate PXF structure
    my $pxf;

    # ==
    # id
    # ==

    $pxf->{id} = $self->{test} ? undef : 'phenopacket_id.' . randStr(8);

    # =======
    # subject
    # =======

    $pxf->{subject} = {
        id => $bff->{id},

        #alternateIds => [],
        #_age => $bff->{info}{age}
        #timeAtLastEncounter => {},
        vitalStatus => { status => 'ALIVE' }
        ,    #["UNKNOWN_STATUS", "ALIVE", "DECEASED"]
        sex => uc( $bff->{sex}{label} ),

        #taxonomy => {} ;
        #_age => $bff->{info}{age}
    };

    # Miscellanea
    for (qw(dateOfBirth)) {
        $pxf->{subject}{$_} = $bff->{info}{$_} if exists $bff->{info}{$_};
    }

    # karyotypicSex
    $pxf->{subject}{karyotypicSex} = $bff->{karyotypicSex}
      if exists $bff->{karyotypicSex};

    # ===================
    # phenotypicFeatures
    # ===================

    $pxf->{phenotypicFeatures} = [
        map {
            {
                type     => delete $_->{featureType},
                excluded => delete $_->{excluded}

                  #_notes => $_->{notes}
            }
        } @{ $bff->{phenotypicFeatures} }
      ]
      if defined $bff->{phenotypicFeatures};

    # ============
    # measurements
    # ============
    if ( defined $bff->{measures} ) {
        $pxf->{measurements} = [];    # Initialize as an empty array reference

        for my $measure ( @{ $bff->{measures} } ) {

            # Check if measurementValue hash contain the typedQuantities key
            my $has_typedQuantities =
              exists $measure->{measurementValue}{typedQuantities} ? 1 : 0;

            # Construct the hash
            my $result = { assay => $measure->{assayCode} };

            # Add the complexValue key if typedQuantities was found
            if ($has_typedQuantities) {
                $result->{complexValue} = $measure->{measurementValue};
            }
            else {
                $result->{value} = $measure->{measurementValue};

            }

            # Push the resulting hash onto the pxf measurements array
            push @{ $pxf->{measurements} }, $result;
        }
    }

    # ==========
    # biosamples
    # ==========

    # ===============
    # interpretations
    # ===============

    #$bff->{interpretation} = {};

    # ========
    # diseases
    # ========

    $pxf->{diseases} =
      [ map { { term => $_->{diseaseCode}, onset => $_->{ageOfOnset} } }
          @{ $bff->{diseases} } ];

    # ===============
    # medicalActions
    # ===============

    # **** procedures ****
    my @procedures = map {
        {
            procedure => {
                code      => $_->{procedureCode},
                performed => {
                    timestamp => exists $_->{dateOfProcedure}
                    ? _map2iso8601( $_->{dateOfProcedure} )
                    : $DEFAULT->{timestamp}
                }
            }
        }
    } @{ $bff->{interventionsOrProcedures} };

    # **** treatments ****
    my @treatments = map {
        {
            treatment => {
                agent                 => $_->{treatmentCode},
                routeOfAdministration => $_->{routeOfAdministration},
                doseIntervals         => $_->{doseIntervals}

#performed => { timestamp => exists $_->{dateOfProcedure} ? $_->{dateOfProcedure} : undef}
            }
        }
    } @{ $bff->{treatments} };

    # Load
    push @{ $pxf->{medicalActions} }, @procedures if @procedures;
    push @{ $pxf->{medicalActions} }, @treatments if @treatments;

    # =====
    # files
    # =====

    # =========
    # metaData
    # =========

    # Depending on the origion (redcap) , _info and resources may exist
    $pxf->{metaData} =
        $self->{test}                 ? undef
      : exists $bff->{info}{metaData} ? $bff->{info}{metaData}
      :                                 get_metaData($self);

    # =========
    # exposures
    # =========

# Can't be mapped as Sept-2023 from pxf-tools
# Message type "org.phenopackets.schema.v2.Phenopacket" has no field named "exposures" at "Phenopacket".
#  Available Fields(except extensions): "['id', 'subject', 'phenotypicFeatures', 'measurements', 'biosamples', 'interpretations', 'diseases', 'medicalActions', 'files', 'metaData']" at line 22

    #   $pxf->{exposures} =
    #
    #      [
    #        map {
    #            {
    #                type       => $_->{exposureCode},
    #                occurrence => { timestamp => $_->{date} }
    #            }
    #        } @{ $bff->{exposures} }
    #      ]
    #      if exists $bff->{exposures};

    #######################################
    # END MAPPING TO PHENOPACKET V2 TERMS #
    #######################################

    return $pxf;
}

1;
