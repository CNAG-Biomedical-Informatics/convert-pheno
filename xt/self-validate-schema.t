#!/usr/bin/env perl

use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::ConvertPheno qw(build_convert is_ld_arch is_windows);

BEGIN {
    if ( is_ld_arch() ) {
        require Test::More;
        Test::More::plan(
            skip_all => 'Skipping tests on ld architectures due to known issues'
        );
        exit;
    }
}

plan skip_all => 'Skipping self-validation test on Windows'
  if is_windows();

plan skip_all => 'Requires IO::Socket::SSL for schema self-validation'
  unless defined eval { require IO::Socket::SSL; 1 };

my $ok = eval {
    my $convert = build_convert(
        in_file              => 't/redcap2bff/in/redcap_data.csv',
        redcap_dictionary    => 't/redcap2bff/in/redcap_dictionary.csv',
        mapping_file         => 't/redcap2bff/in/redcap_mapping.yaml',
        schema_file          => 't/schema/malformed.json',
        self_validate_schema => 1,
        method               => 'redcap2bff',
    );
    $convert->redcap2bff;
    1;
};

ok( !$ok, 'self_validate_schema rejects malformed JSON Schema' );
like(
    $@,
    qr/does not follow JSON Schema specification/,
    'self_validate_schema rejects malformed JSON Schema'
);

done_testing();
