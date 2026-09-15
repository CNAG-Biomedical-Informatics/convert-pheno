use strict;
use warnings;
use lib qw(lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use JSON::XS qw(decode_json);
use Path::Tiny qw(path);
use Mojo::IOLoop;
use Convert::Pheno::HTTP::Jobs;
use Convert::Pheno::HTTP::Service qw(execute);

my $root=tempdir(CLEANUP=>1);
my $jobs=Convert::Pheno::HTTP::Jobs->new(root=>$root,worker=>abs_path('api/perl/worker.pl'));
my $source='t/pxf2bff/in/pxf.json';
my $grant=$jobs->register_file($source);
ok($grant->{id},'file selection receives a handle');
ok(!exists $grant->{path},'public handle does not expose a filesystem path');
eval {$jobs->resolve_grant('../../etc/passwd')};
like($@,qr/Unknown or expired/,'unregistered paths cannot be used as handles');
my $job=$jobs->submit({conversion=>'pxf2bff',input=>{files=>{source=>[$grant->{id}]}},
  output=>{entities=>['individuals','biosamples']},options=>{test=>JSON::XS::true}});
my $deadline=time()+30;
while ($jobs->status($job->{id})->{status} =~ /queued|running/) {
  die 'Worker timed out' if time()>$deadline;
  $jobs->poll;
  select undef,undef,undef,0.05;
}
my $status=$jobs->status($job->{id});
is($status->{status},'completed','separate worker completes a real conversion') or diag explain $status;
my $expected=execute('pxf2bff',{input=>{data=>decode_json(path($source)->slurp_raw)},
  output=>{entities=>['individuals','biosamples']},options=>{test=>JSON::XS::true}});
for my $artifact (@{$expected->{artifacts}}) {
  my ($file)=$jobs->artifact($job->{id},$artifact->{id});
  is_deeply(decode_json(path($file)->slurp_raw),decode_json($artifact->{content}),"$artifact->{id} matches existing API results");
}
ok(!exists $status->{result}{artifacts}[0]{content},'job responses contain descriptors, not entire files');
ok($status->{fingerprints}[0]{sha256},'run records a source fingerprint');
ok(!-f path($root,$job->{id},'request.json'),'request data is removed after execution');
my $preview=$jobs->preview($job->{id},'individuals');
ok($preview->{data},'small JSON output can be inspected structurally');
ok(!$preview->{truncated},'small preview is complete');
eval {$jobs->artifact($job->{id},'../request')};
like($@,qr/Unknown output/,'output paths cannot be traversed');
my $destination = tempdir(CLEANUP=>1);
my $destination_handle = $jobs->register_file($destination);
my $export = $jobs->submit({conversion=>'pxf2bff',input=>{files=>{source=>[$grant->{id}]}},
  destination=>$destination_handle->{id},output=>{entities=>['individuals']},options=>{test=>JSON::XS::true}});
$deadline=time()+30;
while ($jobs->status($export->{id})->{status} =~ /queued|running/) {
  die 'Export worker timed out' if time()>$deadline;
  $jobs->poll; select undef,undef,undef,.05;
}
my $exported = $jobs->status($export->{id});
is($exported->{status},'completed','real conversion publishes to a selected output parent');
ok(-f path($exported->{directory},'individuals.json'),'exported artifact exists');
ok(!-e path($exported->{directory},'.convert-pheno-owner'),'successful export removes ownership marker');
ok(!-e path($root,$export->{id},'publication.json'),'successful export removes journal');
$jobs->shutdown;
my $restart=Convert::Pheno::HTTP::Jobs->new(root=>$root,worker=>abs_path('api/perl/worker.pl'));
is(scalar @{$restart->list},2,'completed run history survives service restart');
$jobs->shutdown;
done_testing;
