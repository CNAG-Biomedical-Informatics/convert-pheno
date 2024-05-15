package Convert::Pheno::CSV;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Convert::Pheno::Default qw(get_defaults);
use Convert::Pheno::REDCap qw(get_required_terms map_diseases map_ethnicity map_exposures);
use Data::Dumper;
use Hash::Fold fold => { array_delimiter => ':' };
use Exporter 'import';
our @EXPORT = qw(do_bff2csv do_pxf2csv do_csv2bff);

#$Data::Dumper::Sortkeys = 1;

my $DEFAULT = get_defaults();

###############
###############
#  BFF2CSV    #
###############
###############

sub do_bff2csv {

    my ( $self, $bff ) = @_;

    # Premature return
    return unless defined($bff);

    # Flatten the hash to 1D
    my $csv = fold($bff);

    # Return the flattened hash
    return $csv;
}

###############
###############
#  PXF2CSV    #
###############
###############

sub do_pxf2csv {

    my ( $self, $pxf ) = @_;

    # Premature return
    return unless defined($pxf);

    # Flatten the hash to 1D
    my $csv = fold($pxf);

    # Return the flattened hash
    return $csv;
}

###############
###############
#  CSV2BFF    #
###############
###############

sub do_csv2bff {

    my ( $self, $participant ) = @_;
    my $data_mapping_file = $self->{data_mapping_file};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # $participant =
    #       {
    #         'abdominal_mass' => 'No',
    #         'abdominal_pain' => 'Yes',
    #         'age' => 25,
    #         'age_first_diagnosis' => 24
    #          ...
    #        }
    print Dumper $participant
      if ( defined $self->{debug} && $self->{debug} > 4 );

    # Data structure (hashref) for each individual
    my $individual = {};

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type
    my $param_sub = {
            type              => 'CSV',
            individual        => $individual,
            data_mapping_file => $data_mapping_file,
            participant       => $participant,
            self              => $self,
        };
    $param_sub->{lock_keys} = ['lock_keys', keys %$param_sub];
    my ( $sex_field, $id_field ) = get_required_terms($param_sub);

    # Premature return if fields are not defined or present
    return
      unless ( defined $participant->{$id_field}
        && $participant->{$sex_field} );

    # Variable that will allow to perform ad hoc changes for specific projects
    my $project_id = $data_mapping_file->{project}{id};
    my $project_ontology = $data_mapping_file->{project}{ontology};

    # ========
    # diseases
    # ========

    map_diseases($param_sub);

    # =========
    # ethnicity
    # =========

    map_ethnicity($param_sub);

    # =========
    # exposures
    # =========

    map_exposures($param_sub);

    # ================
    # geographicOrigin
    # ================

    #$individual->{geographicOrigin} = {};

    # ==
    # id
    # ==

    # Concatenation of the values in @id_fields (mapping file)
    $individual->{id} = join ':',
      map { $participant->{$_} // 'NA' } @{ $data_mapping_file->{id}{fields} };

    # ====
    # info
    # ====

    map_info($param_sub);

    # =========================
    # interventionsOrProcedures
    # =========================

    map_interventionsOrProcedures($param_sub);

    # =============
    # karyotypicSex
    # =============

    # $individual->{karyotypicSex} = undef;

    # ========
    # measures
    # ========


    map_measures($param_sub);

    # =========
    # pedigrees
    # =========

    #$individual->{pedigrees} = [];

    # ==================
    # phenotypicFeatures
    # ==================

    map_phenotypicFeatures($param_sub);

    # ===
    # sex
    # ===

    map_sex($param_sub);


    # ==========
    # treatments
    # ==========

     map_treatments($param_sub);


    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individual;
}

1;
