use strict;
use warnings;
use lib qw(lib t/lib);
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

local $ENV{CONVERT_PHENO_API_TOKEN} = 'a' x 32;
local $ENV{CONVERT_PHENO_LOCAL_TOKEN} = 'b' x 32;
local $ENV{CONVERT_PHENO_STATE_DIR} = tempdir(CLEANUP => 1);
local $ENV{CONVERT_PHENO_OHDSI_DB_DIR};
require './api/perl/main.pl';
my $t = Test::Mojo->new(main::app());
my $folder = tempdir(CLEANUP => 1);
my $auth = {Authorization => 'Bearer ' . $ENV{CONVERT_PHENO_API_TOKEN}};
my $native = {%$auth, 'X-Convert-Pheno-Local' => $ENV{CONVERT_PHENO_LOCAL_TOKEN}};
$t->post_ok('/api/resources/local-directory' => $auth => json => {directory => $folder})
  ->status_is(403);
ok(!defined $ENV{CONVERT_PHENO_OHDSI_DB_DIR}, 'public API cannot change native resource paths');
$t->post_ok('/api/resources/local-directory' => $native => json => {directory => "$folder/missing"})
  ->status_is(422);
$t->post_ok('/api/resources/local-directory' => $native => json => {directory => $folder})
  ->status_is(200)->json_is('/data/directory', abs_path($folder));
is($ENV{CONVERT_PHENO_OHDSI_DB_DIR}, abs_path($folder), 'future workers inherit the selected folder');
$t->get_ok('/api/resources' => $auth)->status_is(200);
my ($ohdsi) = grep {$_->{id} eq 'ohdsi'} @{$t->tx->res->json->{data}};
ok(!$ohdsi->{installed}, 'resource status reflects the empty selected folder');
done_testing;
