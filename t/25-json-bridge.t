use strict;
use warnings;
use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);
use IPC::Open3;
use JSON::XS;
use Symbol qw(gensym);
use Test::More;

my $script = catfile( $Bin, '..', 'api', 'perl', 'json_bridge.pl' );
my $json   = JSON::XS->new->canonical;

sub run_bridge {
    my ($payload) = @_;
    my $stderr = gensym;
    my $pid = open3( my $in, my $out, $stderr, $^X, $script );
    print {$in} $payload if defined $payload;
    close $in;

    local $/;
    my $stdout = <$out>;
    my $err    = <$stderr>;

    waitpid( $pid, 0 );
    return ( $? >> 8, $stdout // q{}, $err // q{} );
}

my ( $exit_ok, $stdout_ok, $stderr_ok ) = run_bridge(
    $json->encode(
        {
            method => 'pxf2bff',
            data   => {
                phenopacket => {
                    id      => 'P0007500',
                    subject => {
                        id          => 'P0007500',
                        dateOfBirth => 'unknown-01-01T00:00:00Z',
                        sex         => 'FEMALE'
                    }
                }
            }
        }
    )
);

is( $exit_ok, 0, 'bridge exits successfully for valid payload' );
is( $stderr_ok, q{}, 'bridge keeps stderr empty on success' );

my $decoded = eval { $json->decode($stdout_ok) };
ok( !$@, 'bridge returns valid JSON on success' );
is( $decoded->{id}, 'P0007500', 'bridge returns converted BFF payload' );

my ( $exit_missing_method, undef, $stderr_missing_method ) =
  run_bridge( $json->encode( { data => {} } ) );
isnt( $exit_missing_method, 0, 'bridge fails when method is missing' );
like(
    $stderr_missing_method,
    qr/Payload must include string field 'method'/,
    'bridge reports missing method clearly'
);

my ( $exit_invalid_method, undef, $stderr_invalid_method ) =
  run_bridge( $json->encode( { method => 'not_a_method', data => {} } ) );
isnt( $exit_invalid_method, 0, 'bridge fails for invalid method name' );
like( $stderr_invalid_method, qr/not_a_method/, 'invalid method is reported' );

my ( $exit_bad_json, undef, $stderr_bad_json ) = run_bridge('{');
isnt( $exit_bad_json, 0, 'bridge fails for malformed JSON input' );
like( $stderr_bad_json, qr/Invalid JSON payload:/, 'malformed JSON is reported' );

done_testing;
