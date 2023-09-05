package Convert::Pheno::PXF;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Sys::Hostname;
use Cwd qw(cwd abs_path);
use Convert::Pheno::Mapping;
use Exporter 'import';
our @EXPORT = qw(do_pxf2bff get_metaData);

#############
#############
#  PXF2BFF  #
#############
#############

sub do_pxf2bff {

    my ( $self, $data ) = @_;
    my $sth = $self->{sth};

    # *** IMPORTANT ****
    # PXF three top-level elements are usually split in files:
    # - phenopacket.json ( usually - 1 individual per file)
    # - cohort.json (info on mutliple individuals)
    # - family.json (info related to one or multiple individuals).
    # These 3 files dont't contain their respective objects at the root level (/).
    #
    # However, top-elements might be combined into a single file (e.g., pxf.json),
    # as a result, certain files may contain objects for top-level elements:
    # - /phenopacket
    # - /cohort
    # - /family
    #
    # In this context, we only accept top-level phenopackets,
    # while the other two types will be categorized as "info".

    # We create cursors for top-level elements
    # 1 - phenopacket (mandatory)
    my $phenopacket =
      exists $data->{phenopacket} ? $data->{phenopacket} : $data;

    # 2, 3 - /cohort and /family (unlikely)
    # NB: They usually contain info on many individuals and their own files)
    my $cohort = exists $data->{family} ? $data->{cohort} : undef;
    my $family = exists $data->{family} ? $data->{family} : undef;

    # Normalize the hash for medical_actions + medicalActions = medicalActions
    if ( exists $phenopacket->{medical_actions} ) {

        # NB: The delete function returns the value of the deleted key-value pair
        $phenopacket->{medicalActions} = delete $phenopacket->{medical_actions};
    }

    # CNAG files have 'meta_data' nomenclature, but PXF documentation uses 'metaData'
    # We search for both 'meta_data' and 'metaData' and simply display the
    if ( exists $phenopacket->{meta_data} ) {

        # NB: The delete function returns the value of the deleted key-value pair
        $phenopacket->{metaData} = delete $phenopacket->{meta_data};
    }

    # Define defaults
    my $default_date            = '1900-01-01';
    my $default_duration        = 'P999Y';
    my $default_value           = -1;
    my $default_timestamp       = '1900-01-01T00:00:00Z';
    my $default_iso8601duration = { iso8601duration => $default_duration };
    my $default_ontology        = { id => 'NCIT:NA0000', label => 'NA' };
    my $default_quantity        = {
        unit  => $default_ontology,
        value => $default_value
    };

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # *** IMPORTANT ***
    # biosamples => can not be mapped to individuals (is Biosamples)
    # interpretations => does not have equivalent
    # files => idem
    # They will added to {info}

    # NB: In PXF some terms are = []

    my $individual;

    # ========
    # diseases
    # ========

    if ( exists $phenopacket->{diseases} ) {
        for my $pxf_disease ( @{ $phenopacket->{diseases} } ) {
            my $disease = $pxf_disease;    # Ref-copy-only
            $disease->{diseaseCode} = $disease->{term};
            $disease->{ageOfOnset}  = $disease->{onset}
              if exists $disease->{onset};
            $disease->{excluded} =
              ( exists $disease->{negated} || exists $disease->{excluded} )
              ? JSON::XS::true
              : JSON::XS::false;

            # Clean analog terms if exist
            for (qw/term onset/) {
                delete $disease->{$_}
                  if exists $disease->{$_};
            }

            push @{ $individual->{diseases} }, $disease;
        }
    }

    # ========
    # ethnicity
    # ========
    # NA

    # ========
    # exposures
    # ========
    if ( exists $phenopacket->{exposures} ) {
        for my $pxf_exposure ( @{ $phenopacket->{exposures} } ) {
            my $exposure = $pxf_exposure;    # Ref-copy-only
            $exposure->{exposureCode} = $exposure->{type};
            $exposure->{date} =
              substr( $exposure->{occurrence}{timestamp}, 0, 10 );

            # Required properties
            $exposure->{ageAtExposure} = $default_iso8601duration;
            $exposure->{duration}      = $default_duration;
            unless ( exists $exposure->{unit} ) {
                $exposure->{unit} = $default_ontology;
            }

            # Clean analog terms if exist
            for (qw/type occurence/) {
                delete $exposure->{$_}
                  if exists $exposure->{$_};
            }

            push @{ $individual->{exposures} }, $exposure;
        }
    }

    # ================
    # geographicOrigin
    # ================
    # NA

    # ==
    # id
    # ==

    $individual->{id} = $phenopacket->{subject}{id}
      if exists $phenopacket->{subject}{id};

    # ====
    # info
    # ====

    # *** IMPORTANT ***
    # Here we set data that do not fit anywhere else

    # Miscelanea for top-level 'phenopacket'
    for my $term (
        qw (dateOfBirth genes interpretations metaData variants files biosamples pedigree)
      )
    {
        $individual->{info}{phenopacket}{$term} = $phenopacket->{$term}
          if exists $phenopacket->{$term};
    }

    # Miscelanea for top-levels 'cohort' and 'family'
    $individual->{info}{cohort} = $cohort if defined $cohort;
    $individual->{info}{family} = $family if defined $family;

    # =========================
    # interventionsOrProcedures
    # ========================

    if ( exists $phenopacket->{medicalActions} ) {
        for my $action ( @{ $phenopacket->{medicalActions} } ) {
            if ( exists $action->{procedure} ) {
                my $procedure = $action->{procedure};    # Ref-copy-only
                $procedure->{procedureCode} =
                  exists $action->{procedure}{code}
                  ? $action->{procedure}{code}
                  : $default_ontology;
                $procedure->{ageOfProcedure} =
                  exists $action->{procedure}{performed}
                  ? $action->{procedure}{performed}
                  : $default_timestamp;

                # Clean analog terms if exist
                for (qw/code performed/) {

                    delete $procedure->{$_}
                      if exists $procedure->{$_};
                }

                push @{ $individual->{interventionsOrProcedures} }, $procedure;
            }
        }
    }

    # =============
    # karyotypicSex
    # =============
    $individual->{karyotypicSex} = $phenopacket->{subject}{karyotypicSex}
      if exists $phenopacket->{subject}{karyotypicSex};

    # =========
    # measures
    # =========
    if ( exists $phenopacket->{measurements} ) {
        for my $measurement ( @{ $phenopacket->{measurements} } ) {
            my $measure = $measurement;    # Ref-copy-only

            $measure->{assayCode} = $measure->{assay};

            # Process remotely compleValue
            # s/type/quantityType/
            map_complexValue( $measure->{complexValue} )
              if exists $measure->{complexValue};

            # Assign dependeing on PXF
            $measure->{measurementValue} =
                exists $measure->{value}        ? $measure->{value}
              : exists $measure->{complexValue} ? $measure->{complexValue}
              :                                   $default_value;
            $measure->{observationMoment} = $measure->{timeObserved}
              if exists $measure->{timeObserved};

            # Clean analog terms if exist
            for (qw/assay value complexValue/) {
                delete $measure->{$_}
                  if exists $measure->{$_};
            }

            push @{ $individual->{measures} }, $measure;
        }
    }

    # =========
    # pedigrees
    # =========
    # See above {info}{phenopacket}{pedigree} => singular!!!

    # ==================
    # phenotypicFeatures
    # ==================
    if ( exists $phenopacket->{phenotypicFeatures} ) {
        for my $feature ( @{ $phenopacket->{phenotypicFeatures} } ) {
            my $phenotypicFeature = $feature;    # Ref-copy-only

            # *** IMPORTANT ****
            # In v2.0.0 BFF 'evidence' is object but in PXF is array of objects

            $phenotypicFeature->{excluded} =
              (      exists $phenotypicFeature->{negated}
                  || exists $phenotypicFeature->{excluded} )
              ? JSON::XS::true
              : JSON::XS::false,
              $phenotypicFeature->{featureType} = $phenotypicFeature->{type}
              if exists $phenotypicFeature->{type};

            # Clean analog terms if exist
            for (qw/negated type/) {
                delete $phenotypicFeature->{$_}
                  if exists $phenotypicFeature->{$_};
            }

            push @{ $individual->{phenotypicFeatures} }, $phenotypicFeature;
        }
    }

    # ===
    # sex
    # ===

    $individual->{sex} = map_ontology(
        {
            query    => $phenopacket->{subject}{sex},
            column   => 'label',
            ontology => 'ncit',
            self     => $self
        }
      )
      if ( exists $phenopacket->{subject}{sex}
        && $phenopacket->{subject}{sex} ne '' );

    # ==========
    # treatments
    # ==========

    if ( exists $phenopacket->{medicalActions} ) {
        for my $action ( @{ $phenopacket->{medicalActions} } ) {
            if ( exists $action->{treatment} ) {
                my $treatment = $action->{treatment};    # Ref-copy-only
                $treatment->{treatmentCode} =
                  exists $action->{treatment}{agent}
                  ? $action->{treatment}{agent}
                  : $default_ontology;

                # Clean analog terms if exist
                delete $treatment->{agent}
                  if exists $treatment->{agent};

                # doseIntervals needs some parsing
                if ( exists $treatment->{doseIntervals} ) {

                    # Required properties:
                    #   - scheduleFrequency
                    #   - quantity

                    for ( @{ $treatment->{doseIntervals} } ) {

                        # quantity
                        unless ( exists $_->{quantity} ) {
                            $_->{quantity} = $default_quantity;
                        }

                        #scheduleFrequency
                        unless ( exists $_->{scheduleFrequency} ) {
                            $_->{scheduleFrequency} = $default_ontology;
                        }
                    }
                }

                push @{ $individual->{treatments} }, $treatment;
            }
        }
    }

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    # print Dumper $individual;
    return $individual;
}

