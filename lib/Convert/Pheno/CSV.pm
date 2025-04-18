package Convert::Pheno::CSV;

use strict;
use warnings;
use autodie;
use feature                        qw(say);
use Convert::Pheno::Utils::Default qw(get_defaults);
use Convert::Pheno::REDCap
  qw(get_required_terms propagate_fields map_fields_to_redcap_dict map_diseases map_ethnicity map_exposures map_info map_interventionsOrProcedures map_measures map_pedigrees map_phenotypicFeatures map_sex map_treatments);
use Data::Dumper;
use Hash::Util qw(lock_keys);
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

    # Intialize parameters for most subs
    my $param_sub = {
        source               => $data_mapping_file->{project}{source},
        project_id           => $data_mapping_file->{project}{id},
        project_ontology     => $data_mapping_file->{project}{ontology},
        data_mapping_file    => $data_mapping_file,
        participant          => $participant,
        self                 => $self,
        individual           => $individual,
        term_mapping_cursor  => undef,
        participant_id_field => undef,
        participant_id       => undef
    };

    $param_sub->{lock_keys} = [ 'lock_keys', keys %$param_sub ];
    lock_keys %$param_sub, @{ $param_sub->{lock_keys} };

    # *** ABOUT REQUIRED PROPERTIES ***
    # 'id' and 'sex' are required properties in <individuals> entry type
    my ( $sex_field, $id_field ) = get_required_terms($param_sub);

    # Now propagate fields according to user selection
    propagate_fields( $id_field, $param_sub );

    # Premature return (undef) if fields are not defined or present
    return
      unless ( defined $participant->{$id_field}
        && $participant->{$sex_field} );

    # NB: We don't need to initialize terms (unless required)
    # e.g.,
    # $individual->{diseases} = undef;
    #  or
    # $individual->{diseases} = []
    # Otherwise the validator may complain about being empty

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
