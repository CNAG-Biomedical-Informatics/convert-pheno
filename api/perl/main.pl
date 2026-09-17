#!/usr/bin/env perl

use strict;
use warnings;

use Mojolicious::Lite;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec::Functions qw(catdir catfile);
use File::Temp qw(tempdir);
use IO::Compress::Zip qw($ZipError);
use MIME::Base64 qw(encode_base64);

our $API_DIR;
BEGIN {
    $API_DIR = dirname( abs_path(__FILE__) );
    require lib;
    lib->import("$API_DIR/../../lib");
}

use Convert::Pheno::HTTP::Service qw(catalog execute execute_files health is_service_error lookup_omop_concept);
use Convert::Pheno::HTTP::Jobs;
use Mojo::Util qw(secure_compare);
use Mojo::File ();
use Mojo::JSON qw(decode_json false);

my $MAX_UPLOAD_BYTES = $ENV{CONVERT_PHENO_HTTP_MAX_UPLOAD_BYTES} || 100 * 1024 * 1024;
my $token = $ENV{CONVERT_PHENO_API_TOKEN} || die "Set CONVERT_PHENO_API_TOKEN before starting the API\n";
die "API token must contain at least 32 characters\n" if length($token) < 32;
my $jobs = Convert::Pheno::HTTP::Jobs->new(
    root => $ENV{CONVERT_PHENO_STATE_DIR} || catdir($ENV{HOME} || $ENV{LOCALAPPDATA} || '.', '.convert-pheno', 'runs'),
    worker => catfile($API_DIR, 'worker.pl'),
);
END {
    # Reaping workers must not replace the server or test process exit status.
    local $?;
    $jobs->shutdown if $jobs;
}

hook before_dispatch => sub {
    my ($c) = @_;
    my $host = $c->req->url->to_abs->host || '';
    my %hosts = map { $_ => 1 } split /,/, ($ENV{CONVERT_PHENO_API_HOSTS} || '127.0.0.1,localhost');
    unless ($hosts{$host}) {
        $c->app->log->warn("Rejected service host <$host>");
        return $c->render(status=>403,json=>{ok=>false,error=>{message=>'Unrecognized service host'}});
    }
    my $origin = $c->req->headers->origin;
    if (defined $origin) {
        my %origins = map { $_ => 1 } split /,/, ($ENV{CONVERT_PHENO_API_ORIGINS} || 'tauri://localhost,http://tauri.localhost,https://tauri.localhost');
        unless ($origins{$origin}) {
            $c->app->log->warn("Rejected application origin <$origin>");
            return $c->render(status=>403,json=>{ok=>false,error=>{message=>'Unrecognized application origin'}});
        }
        $c->res->headers->header('Access-Control-Allow-Origin' => $origin);
        $c->res->headers->header('Vary' => 'Origin');
        $c->res->headers->header('Access-Control-Allow-Headers' => 'Authorization, Content-Type');
        $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
        return $c->render(status=>204,text=>'') if $c->req->method eq 'OPTIONS';
    }
    return $c->render(status=>401,json=>{ok=>false,error=>{message=>'API authentication required'}})
      unless secure_compare($c->req->headers->authorization || '', "Bearer $token");
};

my %EXAMPLE_FIXTURE = (
    beacon => {
        file     => catfile( $API_DIR, '..', '..', 't', 'bff2pxf', 'in', 'individuals.json' ),
        filename => 'beacon-individuals-example.json',
    },
    pxf => {
        file     => catfile( $API_DIR, '..', '..', 't', 'pxf2bff', 'in', 'pxf.json' ),
        filename => 'phenopacket-example.json',
    },
    fhir => {
        file     => catfile( $API_DIR, '..', '..', 't', 'fhir2bff', 'in', 'patient-bundle.json' ),
        filename => 'fhir-bundle-example.json',
    },
    openehr => {
        file     => catfile( $API_DIR, '..', '..', 't', 'openehr2bff', 'in', 'gecco_personendaten_patient.json' ),
        filename => 'openehr-patient-example.json',
    },
    omop => {
        file     => catfile( $API_DIR, '..', '..', 't', 'fixtures', 'http-omop-request.json' ),
        filename => 'omop-tables-example.json',
        unwrap   => 1,
    },
);

