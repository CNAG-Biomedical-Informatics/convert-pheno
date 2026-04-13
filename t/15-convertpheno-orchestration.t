#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);
use Convert::Pheno;
use Convert::Pheno::Runner qw(resolve_operation run_operation);

my $orig_warn_handler = $SIG{__WARN__};
local $SIG{__WARN__} = sub {
    return if $_[0] =~ /^Subroutine .* redefined /;
    return $orig_warn_handler ? $orig_warn_handler->(@_) : warn @_;
};

{
    no warnings 'redefine';

    local *Convert::Pheno::redcap2bff = sub { return [ { id => 'r1' } ] };
    local *Convert::Pheno::cdisc2bff  = sub { return [ { id => 'c1' } ] };
    local *Convert::Pheno::csv2bff    = sub { return [ { id => 'csv1' } ] };
    local *Convert::Pheno::pxf2bff    = sub { return [ { id => 'p1' } ] };
    local *Convert::Pheno::omop2bff   = sub { return [ { id => 'o1' } ] };
    local *Convert::Pheno::_run_primary_view = sub {
        my ($self) = @_;
        return {
            method      => $self->{method},
            data        => $self->{data},
            in_textfile => $self->{in_textfile},
        };
    };
    local *Convert::Pheno::merge_omop_tables = sub { return { merged => shift } };

    my $redcap = Convert::Pheno->new( { method => 'redcap2pxf', in_textfile => 1 } )->redcap2pxf;
    is( $redcap->{method}, 'bff2pxf', 'redcap2pxf switches to bff2pxf' );
    is_deeply( $redcap->{data}, [ { id => 'r1' } ], 'redcap2pxf forwards redcap2bff output' );
    is( $redcap->{in_textfile}, 0, 'redcap2pxf forces in_textfile off' );

    my $cdisc = Convert::Pheno->new( { method => 'cdisc2omop', in_textfile => 1 } )->cdisc2omop;
    is( $cdisc->{merged}{data}[0]{id}, 'c1', 'cdisc2omop merges cdisc2bff output' );

    my $csv = Convert::Pheno->new( { method => 'csv2omop', in_textfile => 1 } )->csv2omop;
    is( $csv->{merged}{data}[0]{id}, 'csv1', 'csv2omop merges csv2bff output' );

    my $pxf = Convert::Pheno->new( { method => 'pxf2omop', in_textfile => 1 } )->pxf2omop;
    is( $pxf->{merged}{data}[0]{id}, 'p1', 'pxf2omop merges pxf2bff output' );
}

{
    my ( undef, $tmp_file ) = tempfile();
    my $convert = Convert::Pheno->new(
        {
            method    => 'omop2bff',
            out_file  => $tmp_file,
            in_textfile => 0,
        }
    );
    $convert->{omop_cli} = 1;
    my $stream = Convert::Pheno::_dispatcher_open_stream_out($convert);
    ok( $stream->{fh}, '_dispatcher_open_stream_out opens output file in streaming mode' );
    close $stream->{fh};
}

{
    my $convert = Convert::Pheno->new(
        {
            method      => 'bff2pxf',
            in_textfile => 0,
            data        => { inline => 1 },
        }
    );
    is_deeply( Convert::Pheno::_dispatcher_input_data($convert), { inline => 1 }, '_dispatcher_input_data returns in-memory data when not reading a file' );
}

{
    my $convert = Convert::Pheno->new(
        {
            method      => 'bff2pxf',
            in_textfile => 1,
            in_file     => 't/bff2pxf/in/individuals.json',
        }
    );
    my $data = Convert::Pheno::_dispatcher_input_data($convert);
    is( ref($data), 'ARRAY', '_dispatcher_input_data reads structured file input for bff-like methods' );
}

{
    my $convert = Convert::Pheno->new( { stream => 1 } );
    local *Convert::Pheno::transpose_omop_data_structure = sub { die 'should not be called' };
    my $data = { CONCEPT => [] };
    ok( Convert::Pheno::_omop_prepare_data_shape( $convert, $data ), '_omop_prepare_data_shape succeeds in stream mode' );
    is( $convert->{data}, $data, '_omop_prepare_data_shape keeps data as-is in stream mode' );
}

{
    my $convert = Convert::Pheno->new( { stream => 0 } );
    local *Convert::Pheno::transpose_omop_data_structure = sub { return [ { PERSON => { person_id => 1 } } ] };
    ok( Convert::Pheno::_omop_prepare_data_shape( $convert, { CONCEPT => [] } ), '_omop_prepare_data_shape succeeds in non-stream mode' );
    is_deeply( $convert->{data}, [ { PERSON => { person_id => 1 } } ], '_omop_prepare_data_shape transposes data in non-stream mode' );
}

{
    my $convert = Convert::Pheno->new( {} );
    dies_ok { Convert::Pheno::_omop_require_concept( $convert, {} ) } '_omop_require_concept dies when CONCEPT is missing';
    ok( Convert::Pheno::_omop_require_concept( $convert, { CONCEPT => [] } ), '_omop_require_concept passes when CONCEPT exists' );
}

