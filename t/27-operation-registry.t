use strict;
use warnings;

use Test::More;

use Convert::Pheno;
use Convert::Pheno::Operations qw(is_public_conversion public_conversions);

ok( is_public_conversion('pxf2bff'), 'registry accepts a public conversion' );
ok( !is_public_conversion('get_info'), 'registry rejects callable helper methods' );
ok(
    !is_public_conversion('omop2bff_stream_processing'),
    'registry rejects internal conversion helpers'
);

for my $conversion ( @{ public_conversions() } ) {
    ok(
        Convert::Pheno->can($conversion),
        "registered conversion <$conversion> exists"
    );
}

done_testing;