my $TEST_DIR = catdir( $API_DIR, '..', '..', 't' );
my %EXAMPLE_FILE_FIXTURE = (
    cbioportal => {
        files => [
            { role => 'source', directory => catdir( $TEST_DIR, 'cbioportal2bff', 'in', 'acyc_mgh_2016' ), filename => 'acyc_mgh_2016.zip' },
            { role => 'mapping', file => catfile( $TEST_DIR, 'cbioportal2bff', 'in', 'cbioportal_mapping.yaml' ) },
        ],
    },
    'cdisc-odm' => {
        files => [
            { role => 'source', file => catfile( $TEST_DIR, 'cdiscodm2bff', 'in', 'cdisc_odm_data.xml' ) },
            { role => 'dictionary', file => catfile( $TEST_DIR, 'redcap2bff', 'in', 'redcap_dictionary.csv' ) },
            { role => 'mapping', file => catfile( $TEST_DIR, 'redcap2bff', 'in', 'redcap_mapping.yaml' ) },
        ],
    },
    csv => {
        options => { separator => ',' },
        files => [
            { role => 'source', file => catfile( $TEST_DIR, 'csv2bff', 'in', 'csv_data.csv' ) },
            { role => 'mapping', file => catfile( $TEST_DIR, 'csv2bff', 'in', 'csv_mapping.yaml' ) },
        ],
    },
    fhir => {
        json_default => 1,
        files => [
            { role => 'source', file => catfile( $TEST_DIR, 'fhir2bff', 'in', 'patient-bundle.json' ) },
        ],
    },
    'dataset-json' => {
        files => [
            ( map { +{ role => 'source', file => $_ } }
                sort glob catfile( $TEST_DIR, 'datasetjson2bff', 'in', '*.json' ) ),
            { role => 'mapping', file => catfile( $TEST_DIR, 'datasetjson2bff', 'in', 'sdtm_terminology.yaml' ) },
        ],
    },
    'dataset-xml' => {
        files => [
            ( map { +{ role => 'source', file => catfile( $TEST_DIR, 'datasetxml2bff', 'in', "$_.xml" ) } }
                qw(dm mh lb ts) ),
            { role => 'define', file => catfile( $TEST_DIR, 'datasetxml2bff', 'in', 'define.xml' ) },
        ],
    },
    i2b2 => {
        files => [
            { role => 'source', directory => catdir( $TEST_DIR, 'i2b22bff', 'in' ), filename => 'i2b2-tables.zip' },
        ],
    },
    omop => {
        files => [ map { +{ role => 'source', file => catfile( $TEST_DIR, 'omop2bff', 'in', $_ ) } }
            qw(CONCEPT.csv DRUG_EXPOSURE.csv PERSON.csv) ],
    },
    openehr => {
        json_default => 1,
        files => [
            { role => 'source', file => catfile( $TEST_DIR, 'openehr2bff', 'in', 'gecco_personendaten_patient.json' ) },
        ],
    },
    pxf => {
        json_default => 1,
        files => [
            { role => 'source', file => catfile( $TEST_DIR, 'pxf2bff', 'in', 'pxf.json' ) },
        ],
    },
    redcap => {
        files => [
            { role => 'source', file => catfile( $TEST_DIR, 'redcap2bff', 'in', 'redcap_data.csv' ) },
            { role => 'dictionary', file => catfile( $TEST_DIR, 'redcap2bff', 'in', 'redcap_dictionary.csv' ) },
            { role => 'mapping', file => catfile( $TEST_DIR, 'redcap2bff', 'in', 'redcap_mapping.yaml' ) },
        ],
    },
    pcornet => {
        files => [
            { role => 'source', directory => catdir( $TEST_DIR, 'pcornet2bff', 'in' ), filename => 'pcornet-tables.zip' },
        ],
    },
    sentinel => {
        files => [
            { role => 'source', directory => catdir( $TEST_DIR, 'sentinel2bff', 'in' ), filename => 'sentinel-tables.zip' },
        ],
    },
);

