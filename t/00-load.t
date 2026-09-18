#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(./lib ../lib t/lib);
use Test::More;

use_ok('Convert::Pheno');

{
    local %ENV = %ENV;
    delete @ENV{qw(LOGNAME USER USERNAME)};
    is(Convert::Pheno->new()->username, 'dummy-user',
        'missing username environment variables have a string fallback');
    is(Convert::Pheno->new(username => undef)->username, 'dummy-user',
        'explicit undefined username uses the same fallback');
    is(Convert::Pheno->new(username => 'reviewer')->username, 'reviewer',
        'explicit username is preserved without environment defaults');
}

my $signal_check = q{
    use strict;
    use warnings;
    use Scalar::Util qw(refaddr);
    BEGIN {
        $SIG{__WARN__} = sub { };
        $SIG{__DIE__}  = sub { CORE::die @_ };
    }
    my $warn_handler = refaddr($SIG{__WARN__});
    my $die_handler  = refaddr($SIG{__DIE__});
    require Convert::Pheno;
    exit 1 unless refaddr($SIG{__WARN__}) == $warn_handler;
    exit 1 unless refaddr($SIG{__DIE__}) == $die_handler;
};
is(
    system( $^X, '-Ilib', '-e', $signal_check ),
    0,
    'loading Convert::Pheno preserves application signal handlers'
);

open my $version_fh, '<', 'VERSION' or die "Could not read VERSION: $!";
chomp( my $release_version = <$version_fh> );
close $version_fh;
( my $module_release_version = $Convert::Pheno::VERSION ) =~ s/_.*\z//;
is(
    $module_release_version,
    $release_version,
    'Perl module release base matches workflow VERSION'
);

done_testing;
