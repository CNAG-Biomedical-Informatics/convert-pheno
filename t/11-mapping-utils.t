#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Warn;
use Convert::Pheno::Mapping::Shared qw(
  convert2boolean
  convert_label_to_days
  get_age_from_date_and_birthday
  get_date_at_age
  get_date_component
  map_age_range
  map_iso8601_date2timestamp
  map_iso8601_timestamp2date
  merge_omop_tables
  validate_format
);

is( map_iso8601_date2timestamp('2020-03-04'), '2020-03-04T00:00:00Z', 'maps date to timestamp' );
is( map_iso8601_timestamp2date('2020-03-04 10:11:12'), '2020-03-04', 'maps timestamp to date' );

is( get_date_component( '2020-03-04T10:11:12Z', 'month' ), '03', 'extracts month component' );
warning_like {
    is( get_date_component( '2020-03-04T10:11:12Z', 'foo' ), '2020', 'falls back to year for invalid component' );
} qr/Invalid component <foo>/, 'warns on invalid date component';

is_deeply(
    map_age_range('7'),
    { age => { iso8601duration => 'P7Y' } },
    'maps scalar age to iso8601duration'
);
is_deeply(
    map_age_range('70+'),
    {
        ageRange => {
            start => { iso8601duration => 'P70Y' },
            end   => { iso8601duration => 'P999Y' },
        }
    },
    'maps plus range to bounded ageRange'
);

is( convert_label_to_days( 'weeks', 2 ), 14, 'converts plural week label to days' );
is( convert_label_to_days( 'month', 2 ), 60, 'converts month label to days' );
is( convert_label_to_days( 'fortnight', 2 ), undef, 'returns undef for unsupported duration label' );
is( convert_label_to_days( undef, 2 ), undef, 'returns undef for missing label' );

ok( convert2boolean('yes'), 'maps yes to true' );
ok( !convert2boolean('no'), 'maps no to false' );
is( convert2boolean('maybe'), undef, 'returns undef for unknown boolean string' );

is( get_age_from_date_and_birthday( { birth_day => '2000-05-03', date => '2010-05-02' } ), 'P9Y', 'computes age before birthday' );
is( get_age_from_date_and_birthday( { birth_day => '2000-05-03', date => '2010-05-03' } ), 'P10Y', 'computes age on birthday' );
is( get_date_at_age( 'P2Y', '2000-01-01' ), '2002-01-01', 'computes date at age for full-year duration' );

is( validate_format( { subject => {} }, 'pxf' ), 1, 'recognizes pxf format' );
is( validate_format( { id => 'x' }, 'bff' ), 1, 'recognizes non-pxf as bff format' );

is_deeply(
    merge_omop_tables(
        [
            {
                PERSON      => { person_id => 1 },
                OBSERVATION => [ { observation_id => 1 } ],
            },
            'not-a-hash',
            {
                OBSERVATION => [ { observation_id => 2 } ],
                MEASUREMENT => { measurement_id => 1 },
            },
        ]
    ),
    {
        PERSON      => [ { person_id => 1 } ],
        OBSERVATION => [ { observation_id => 1 }, { observation_id => 2 } ],
        MEASUREMENT => [ { measurement_id => 1 } ],
    },
    'merge_omop_tables merges array and scalar table rows and skips non-hash entries'
);

done_testing();