sub zip_fixture_directory {
    my ($directory) = @_;
    my @files;
    find(
        {
            no_chdir => 1,
            wanted   => sub { push @files, $File::Find::name if -f $File::Find::name },
        },
        $directory,
    );
    my $content = q{};
    my $zip;
    for my $file ( sort @files ) {
        my $name = $file;
        $name =~ s{^\Q$directory\E[\\/]*}{};
        $name =~ tr{\\}{/};
        if ($zip) {
            $zip->newStream( Name => $name )
              or die "Cannot add <$name> to example ZIP: $ZipError";
        }
        else {
            $zip = IO::Compress::Zip->new( \$content, Name => $name )
              or die "Cannot create example ZIP: $ZipError";
        }
        $zip->print( Mojo::File::path($file)->slurp );
    }
    $zip->close if $zip;
    return $content;
}

sub encoded_example_file {
    my ($definition) = @_;
    my $filename = $definition->{filename}
      || Mojo::File::path( $definition->{file} )->basename;
    my $content = $definition->{directory}
      ? zip_fixture_directory( $definition->{directory} )
      : Mojo::File::path( $definition->{file} )->slurp;
    return {
        role     => $definition->{role},
        filename => $filename,
        encoding => 'base64',
        content  => encode_base64( $content, q{} ),
    };
}

sub render_error {
    my ( $c, $status, $code, $message, $conversion ) = @_;
    my $body = {
        ok    => false,
        error => { code => $code, message => $message },
    };
    $body->{meta} = { conversion => $conversion } if defined $conversion;
    return $c->render( json => $body, status => $status );
}

sub render_service_call {
    my ( $c, $conversion, $code ) = @_;
    my $result = eval { $code->() };
    if ( my $error = $@ ) {
        if ( is_service_error($error) ) {
            return render_error(
                $c, $error->status, $error->code, $error->message, $conversion
            );
        }
        return render_error(
            $c, 500, 'infrastructure_error',
            'The local conversion service failed unexpectedly', $conversion
        );
    }
    return $c->render( json => $result );
}

get '/api/health' => sub {
    my $c = shift;
    return render_service_call( $c, undef, sub { health() } );
};

get '/api/conversions' => sub {
    my $c = shift;
    return render_service_call( $c, undef, sub { catalog() } );
};
get '/api/ontology/omop/:concept' => sub {
    my $c = shift;
    return render_service_call($c, undef, sub {
        return {ok => Mojo::JSON->true, data => lookup_omop_concept($c->param('concept'))};
    });
};

