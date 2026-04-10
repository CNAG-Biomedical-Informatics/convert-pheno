package Convert::Pheno::REDCap;

use strict;
use warnings;
use autodie;
use Data::Dumper;
use Hash::Util qw(lock_keys);
use Convert::Pheno::Mapping::BFF::Individuals::Tabular qw(
  get_required_terms
  propagate_fields
  map_fields_to_redcap_dict
  map_diseases
  map_ethnicity
  map_exposures
  map_info
  map_interventionsOrProcedures
  map_measures
  map_phenotypicFeatures
  map_sex
  map_treatments
);
use Exporter 'import';

our @EXPORT = qw(do_redcap2bff);

sub do_redcap2bff {
    my ( $self, $participant ) = @_;
    my $redcap_dict       = $self->{data_redcap_dict};
    my $data_mapping_file = $self->{data_mapping_file};

    ##############################
    # <Variable> names in REDCap #
    ##############################
    #
    # REDCap does not enforce any particular variable name.
    # Extracted from https://www.ctsi.ufl.edu/wordpress/files/2019/02/Project-Creation-User-Guide.pdf
    # ---
    # "Variable Names: Variable names are critical in the data analysis process. If you export your data to a
    # statistical software program, the variable names are what you or your statistician will use to conduct
    # the analysis"
    #
    # "We always recommend reviewing your variable names with a statistician or whoever will be
    # analyzing your data. This is especially important if this is the first time you are building a
    # database"
    #---
    # If variable names are not consensuated, then we need to do the mapping manually "a posteriori".
    # This is what we are attempting here:

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    print Dumper $redcap_dict
      if ( defined $self->{debug} && $self->{debug} > 4 );
    print Dumper $participant
      if ( defined $self->{debug} && $self->{debug} > 4 );

    my $individual = {};

    my $param_sub = {
        source              => $data_mapping_file->{project}{source},
        project_id          => $data_mapping_file->{project}{id},
        project_ontology    => $data_mapping_file->{project}{ontology},
        redcap_dict         => $redcap_dict,
        data_mapping_file   => $data_mapping_file,
        participant         => $participant,
        self                => $self,
        individual          => $individual,
        term_mapping_cursor => undef,
    };

    my ( $sex_field, $id_field ) = get_required_terms($param_sub);

    propagate_fields( $id_field, $param_sub );

    return
      unless ( defined $participant->{$id_field}
        && $participant->{$sex_field} );

    my $pid_field = $id_field;
    my $pid       = join ':',
      map { $participant->{$_} // 'NA' } @{ $data_mapping_file->{id}{fields} };

    $param_sub->{participant_id_field} = $pid_field;
    $param_sub->{participant_id}       = $pid;

    $param_sub->{lock_keys} = [ 'lock_keys', keys %$param_sub ];
    lock_keys %$param_sub, @{ $param_sub->{lock_keys} };

    map_fields_to_redcap_dict( $redcap_dict, $participant );

    map_diseases($param_sub);
    map_ethnicity($param_sub);
    map_exposures($param_sub);

    $individual->{id} = $pid;

    map_info($param_sub);
    map_interventionsOrProcedures($param_sub);
    map_measures($param_sub);

    #map_pedigrees($param_sub);

    map_phenotypicFeatures($param_sub);
    map_sex($param_sub);
    map_treatments($param_sub);

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individual;
}

1;
