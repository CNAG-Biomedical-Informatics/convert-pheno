use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use Path::Tiny qw(path);
use JSON::XS qw(encode_json);
use Fcntl qw(LOCK_EX LOCK_NB);
use Convert::Pheno::HTTP::Jobs;

sub interrupted_export {
    my ($default) = @_;
    my $root = path(abs_path(tempdir(CLEANUP=>1)));
    my $external = path(abs_path(tempdir(CLEANUP=>1)));
    my $id = 'a' x 40;
    my $dir = $root->child($id); $dir->mkpath;
    my $staging = $default ? $dir->child('staging') : $external->child(".convert-pheno-$id"); $staging->mkpath;
    my $final = $default ? $dir->child('outputs') : $external->child("convert-pheno-$id");
    my $status = {id=>$id, status=>'running', created=>1, outputDirectory=>"$final"};
    my $completed = {%$status,status=>'completed',directory=>"$final",result=>{artifacts=>[{id=>'individuals',filename=>'individuals.json',bytes=>2,kind=>'json'}]}};
    $dir->child('status.json')->spew_raw(encode_json($status));
    $dir->child('request.json')->spew_raw('{}');
    $dir->child('publication.json')->spew_raw(encode_json({final=>"$final",staging=>"$staging",owner=>'synthetic-owner',completed=>$completed}));
    $staging->child('.convert-pheno-owner')->spew_raw('synthetic-owner');
    $staging->child('individuals.json')->spew_raw('[]');
    return ($root,$dir,$staging,$final,$completed);
}
{
    my ($root,$dir,$staging,$final) = interrupted_export();
    my $jobs=Convert::Pheno::HTTP::Jobs->new(root=>"$root",worker=>'api/perl/worker.pl');
    is($jobs->status('a' x 40)->{status},'interrupted','incomplete export is interrupted');
    ok(!-e $staging && !-e $final,'owned partial export removed without publishing');
    ok(!-e $dir->child('publication.json'),'recovered journal removed');
    $jobs->shutdown;
}
{
    my ($root,$dir,$staging,$final) = interrupted_export();
    rename $staging,$final or die $!;
    my $jobs=Convert::Pheno::HTTP::Jobs->new(root=>"$root",worker=>'api/perl/worker.pl');
    is($jobs->status('a' x 40)->{status},'completed','rename completed before crash is recovered as success');
    is($final->child('individuals.json')->slurp_raw,'[]','published output retained');
    ok(!-e $final->child('.convert-pheno-owner'),'marker cleared after completion');
    $jobs->shutdown;
}
{
    my ($root,$dir,$staging,$final,$completed) = interrupted_export();
    rename $staging,$final or die $!;
    $dir->child('status.json')->spew_raw(encode_json($completed));
    unlink $final->child('.convert-pheno-owner');
    my $jobs=Convert::Pheno::HTTP::Jobs->new(root=>"$root",worker=>'api/perl/worker.pl');
    is($jobs->status('a' x 40)->{status},'completed','recovery tolerates crash after marker cleanup');
    $jobs->shutdown;
}
{
    my ($root,$dir,$staging) = interrupted_export();
    $staging->child('.convert-pheno-owner')->spew_raw('another-owner');
    ok(!eval {Convert::Pheno::HTTP::Jobs->new(root=>"$root",worker=>'api/perl/worker.pl');1},'changed ownership refuses automatic cleanup');
    ok(-f $staging->child('individuals.json'),'unowned output is preserved');
}
{
    my ($root,$dir,$staging) = interrupted_export();
    open my $lock,'>>',$dir->child('.worker.lock') or die $!;
    flock($lock,LOCK_EX|LOCK_NB) or die $!;
    ok(!eval {Convert::Pheno::HTTP::Jobs->new(root=>"$root",worker=>'api/perl/worker.pl');1},'live worker lock blocks startup recovery');
    ok(-f $dir->child('request.json') && -d $staging,'live worker files left alone');
    close $lock;
}
{
    my ($root,$dir,$staging,$final) = interrupted_export(1);
    rename $staging,$final or die $!;
    my $jobs=Convert::Pheno::HTTP::Jobs->new(root=>"$root",worker=>'api/perl/worker.pl');
    is($jobs->status('a' x 40)->{status},'completed','default output rename is recovered as success');
    is($final->child('individuals.json')->slurp_raw,'[]','default published output retained');
    $jobs->shutdown;
}
done_testing;