{
    my $convert = Convert::Pheno->new( { method => 'omop2bff', prev_omop_tables => [ 'DRUG_EXPOSURE', 'PERSON' ], person => { 1 => { person_id => 1 } } } );
    my @csv_calls;
    my @sql_calls;
    local *Convert::Pheno::open_connections_SQLite = sub { return 1 };
    local *Convert::Pheno::read_csv_stream = sub { push @csv_calls, $_[0]{in}; return 1 };
    local *Convert::Pheno::read_sqldump_stream = sub { push @sql_calls, $_[0]{self}{omop_tables}[0]; return 1 };

    ok( Convert::Pheno::process_csv_files_stream( $convert, [ 'a.csv', 'b.csv' ] ), 'process_csv_files_stream succeeds' );
    is_deeply( \@csv_calls, [ 'a.csv', 'b.csv' ], 'process_csv_files_stream forwards each file' );

    ok( Convert::Pheno::process_sqldump_stream( $convert, 'dump.sql', [ 'CONCEPT', 'DRUG_EXPOSURE', 'PERSON' ] ), 'process_sqldump_stream succeeds' );
    is_deeply( \@sql_calls, [ 'DRUG_EXPOSURE' ], 'process_sqldump_stream skips RAM-memory OMOP tables' );
}

{
    no warnings 'redefine';
    my $json = JSON::XS->new->canonical->pretty;
    my $convert = Convert::Pheno->new( {} );
    $convert->{method_ori} = 'omop2pxf';
    local *Convert::Pheno::do_bff2pxf = sub { return { converted => 1 } };
    my $out_ref = Convert::Pheno::omop_dispatcher( $convert, { id => 1 }, $json );
    like( $$out_ref, qr/converted/, 'omop_dispatcher applies bff2pxf when method_ori is omop2pxf' );

    $convert->{method_ori} = 'omop2bff';
    $out_ref = Convert::Pheno::omop_dispatcher( $convert, { direct => 1 }, $json );
    like( $$out_ref, qr/direct/, 'omop_dispatcher encodes original result otherwise' );
}

{
    no warnings 'redefine';

    my $convert = Convert::Pheno->new( { method => 'omop2bff' } );
    my $op = resolve_operation($convert);
    is( $op->{type}, 'bundle', 'runner resolves omop2bff as a bundle operation' );
    is_deeply( $op->{default_entities}, ['individuals'], 'runner resolves omop2bff default bundle entities' );

    local *Convert::Pheno::OMOP::ToBFF::run_omop_to_bundle = sub {
        my ( $self, $input, $context ) = @_;
        my $bundle = Convert::Pheno::Model::Bundle->new( { entities => ['individuals'] } );
        $bundle->add_entity( individuals => { id => $input->{id} } );
        return $bundle;
    };

    local *Convert::Pheno::open_connections_SQLite       = sub { return 1 };
    local *Convert::Pheno::close_connections_SQLite      = sub { return 1 };
    local *Convert::Pheno::finalize_search_audit         = sub { return 1 };
    local *Convert::Pheno::_dispatcher_open_stream_out   = sub { return undef };

    my $res = run_operation( $convert, { id => 'bundle-1' }, operation => $op, view => 'primary' );
    is_deeply( $res, { id => 'bundle-1' }, 'runner unwraps bundle operations to the primary view' );
}

{
    my $convert = Convert::Pheno->new( { method => 'bff2csv' } );
    my $op = resolve_operation($convert);
    is( $op->{type}, 'direct', 'runner resolves bff2csv as a direct operation' );
}

{
    no warnings 'redefine';

    my $convert = Convert::Pheno->new(
        {
            method   => 'omop2bff',
            entities => [ 'individuals', 'biosamples' ],
        }
    );

    local *Convert::Pheno::open_connections_SQLite       = sub { return 1 };
    local *Convert::Pheno::close_connections_SQLite      = sub { return 1 };
    local *Convert::Pheno::finalize_search_audit         = sub { return 1 };
    local *Convert::Pheno::_dispatcher_open_stream_out   = sub { return undef };

    local *Convert::Pheno::OMOP::ToBFF::run_omop_to_bundle = sub {
        my ( $self, $input, $context ) = @_;
        my $bundle = Convert::Pheno::Model::Bundle->new(
            {
                context  => $context,
                entities => $context->entities,
            }
        );
        $bundle->add_entity( individuals => { id => $input->{id} } );
        $bundle->add_entity( biosamples  => { id => "bio-$input->{id}" } );
        return $bundle;
    };

    my $bundle = run_operation(
        $convert,
        [ { id => 'i1' }, { id => 'i2' } ],
        view => 'bundle',
    );

    is_deeply(
        $bundle->entities('individuals'),
        [ { id => 'i1' }, { id => 'i2' } ],
        'runner merges individuals across bundle operations'
    );
    is_deeply(
        $bundle->entities('biosamples'),
        [ { id => 'bio-i1' }, { id => 'bio-i2' } ],
        'runner merges secondary entities across bundle operations'
    );
}

done_testing();
