use strict;
use warnings;
use lib qw(lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use Path::Tiny qw(path);
use JSON::XS ();
use Convert::Pheno::HTTP::Jobs;
use Convert::Pheno::HTTP::Projects;

my $tmp = tempdir(CLEANUP => 1);
my $root = path($tmp, 'service'); $root->mkpath;
my $dir = path($tmp, 'project'); $dir->mkpath;
my $jobs = Convert::Pheno::HTTP::Jobs->new(root => "$root", worker => abs_path('api/perl/worker.pl'));
my $external = $dir->child('external.csv'); $external->spew_utf8("id\n1\n");
my $example = $root->child('example.csv'); $example->spew_utf8("id\n2\n");
my $output = $dir->child('outputs'); $output->mkpath;
my $file = $dir->child('review.cpheno');
my $data = {settings => {conversion => 'csv2bff', options => {separator => ';'}, output => {entities => ['individuals']}},
    files => {source => [$jobs->register_file("$external")->{id}], dictionary => [$jobs->register_file("$example")->{id}]},
    jsonInput => qq({"id":"synthetic-\x{e9}"}), mapping => "mappingVersion: 2\n# unfinished edit\n",
    mappingDirty => JSON::XS::true, destination => $jobs->register_file("$output")->{id}, runs => ['run-1']};
my $saved = Convert::Pheno::HTTP::Projects::save($jobs, "$file", $data);
ok($saved->{file}{id}, 'project save returns an authorized handle');
my $manifest = JSON::XS::decode_json($file->slurp_raw);
is($manifest->{sources}{source}[0]{path}, 'external.csv', 'external source is referenced relatively');
ok($manifest->{sources}{dictionary}[0]{owned}, 'managed example is copied into project data');
is($external->slurp_utf8, "id\n1\n", 'original file is unchanged');
ok(!exists($manifest->{settings}{files}), 'session handles are not serialized into settings');
$example->remove;
$jobs->shutdown;
$jobs = Convert::Pheno::HTTP::Jobs->new(root => "$root", worker => abs_path('api/perl/worker.pl'));
my $opened = Convert::Pheno::HTTP::Projects::open($jobs, "$file");
is_deeply($opened->{settings}, $data->{settings}, 'conversion options and entities round-trip');
is($opened->{jsonInput}, $data->{jsonInput}, 'pasted Unicode text survives restart');
is($opened->{mapping}, $data->{mapping}, 'unfinished mapping text survives restart');
ok($opened->{mappingDirty}, 'unvalidated mapping remains unvalidated');
is_deeply($opened->{runs}, ['run-1'], 'run references survive restart');
is_deeply($opened->{missing}, [], 'available files do not require reselection');
is(path($jobs->resolve_grant($opened->{files}{dictionary}[0]{id}))->slurp_utf8, "id\n2\n", 'example survives deletion of temporary source');
is(path($jobs->resolve_grant($opened->{files}{mapping}[0]{id}))->slurp_utf8, $data->{mapping}, 'mapping input and editor restore the same snapshot');
is(abs_path($jobs->resolve_grant($opened->{destination}{id})), abs_path($output), 'output destination is restored');

my $copy = $dir->child('copy.cpheno');
Convert::Pheno::HTTP::Projects::save($jobs, "$copy", {%$data, files => {dictionary => [$opened->{files}{dictionary}[0]{id}]}, destination => $opened->{destination}{id}});
like(JSON::XS::decode_json($copy->slurp_raw)->{sources}{dictionary}[0]{path}, qr/copy\.cpheno\.data/, 'Save As copies owned examples into its own companion folder');
$external->remove;
$opened = Convert::Pheno::HTTP::Projects::open($jobs, "$file");
is($opened->{missing}[0]{role}, 'source', 'missing source is identified by role');
is($opened->{missing}[0]{path}, 'external.csv', 'missing source retains its path for relinking');
my $before = $file->slurp_raw;
eval {Convert::Pheno::HTTP::Projects::save($jobs, "$file", $data)};
ok($@, 'expired grants cannot be saved');
is($file->slurp_raw, $before, 'failed save preserves the previous project');
my $unrelated = $dir->child('unrelated.cpheno'); $unrelated->spew_utf8('unrelated contents');
eval {Convert::Pheno::HTTP::Projects::save($jobs, "$unrelated", $data)};
ok($@, 'unrelated files are never overwritten');
is($unrelated->slurp_utf8, 'unrelated contents', 'unrelated content is preserved');
path($dir, $manifest->{jsonInput})->remove;
eval {Convert::Pheno::HTTP::Projects::open($jobs, "$file")};
like($@, qr/Missing project data/, 'missing pasted data fails clearly instead of discarding it');
$jobs->shutdown;

subtest 'project paths through a symbolic-link directory' => sub {
    my $base = path(tempdir(CLEANUP => 1))->realpath;
    my $real = $base->child('real'); $real->mkpath;
    my $link = $base->child('alias');
    plan skip_all => 'Directory symlinks are unavailable' unless eval { symlink "$real", "$link" };
    my $service = Convert::Pheno::HTTP::Jobs->new(
        root => "$base/service", worker => abs_path('api/perl/worker.pl'));
    my $source = $real->child('external.csv'); $source->spew_utf8("id\n1\n");
    my $destination = $real->child('output'); $destination->mkpath;
    my $managed = path($service->{root}, 'example.csv'); $managed->spew_utf8("id\n2\n");
    my $project = $link->child('review.cpheno');
    Convert::Pheno::HTTP::Projects::save($service, "$project", {
        settings => $data->{settings},
        files => {
            source => [$service->register_file("$source")->{id}],
            dictionary => [$service->register_file("$managed")->{id}],
        },
        destination => $service->register_file("$destination")->{id},
        jsonInput => '{"id":"synthetic"}', mapping => "mappingVersion: 2\n",
    });
    my $stored = JSON::XS::decode_json($project->slurp_raw);
    is($stored->{sources}{source}[0]{path}, 'external.csv', 'source is relative to the physical project directory');
    is($stored->{destination}, 'output', 'destination is relative to the physical project directory');
    like($stored->{jsonInput}, qr{^review\.cpheno\.data[\\/]}, 'owned text stays within the companion folder');
    $managed->remove;
    for my $directory ($real, $link) {
        my $restored = Convert::Pheno::HTTP::Projects::open($service, "@{[$directory->child('review.cpheno')]}");
        is_deeply($restored->{missing}, [], "all files reopen through $directory");
        is($restored->{jsonInput}, '{"id":"synthetic"}', 'owned text reopens');
    }
    $service->shutdown;
};

require Test::Mojo;
local $ENV{CONVERT_PHENO_API_TOKEN} = 'a' x 32;
local $ENV{CONVERT_PHENO_LOCAL_TOKEN} = 'b' x 32;
local $ENV{CONVERT_PHENO_STATE_DIR} = tempdir(CLEANUP => 1);
require './api/perl/main.pl';
my $t = Test::Mojo->new(main::app());
my $auth = {Authorization => 'Bearer ' . $ENV{CONVERT_PHENO_API_TOKEN}};
$t->post_ok('/api/projects/local/open' => $auth => json => {path => "$copy"})->status_is(403);
$t->post_ok('/api/projects/local/save' => $auth => json => {path => "$copy", data => $data})->status_is(403);
$t->post_ok('/api/projects/local/open' => {%$auth, 'X-Convert-Pheno-Local' => $ENV{CONVERT_PHENO_LOCAL_TOKEN}} => json => {path => "$copy"})
    ->status_is(200)->json_is('/data/settings/conversion', 'csv2bff');
done_testing;
