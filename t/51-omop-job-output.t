use strict;
use warnings;
use lib qw(lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use JSON::XS qw(decode_json);
use Convert::Pheno::HTTP::Service qw(execute);
use Convert::Pheno::HTTP::Jobs;

for my $method (qw(omop2bff omop2pxf)) {
    my $root=tempdir(CLEANUP=>1);
    my $jobs=Convert::Pheno::HTTP::Jobs->new(root=>$root,worker=>path('api/perl/worker.pl')->absolute->stringify);
    my $request=decode_json(path('t/fixtures/http-omop-request.json')->slurp_raw);
    delete $request->{conversion};
    $request->{options}={test=>JSON::XS::true};
    $request->{options}{stream}=JSON::XS::false if $method eq 'omop2bff';
    $request->{output}=$method eq 'omop2bff' ? {entities=>['individuals']} : {};
    my $expected=execute($method,$request);
    my $job=$jobs->submit({conversion=>$method,%$request});
    my $deadline=time()+30;
    while ($jobs->status($job->{id})->{status} =~ /queued|running/) {
        die 'Worker timed out' if time()>$deadline;
        $jobs->poll; select undef,undef,undef,0.05;
    }
    my $status=$jobs->status($job->{id});
    is($status->{status},'completed',"$method JSON job completes") or diag explain $status;
    for my $entry (@{$expected->{artifacts}}) {
        my ($file)=$jobs->artifact($job->{id},$entry->{id});
        ok(-s $file,"$method output file is nonempty");
        is_deeply(decode_json(path($file)->slurp_raw),decode_json($entry->{content}),"$method file equals in-memory API output");
    }
    $jobs->shutdown;
}
done_testing;