sub map_complexValue {

    my $complexValue = shift;

    # "typedQuantities": [
    #            {
    #              "type": {
    #                "label": "Visual Acuity",
    #                "id": "NCIT:C87149"
    #              },
    #              "quantity": {
    #                "unit": {
    #                  "id": "NCIT:C48570",
    #                  "label": "Percent Unit"
    #                },
    #                "value": 100
    #              }
    #            }
    #  }

    # Modifying the orginal ref
    for ( @{ $complexValue->{typedQuantities} } ) {
        $_->{quantityType} = delete $_->{type};
    }

    return 1;
}

sub get_metaData {

    my $self = shift;

    # NB: Q: Why inside PXF.pm and not inside BFF.pm?
    #   : A: Because it's easier to remember (used in REDCap,pm, BFF.pm)

    # Setting a few variables
    my $user = $self->{username};

    # NB: Darwin does not have nproc to show #logical-cores, using sysctl instead
    my $os = $^O;
    chomp(
        my $ncpuhost =
          $os eq 'Darwin' ? qx{/usr/sbin/sysctl -n hw.logicalcpu}
        : $os eq 'MSWin32' ? qx{wmic cpu get NumberOfLogicalProcessors}
        :                    qx{/usr/bin/nproc} // 1
    );

    # For the Windows command, the result will also contain the string
    # "NumberOfLogicalProcessors" which is the header of the output.
    # So we need to extract the actual number from it:
    if ( $os eq 'MSWin32' ) {
        ($ncpuhost) = $ncpuhost =~ /(\d+)/;
    }
    $ncpuhost = 0 + $ncpuhost;    # coercing it to be a number

    my $info = {
        user            => $user,
        ncpuhost        => $ncpuhost,
        cwd             => cwd,
        hostname        => hostname,
        'Convert-Pheno' => $::VERSION
    };
    my $resources = [
        {
            id   => 'ICD10',
            name =>
'International Statistical Classification of Diseases and Related Health Problems 10th Revision',
            url             => 'https://icd.who.int/browse10/2019/en#',
            version         => '2019',
            namespacePrefix => 'ICD10',
            iriPrefix       => 'https://icd.who.int/browse10/2019/en#/'
        },
        {
            id              => 'NCIT',
            name            => 'NCI Thesaurus',
            url             => 'http://purl.obolibrary.org/obo/ncit.owl',
            version         => '22.03d',
            namespacePrefix => 'NCIT',
            iriPrefix       => 'http://purl.obolibrary.org/obo/NCIT_'
        },
        {
            id              => 'Athena-OHDSI',
            name            => 'Athena-OHDSI',
            url             => 'https://athena.ohdsi.org',
            version         => 'v5.3.1',
            namespacePrefix => 'OHDSI',
            iriPrefix       => 'http://www.fakeurl.com/OHDSI_'
        }
    ];
    return {
        #_info => $info,         # Not allowed
        created                  => iso8601_time(),
        createdBy                => $user,
        submittedBy              => $user,
        phenopacketSchemaVersion => '2.0',
        resources                => $resources,
        externalReferences       => [
            {
                id        => 'PMID: 26262116',
                reference =>
                  'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4815923',
                description =>
'Observational Health Data Sciences and Informatics (OHDSI): Opportunities for Observational Researchers'
            }
        ]
    };
}

1;