sub job_call {
    my ($c,$callback,$status)=@_;
    my $result=eval {$callback->()};
    if ($@) { my $message="$@"; $message =~ s/\s+at \S+ line \d+.*//s; return render_error($c,422,'invalid_request',$message) }
    return $c->render(status=>$status || 200,json=>{ok=>Mojo::JSON->true,data=>$result});
}

post '/api/shutdown' => sub {
    my $c = shift;
    my $local = $ENV{CONVERT_PHENO_LOCAL_TOKEN};
    return render_error($c,403,'local_access_denied','Native shutdown is not authorized')
      unless $local && secure_compare($c->req->headers->header('X-Convert-Pheno-Local') || '',$local);
    $jobs->shutdown;
    $c->render(json => {ok => Mojo::JSON->true});
    Mojo::IOLoop->timer(0.2 => sub { Mojo::IOLoop->stop });
};

post '/api/inputs/local' => sub {
    my $c=shift;
    my $local=$ENV{CONVERT_PHENO_LOCAL_TOKEN};
    return render_error($c,403,'local_access_denied','Native file selection is not authorized')
      unless $local && secure_compare($c->req->headers->header('X-Convert-Pheno-Local') || '',$local);
    job_call($c,sub {
        my $body=$c->req->json;
        die "Provide selected paths\n" unless ref($body) eq 'HASH' && ref($body->{paths}) eq 'ARRAY' && @{$body->{paths}} <=128;
        return [map {$jobs->register_file($_)} @{$body->{paths}}];
    },201);
};

post '/api/inputs' => sub {
    my $c=shift;
    job_call($c,sub {
        my $uploads=$c->req->uploads || [];
        die "Provide at least one file\n" unless @$uploads && @$uploads<=128;
        my $total=0; $total+=$_->size for @$uploads;
        die "Uploaded files exceed the request limit\n" if $total>$MAX_UPLOAD_BYTES;
        my $folder=tempdir('uploads-XXXXXX',DIR=>$jobs->{root},CLEANUP=>0);
        my @result;
        for my $upload (@$uploads) {
            my $name=$upload->filename || 'input'; $name =~ s{.*[\\/]}{}; $name =~ s{[^A-Za-z0-9._-]}{_}g;
            $name='input' if $name eq '.' || $name eq '..';
            my $file=catfile($folder,sprintf('%03d-',scalar @result).$name);
            $upload->move_to($file);
            push @result,$jobs->register_file($file);
        }
        return \@result;
    },201);
};

get '/api/jobs' => sub { my $c=shift; job_call($c,sub {$jobs->list}) };
post '/api/jobs/cancel-pending' => sub { my $c=shift; job_call($c,sub {$jobs->cancel_pending}) };
get '/api/inputs/:id/preview' => sub {my $c=shift; job_call($c,sub {$jobs->input_preview($c->param('id'))})};
post '/api/mappings' => sub {my $c=shift; job_call($c,sub {$jobs->save_mapping(($c->req->json || {})->{text})},201)};
post '/api/projects/local/:operation' => sub {
    my $c = shift;
    my $local = $ENV{CONVERT_PHENO_LOCAL_TOKEN};
    return render_error($c,403,'local_access_denied','Native project access is not authorized')
      unless $local && secure_compare($c->req->headers->header('X-Convert-Pheno-Local') || '', $local);
    job_call($c, sub {
        require Convert::Pheno::HTTP::Projects;
        my $body = $c->req->json || {};
        my $file = $body->{handle} ? $jobs->resolve_grant($body->{handle}) : $body->{path};
        return Convert::Pheno::HTTP::Projects::save($jobs, $file, $body->{data}) if $c->param('operation') eq 'save';
        return Convert::Pheno::HTTP::Projects::open($jobs, $file) if $c->param('operation') eq 'open';
        die "Unknown project operation\n";
    });
};
get '/api/resources' => sub {my $c=shift; job_call($c,sub {
    my $manifest=Convert::Pheno::DB::Bundle::bundle_manifest($Convert::Pheno::share_dir);
    return [map {my $id=$_; my $entry=$manifest->{databases}{$id};
        my $file=$id eq 'ohdsi' && $ENV{CONVERT_PHENO_OHDSI_DB_DIR} ? catfile($ENV{CONVERT_PHENO_OHDSI_DB_DIR},'ohdsi.db')
          : Convert::Pheno::DB::Bundle::bundled_database_path($Convert::Pheno::share_dir,$id);
        +{id=>$id,%$entry,installed=>-f $file ? Mojo::JSON->true : false};
    } sort keys %{$manifest->{databases}}];
})};
post '/api/resources/local-directory' => sub {
    my $c=shift;
    my $local=$ENV{CONVERT_PHENO_LOCAL_TOKEN};
    return render_error($c,403,'local_access_denied','Native resource selection is not authorized')
      unless $local && secure_compare($c->req->headers->header('X-Convert-Pheno-Local') || '',$local);
    job_call($c,sub {
        die "Wait for active and queued conversions before changing the resource folder\n"
          if grep {$_->{status} =~ /\A(?:queued|running|cancelling)\z/} @{$jobs->list};
        my $directory=($c->req->json || {})->{directory};
        die "Select an existing resource folder\n" unless defined $directory && !ref $directory && -d $directory;
        $ENV{CONVERT_PHENO_OHDSI_DB_DIR}=abs_path($directory);
        return {directory=>$ENV{CONVERT_PHENO_OHDSI_DB_DIR}};
    });
};
post '/api/jobs' => sub { my $c=shift; job_call($c,sub {$jobs->submit($c->req->json)},202) };
get '/api/jobs/:id' => sub { my $c=shift; job_call($c,sub {$jobs->status($c->param('id'))}) };
post '/api/jobs/:id/cancel' => sub { my $c=shift; job_call($c,sub {$jobs->cancel($c->param('id'))}) };
del '/api/jobs/:id' => sub { my $c=shift; job_call($c,sub {$jobs->delete_history($c->param('id'))}) };
del '/api/jobs' => sub { my $c=shift; job_call($c,sub {$jobs->delete_all(0)}) };
post '/api/jobs/delete-all-files' => sub { my $c=shift; job_call($c,sub {$jobs->delete_all(1)}) };
del '/api/jobs/:id/files' => sub { my $c=shift; job_call($c,sub {$jobs->delete_files($c->param('id'))}) };
get '/api/jobs/:id/outputs/:artifact/preview' => sub {
    my $c=shift; job_call($c,sub {$jobs->preview($c->param('id'),$c->param('artifact'))});
};
get '/api/jobs/:id/outputs/:artifact/download' => sub {
    my $c=shift;
    my ($file,$entry)=eval {$jobs->artifact($c->param('id'),$c->param('artifact'))};
    return render_error($c,404,'output_unavailable','Output is unavailable') if $@;
    $c->res->headers->content_type($entry->{mediaType});
    $c->res->headers->content_disposition('attachment; filename="'.$entry->{filename}.'"');
    return $c->reply->file("$file");
};


# The workbench can load only these bundled, synthetic examples. The source
# name is resolved through the allowlist above and is never treated as a path.
get '/examples/:source' => sub {
    my $c       = shift;
    my $source  = $c->param('source');
    my $package = $EXAMPLE_FILE_FIXTURE{$source};
    my $transport = $c->param('transport');
    # Accepted input transports do not imply that every transport has a fixture.
    # Desktop callers ask the engine to choose the available example format.
    $transport = $EXAMPLE_FIXTURE{$source} ? 'json' : 'multipart'
      if defined($transport) && $transport eq 'auto';
    $transport = $package && $package->{json_default} ? 'json' : 'multipart'
      unless defined $transport && length $transport;
    if ( $package && $transport eq 'multipart' ) {
        my $files = eval {
            [ map { encoded_example_file($_) } @{ $package->{files} } ];
        };
        return render_error( $c, 500, 'infrastructure_error',
            'The bundled example could not be loaded' )
          if $@;
        return $c->render(
            json => {
                ok   => Mojo::JSON->true,
                data => {
                    transport => 'multipart',
                    files     => $files,
                    options   => $package->{options} || {},
                },
                meta => { source => $source, filename => 'synthetic-fixture-package' },
            }
        );
    }

    my $fixture = $EXAMPLE_FIXTURE{$source};
    return render_error( $c, 404, 'unknown_example', 'No example is available for this source' )
      unless $fixture;

    my $data = eval { decode_json( Mojo::File::path( $fixture->{file} )->slurp ) };
    return render_error( $c, 500, 'infrastructure_error', 'The bundled example could not be loaded' )
      if $@;
    $data = $data->{input}{data} if $fixture->{unwrap};

    return $c->render(
        json => {
            ok   => Mojo::JSON->true,
            data => $data,
            meta => { source => $source, filename => $fixture->{filename} },
        }
    );
};

# The desktop frontend is bundled by Tauri. This process serves the API only.

app->config( hypnotoad => { listen => ['http://*:8080'] } );
app->max_request_size( $MAX_UPLOAD_BYTES + 1024 * 1024 );
app->start unless caller;
app;
