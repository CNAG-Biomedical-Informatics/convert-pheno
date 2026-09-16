use strict;
use warnings;
use lib qw(./lib ../lib t/lib);
use Test::More;
use File::Temp qw(tempdir);
use Storable qw(dclone);
use Test::ConvertPheno qw(build_convert test_ohdsi_db_dir load_json_file write_json_file);
use Convert::Pheno::IO::CSVHandler qw(read_mapping_file);
use Convert::Pheno::OMOP::Vocabulary qw(resolve_standard_concept);
use Convert::Pheno::DB::SQLite qw(open_connections_SQLite close_connections_SQLite);
use Convert::Pheno::HTTP::Service qw(catalog execute_files);

my $tmp = tempdir(CLEANUP => 1);
my $db = test_ohdsi_db_dir();
my $mapping = 't/bff2omop/in/terminology.yaml';
my $schema = 'share/schema/mapping-v2.json';
my $data = load_json_file('t/bff2omop/in/local-terms.json');
my $before = dclone($data);
my $convert = build_convert(method => 'bff2omop', in_textfile => 0,
    data => $data, ohdsi_db => 1, path_to_ohdsi_db => $db,
    mapping_file => $mapping, term_audit_file => "$tmp/audit.tsv");
my $output = $convert->bff2omop;
is($output->{PERSON}[0]{gender_concept_id}, 8532, 'unlisted terms use normal resolution');
is($output->{CONDITION_OCCURRENCE}[0]{condition_concept_id}, 4112343, 'reviewed ID resolves through OHDSI');
is($output->{PROCEDURE_OCCURRENCE}[0]{procedure_concept_id}, 4163872, 'reviewed label resolves through OHDSI');
is($output->{CONDITION_OCCURRENCE}[0]{condition_source_value}, $data->[0]{diseases}[0]{diseaseCode}{label}, 'original source label retained');
is($output->{CONDITION_OCCURRENCE}[0]{condition_source_concept_id}, 0, 'target is not misrepresented as original source concept');
is_deeply($data, $before, 'caller-owned BFF remains unchanged');
my $audit;
{
    open my $fh, '<', "$tmp/audit.tsv" or die $!;
    local $/; $audit = <$fh>;
}
like($audit, qr/mapped_identifier_standard/, 'audit identifies reviewed identifier mapping');
like($audit, qr/mapped_domain_label_exact/, 'audit identifies reviewed label query');
like($audit, qr/LOCAL:viral-pharyngitis/, 'audit retains original identifier');
like($audit, qr/SNOMED:195662009/, 'audit includes reviewed query and result');

my $compiled = read_mapping_file({mapping_file => $mapping, schema_file => $schema});
my $unsupported = eval {
    build_convert(method => 'bff2pxf', in_textfile => 0, data => $data,
        mapping_file => $mapping)->bff2pxf;
    1;
};
ok(!$unsupported, 'OMOP terminology mapping is not silently ignored on another BFF route');
like($@, qr/only for bff2omop/, 'explains the mapping scope');
sub mapped_lookup {
    my ($query, $term, $domain) = @_;
    my $instance = build_convert(method => 'bff2omop', ohdsi_db => 1, path_to_ohdsi_db => $db);
    $instance->{_omop_terminology} = {'diseases.diseaseCode' => {query => $query}};
    open_connections_SQLite($instance);
    my $result = resolve_standard_concept({self => $instance, term => $term,
        domain => $domain // 'Condition', mapping_type => 'disease', source_field => 'diseases.diseaseCode'});
    close_connections_SQLite($instance);
    return $result;
}
my $term = {id => 'LOCAL:test', label => 'Acute viral pharyngitis'};
for my $id ('OHDSI:4163872', 'OHDSI:999999999', 'SNOMED:428251008') {
    my $result = mapped_lookup({from => 'id', column => 'id', aliases => {'LOCAL:test' => $id}}, $term);
    is($result->{concept_id}, 0, "invalid or wrong-domain ID $id cannot be rescued by the source label");
    like($result->{decision_reason}, qr/^mapped_/, 'failed mapping is also visible in the audit reason');
}
my $mapped = mapped_lookup({from => 'id', column => 'id', aliases => {'LOCAL:test' => 'ICD10CM:E11'}}, $term);
is($mapped->{concept_id}, 201826, 'configured nonstandard concept follows Maps to');
is($mapped->{target_label}, 'Type 2 diabetes mellitus', 'canonical label comes from database');
$mapped = mapped_lookup({from => 'id', column => 'id', aliases => {'ICD10CM:E11' => 'OHDSI:4112343'}}, {id => 'ICD10CM:E11', label => 'Original label'});
is($mapped->{source_concept_id}, 1567956, 'a genuine original source concept is retained');
is($mapped->{source_value}, 'Original label', 'reviewed ID does not replace source text');
$mapped = mapped_lookup({from => 'value', aliases => {'Local oral' => 'Oral'}}, {label => 'Local oral'}, 'Observation');
is($mapped->{concept_id}, 0, 'ambiguous alias is not automatically accepted');
is($mapped->{decision_reason}, 'mapped_label_ambiguous', 'ambiguity remains explicit');

for my $case ('target', 'field', 'from', 'id') {
    my $bad = dclone($compiled);
    $bad->{target}{model} = 'beacon' if $case eq 'target';
    $bad->{terminology}{geographicOrigin} = delete $bad->{terminology}{'diseases.diseaseCode'} if $case eq 'field';
    $bad->{terminology}{'diseases.diseaseCode'}{query}{from} = 'field' if $case eq 'from';
    $bad->{terminology}{'diseases.diseaseCode'}{query}{aliases}{'LOCAL:viral-pharyngitis'} = '4112343' if $case eq 'id';
    write_json_file("$tmp/bad.json", $bad);
    my $ok = eval { read_mapping_file({mapping_file => "$tmp/bad.json", schema_file => $schema}); 1 };
    ok(!$ok, "schema rejects invalid $case");
}

{
    local $ENV{CONVERT_PHENO_OHDSI_DB_DIR} = $db;
    my ($route) = grep {$_->{id} eq 'bff2omop'} @{catalog()->{data}};
    ok(grep($_->{name} eq 'mapping' && !$_->{required}, @{$route->{input}{files}}), 'desktop catalog exposes optional terminology mapping');
    my $result = execute_files('bff2omop', {options => {}}, {
        source => [{path => 't/bff2omop/in/local-terms.json', filename => 'local-terms.json'}],
        mapping => [{path => $mapping, filename => 'terminology.yaml'}],
    }, {workspace => $tmp});
    ok(@{$result->{artifacts}}, 'HTTP file conversion accepts optional mapping');
}
done_testing;
