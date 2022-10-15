package Convert::Pheno::BFF;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Convert::Pheno::Mapping;
use Convert::Pheno::PXF;
use Exporter 'import';
our @EXPORT = qw(do_bff2pxf);

my $DEFAULT_timestamp = '0000-01-01T00:00:00Z';

#############
#############
#  BFF2PXF  #
#############
#############

sub do_bff2pxf {

    my ( $self, $data ) = @_;

    # Premature return
    return unless defined($data);

    #########################################
    # START MAPPING TO PHENOPACKET V2 TERMS #
    #########################################

# We need to shuffle a bit some Beacon v2 properties to be Phenopacket compliant
# https://phenopacket-schema.readthedocs.io/en/latest/phenopacket.html
    my $pxf;

    # ==
    # id
    # ==

    $pxf->{id} = $self->{test} ? undef : 'phenopacket_id.' . randStr(8);

    # =======
    # subject
    # =======

    $pxf->{subject} = {
        id  => $data->{id},
        #alternateIds => [],
        #_age => $data->{info}{age}
        #dateOfBirth => undef, 
        #timeAtLastEncounter => {},
        vitalStatus => 'ALIVE', #["UNKNOWN_STATUS", "ALIVE", "DECEASED"]
        sex => uc( $data->{sex}{label} ),
        #karyotypicSex => undef , # ["UNKNOWN_KARYOTYPE", "XX", "XY", "XO", "XXY","XXX","XXYY", "XXXY", "XXXX", "XYY", "OTHER_KARYOTYPE"]
        #taxonomy => {}
        #_age => $data->{info}{age}
    };

    # ===================
    # phenotypic_features
    # ===================

    $pxf->{phenotypicFeatures} = [
        map {
            {
                type => $_->{featureType}

                  #_notes => $_->{notes}
            }
        } @{ $data->{phenotypicFeatures} }
      ]
      if defined $data->{phenotypicFeatures};

    # ============
    # measurements
    # ============

    $pxf->{measurements} = [
        map {
            {
                assay        => $_->{assayCode},
                timeObserved => exists $_->{date} ? $_->{date} : undef,
                value        => $_->{measurementValue}
            }
        } @{ $data->{measures} }
      ]
      if defined $data->{measures};   # Only 1 element at $_->{measurementValue}

    # ==========
    # biosamples
    # ==========

    # ===============
    # interpretations
    # ===============

    #$data->{interpretation} = {};

    # ========
    # diseases
    # ========

    $pxf->{diseases} =
      [ map { { term => $_->{diseaseCode}, onset => $_->{ageOfOnset} } }
          @{ $data->{diseases} } ];

    # ===============
    # medical_actions
    # ===============

    # **** procedures ****
    my @procedures = map {
        {
            procedure => {
                code      => $_->{procedureCode},
                performed => {
                    timestamp => exists $_->{dateOfProcedure}
                    ? _map2iso8601( $_->{dateOfProcedure} )
                    : $DEFAULT_timestamp
                }
            }
        }
    } @{ $data->{interventionsOrProcedures} };

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
    } @{ $data->{treatments} };

    # Load
    push @{ $pxf->{medicalActions} }, @procedures if @procedures;
    push @{ $pxf->{medicalActions} }, @treatments if @treatments;

    # =====
    # files
    # =====

    # =========
    # meta_data
    # =========

    # Depending on the origion (redcap) , _info and resources may exist
    $pxf->{metaData} =
        $self->{test}                  ? undef
      : exists $data->{info}{metaData} ? $data->{info}{metaData}
      :                                  get_metaData();

    #######################################
    # END MAPPING TO PHENOPACKET V2 TERMS #
    #######################################

    return $pxf;
}
1;
