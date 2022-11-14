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

    # We encountered that some PXF files have 
    # /phenopacket 
    # /interpretation
    # Get cursors for them if they exist
    my $interpretation = exists $data->{interpretation} ? $data->{interpretation} : undef;
    my $phenopacket    = exists $data->{phenopacket} ? $data->{phenopacket} : $data;

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # NB: In PXF some terms are = []
    my $individual;

    # ========
    # diseases
    # ========

    $individual->{diseases} =
      [ map { $_ = { diseaseCode => $_->{term} } }
          @{ $phenopacket->{diseases} } ]
      if exists $phenopacket->{diseases};

    # ==
    # id
    # ==

    $individual->{id} = $phenopacket->{subject}{id}
      if exists $phenopacket->{subject}{id};

    # ====
    # info
    # ====

    # **** $data->{phenopacket} ****
    $individual->{info}{phenopacket}{dateOfBirth} =
      $phenopacket->{subject}{dateOfBirth};

    # CNAG files have 'meta_data' nomenclature, but PHX documentation uses 'metaData'
    # We search for both 'meta_data' and 'metaData' and leave them untouched
    for my $term (qw (dateOfBirth genes meta_data metaData variants)) {
        $individual->{info}{phenopacket}{$term} = $phenopacket->{$term}
          if exists $phenopacket->{$term};
    }

    # **** $data->{interpretation} ****
    for my $term (qw (meta_data metaData)) {
        $individual->{info}{interpretation}{phenopacket}{$term} =
          $interpretation->{phenopacket}{$term}
          if $interpretation->{phenopacket}{$term};
    }

    # <diseases> and <phenotypicFeatures> are identical to those of $data->{phenopacket}{diseases,phenotypicFeatures}
    for my $term (
        qw (diagnosis diseases resolutionStatus phenotypicFeatures genes variants)
      )
    {
        $individual->{info}{interpretation}{$term} = $interpretation->{$term}
          if exists $interpretation->{$term};
    }

    # ==================
    # phenotypicFeatures
    # ==================

    $individual->{phenotypicFeatures} = [
        map {
            $_ = {
                "excluded" => (
                    exists $_->{negated} ? JSON::XS::true : JSON::XS::false
                ),
                "featureType" => $_->{type}
            }
        } @{ $phenopacket->{phenotypicFeatures} }
      ]
      if exists $phenopacket->{phenotypicFeatures};

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

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    # print Dumper $individual;
    return $individual;
}

sub get_metaData {

    # NB: Q: Why inside PXF.pm and not inside BFF.pm?
    #   : A: Because it's easier to remember

    # Setting a few variables
    my $user = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
    chomp( my $ncpuhost = qx{/usr/bin/nproc} ) // 1;
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
        externalReference        => [
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
