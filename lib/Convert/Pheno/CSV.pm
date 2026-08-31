package Convert::Pheno::CSV;

use strict;
use warnings;
use autodie;
use feature                        qw(say);
use JSON::XS;
use Hash::Fold fold => { array_delimiter => ':' };
use Exporter 'import';
our @EXPORT = qw(do_bff2csv do_pxf2csv);

#$Data::Dumper::Sortkeys = 1;

my $JSON    = JSON::XS->new->canonical;

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
    _normalize_folded_csv_values($csv);

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
    _normalize_folded_csv_values($csv);

    # Return the flattened hash
    return $csv;
}

sub _normalize_folded_csv_values {
    my ($row) = @_;

    # CSV output cannot preserve nested Perl refs. When Hash::Fold leaves a
    # boolean/object/array/hash at the leaf, convert it to a JSON literal so
    # headers stay stable and the value is still inspectable by the user.
    for my $key ( keys %{$row} ) {
        next unless ref $row->{$key};
        my $type = ref $row->{$key};

        if ( $type =~ /::Boolean$/ ) {
            $row->{$key} = $row->{$key} ? 'true' : 'false';
            next;
        }

        my $encoded = eval { $JSON->encode( $row->{$key} ) };
        $row->{$key} = defined $encoded ? $encoded : q{};
    }

    return $row;
}

1;
