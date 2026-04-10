package Convert::Pheno::Runner;

use strict;
use warnings;
use autodie;

use Exporter 'import';

our @EXPORT_OK = qw(resolve_operation execute_operation);

sub resolve_operation {
    my ($self) = @_;

    my %legacy = (
        redcap2bff => \&Convert::Pheno::do_redcap2bff,
        cdisc2bff  => \&Convert::Pheno::do_cdisc2bff,
        csv2bff    => \&Convert::Pheno::do_csv2bff,
        csv2pxf    => \&Convert::Pheno::do_csv2pxf,
        bff2pxf    => \&Convert::Pheno::do_bff2pxf,
        bff2csv    => \&Convert::Pheno::do_bff2csv,
        bff2jsonf  => \&Convert::Pheno::do_bff2csv,
        bff2jsonld => \&Convert::Pheno::do_bff2jsonld,
        bff2omop   => \&Convert::Pheno::do_bff2omop,
        pxf2csv    => \&Convert::Pheno::do_pxf2csv,
        pxf2jsonf  => \&Convert::Pheno::do_pxf2csv,
        pxf2jsonld => \&Convert::Pheno::do_pxf2jsonld,
    );

    return {
        type   => 'bundle',
        entity => 'individuals',
        run    => sub {
            my ( $convert, $input ) = @_;
            return Convert::Pheno::OMOP::run_omop_to_bundle(
                $convert, $input, $convert->{conversion_context}
            );
        },
    } if $self->{method} eq 'omop2bff';

    return {
        type   => 'bundle',
        entity => 'individuals',
        run    => sub {
            my ( $convert, $input ) = @_;
            return Convert::Pheno::PXF::run_pxf_to_bundle(
                $convert, $input, $convert->{conversion_context}
            );
        },
    } if $self->{method} eq 'pxf2bff';

    return {
        type => 'legacy',
        run  => $legacy{ $self->{method} },
    } if exists $legacy{ $self->{method} };

    die "Unsupported method <$self->{method}> in runner\n";
}

sub execute_operation {
    my ( $self, $operation, $input ) = @_;

    my $result = $operation->{run}->( $self, $input );

    return $result->legacy_primary_entity( $operation->{entity} )
      if $operation->{type} eq 'bundle';

    return $result;
}

1;
