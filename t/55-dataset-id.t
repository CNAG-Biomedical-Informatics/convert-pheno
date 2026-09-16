use strict;
use warnings;
use lib qw(lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use JSON::XS qw(decode_json);
use Storable qw(dclone);
use Test::ConvertPheno qw(build_convert write_json_file);
use Convert::Pheno::HTTP::Service qw(catalog execute_files);
use Convert::Pheno::CLI::Args qw(build_cli_request);

my $dir = tempdir(CLEANUP => 1);
sub mapping {
    my ($profile, $id) = @_;
    my $file = "$dir/$profile-mapping.json";
    write_json_file($file, {
        mappingVersion => 2, source => {profile => $profile},
        target => {model => 'beacon', schemaVersion => '2.0.0'},
        project => {id => 'project-id', version => '1'},
        beacon => {datasets => {defaults => {id => $id, name => 'Study name'}}},
    });
    return $file;
}
my $map = mapping('pxf', 'study-123');
my $project_only_map = "$dir/project-only-mapping.json";
write_json_file($project_only_map, {
    mappingVersion => 2, source => {profile => 'pxf'},
    target => {model => 'beacon', schemaVersion => '2.0.0'},
    project => {id => 'project-id', version => '1'},
});
my $input = [{subject => {id => 'person-1', sex => 'MALE'}, biosamples => [{id => 'sample-1'}]}];
my $original = dclone($input);
sub converter {
    return build_convert(method => 'pxf2bff', data => $input, in_textfile => 0,
        mapping_file => $map, @_);
}

for my $enabled (0, 1) {
    my $bundle = converter(include_dataset_id => $enabled,
        entities => [qw(individuals biosamples datasets cohorts)])->_run_bundle_view;
    is($bundle->entities('datasets')->[0]{id}, 'study-123', 'Dataset ID follows mapping metadata');
    is($bundle->entities('datasets')->[0]{name}, 'Study name', 'Dataset name remains independent');
    for my $entity (qw(individuals biosamples)) {
        my $record = $bundle->entities($entity)->[0];
        if ($enabled) { is($record->{datasetId}, 'study-123', "$entity opt-in uses top-level datasetId") }
        else { ok(!exists $record->{datasetId}, "$entity unchanged without opt-in") }
        ok(!exists $record->{_datasetId}, 'No underscore alias is generated');
    }
    ok(!exists $bundle->entities('cohorts')->[0]{datasetId}, 'Cohorts do not receive the extension');
}
is_deeply($input, $original, 'Caller-owned input is unchanged');
is(converter(include_dataset_id => 1)->pxf2bff->[0]{datasetId}, 'study-123', 'Primary individuals output needs no datasets collection');
my $biosamples = converter(include_dataset_id => 1, entities => ['biosamples'])->_run_bundle_view;
is($biosamples->entities('biosamples')->[0]{datasetId}, 'study-123', 'Biosamples-only output gets the ID');

eval { converter(include_dataset_id => 1, mapping_file => undef)->pxf2bff };
like($@, qr/requires a dataset ID at <beacon\.datasets\.defaults\.id>/,
    'Missing mapping fails clearly');
eval { converter(include_dataset_id => 1, mapping_file => $project_only_map)->pxf2bff };
like($@, qr/requires a dataset ID at <beacon\.datasets\.defaults\.id>/,
    'Project ID is not reused for record-level datasetId');
eval { converter(include_dataset_id => 1, derived_entity_overrides => {datasets => {id => 'other'}})->pxf2bff };
like($@, qr/conflicts with the mapping file/, 'Conflicting dataset override cannot silently disagree');
eval { build_convert(method => 'pxf2omop', include_dataset_id => 1) };
like($@, qr/only supported for BFF output/, 'Other targets reject the option');

my $payload = "$dir/pxf.json";
write_json_file($payload, $input);
my $request = build_cli_request(argv => ['-ipxf', $payload, '-obff', "$dir/output.json",
    '--mapping-file', $map, '--include-dataset-id'],
    schema_file => 'share/schema/mapping-v2.json', out_dir => $dir, usage_error => sub {die @_});
ok($request->{data}{include_dataset_id}, 'CLI parses the opt-in');
my $response = execute_files('pxf2bff', {
    options => {include_dataset_id => JSON::XS::true, test => JSON::XS::true},
    output => {entities => ['individuals', 'biosamples']},
}, {source => [{path => $payload, filename => 'pxf.json'}],
    mapping => [{path => $map, filename => 'mapping.json'}]}, {workspace => $dir});
for my $artifact (@{$response->{artifacts}}) {
    is(decode_json($artifact->{content})->[0]{datasetId}, 'study-123', 'File API applies the same extension');
}
for my $route (@{catalog()->{data}}) {
    my $offered = scalar grep {$_->{name} eq 'include_dataset_id'} @{$route->{options}};
    is(!!$offered, !!($route->{target}{id} eq 'beacon'), "$route->{id} advertises the option only for BFF");
}

my $omop_map = mapping('omop', 'omop-study');
for my $stream (0, 1) {
    my $output = "$dir/omop-$stream";
    path($output)->mkpath;
    my $convert = build_convert(method => 'omop2bff',
        in_files => [map {"t/omop2bff/in/mimic_specimen/$_.csv"} qw(CONCEPT PERSON SPECIMEN)],
        mapping_file => $omop_map, include_dataset_id => 1,
        entities => [qw(individuals biosamples)], stream => $stream, out_dir => $output, sep => ';');
    if ($stream) {
        $convert->omop2bff;
        for my $entity (qw(individuals biosamples)) {
            my @records = map {decode_json($_)} path("$output/$entity.json")->lines;
            ok(@records > 0, "Streamed $entity are present");
            is_deeply([map {$_->{datasetId}} @records], [('omop-study') x @records], "Streamed $entity all carry the mapped ID");
        }
    } else {
        my $bundle = $convert->_run_bundle_view;
        for my $entity (qw(individuals biosamples)) {
            my $records = $bundle->entities($entity);
            ok(@$records > 0, "Non-streamed $entity are present");
            is_deeply([map {$_->{datasetId}} @$records], [('omop-study') x @$records], "Non-streamed $entity all carry the mapped ID");
        }
    }
}
done_testing;
