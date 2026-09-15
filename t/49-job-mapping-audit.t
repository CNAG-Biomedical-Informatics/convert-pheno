use strict;
use warnings;
use lib qw(lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use JSON::XS qw(decode_json);
use List::Util qw(sum);
use Test::ConvertPheno qw(slurp_zip_member);
use Convert::Pheno::HTTP::Jobs;
my $root=tempdir(CLEANUP=>1);
my $jobs=Convert::Pheno::HTTP::Jobs->new(root=>$root,worker=>path('api/perl/worker.pl')->absolute->stringify);
END {$jobs->shutdown if $jobs}
my $source=$jobs->register_file('t/csv2bff/in/csv_data.csv');
my $mapping=$jobs->register_file('t/csv2bff/in/csv_mapping.yaml');
my $original=path('t/csv2bff/in/csv_mapping.yaml')->slurp_utf8;
my $copy=$jobs->save_mapping($original."\n# Reviewed copy\n");
is(path('t/csv2bff/in/csv_mapping.yaml')->slurp_utf8,$original,'validation never modifies source mapping');
my @outputs;
for my $format (qw(tsv xlsx)) {
    my $job=$jobs->submit({conversion=>'csv2bff',input=>{files=>{source=>[$source->{id}],mapping=>[($format eq 'tsv' ? $mapping : $copy)->{id}]}},
        output=>{entities=>['individuals']},options=>{separator=>',',term_audit=>$format,test=>JSON::XS::true}});
    my $deadline=time()+60;
    while ($jobs->status($job->{id})->{status}=~/queued|running/) {
        die 'Audit worker timed out' if time()>$deadline;
        $jobs->poll; select undef,undef,undef,.05;
    }
    my $status=$jobs->status($job->{id});
    is($status->{status},'completed',"native mapping conversion with $format audit completes") or diag explain $status;
    my $review=$status->{result}{meta}{terminologyAudit};
    ok($review->{totalDecisions}>0,'review metadata contains real lookup decisions');
    is(sum(values %{$review->{counts}}),$review->{totalDecisions},'action counts cover all decisions');
    my ($file)=$jobs->artifact($job->{id},$review->{reportArtifactId});
    ok(-s $file,'downloadable full audit exists');
    if ($format eq 'xlsx') {
        like(slurp_zip_member("$file",'xl/workbook.xml'),qr/Terminology Audit/,'XLSX contains the expected worksheet');
    } else { like(path($file)->slurp_utf8,qr/review_action/,'TSV includes recommendation column') }
    my ($output)=$jobs->artifact($job->{id},'individuals');
    $outputs[$format eq 'tsv' ? 0 : 1] = decode_json(path($output)->slurp_raw);
}
is_deeply($outputs[1],$outputs[0],'reviewed mapping copy and different audit format preserve conversion results');
ok(!eval {$jobs->save_mapping("mappingVersion: [\n");1},'invalid YAML cannot become the active validated copy');
$jobs->shutdown;
done_testing;
