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

use Convert::Pheno::HTTP::Service qw(catalog execute execute_files health is_service_error);
use Mojo::File ();
use Mojo::JSON qw(decode_json false);

my $MAX_UPLOAD_BYTES = $ENV{CONVERT_PHENO_HTTP_MAX_UPLOAD_BYTES} || 100 * 1024 * 1024;

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

post '/api/conversions/:conversion' => sub {
    my $c          = shift;
    my $conversion = $c->param('conversion');
    my $content_type = $c->req->headers->content_type || q{};

    if ( $content_type =~ m{\Amultipart/form-data\b}i ) {
        my $raw_request = $c->param('request') // '{}';
        my $request = eval { decode_json($raw_request) };
        return render_error( $c, 422, 'invalid_request',
            "Multipart field 'request' must contain valid JSON", $conversion )
          if $@ || ref($request) ne 'HASH';

        my $workspace = tempdir( 'convert-pheno-http-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
        my ( %files, $total, $index );
        for my $upload ( @{ $c->req->uploads || [] } ) {
            my $role = $upload->name;
            next if !defined $role || $role eq 'request';
            my $filename = $upload->filename // 'upload';
            my $safe = $filename;
            $safe =~ s{.*[\\/]}{};
            $safe =~ s{[^A-Za-z0-9._-]}{_}g;
            $safe = 'upload' unless length $safe;
            my $size = $upload->size || 0;
            $total += $size;
            return render_error( $c, 413, 'request_too_large',
                'Uploaded files exceed the 100 MiB request limit', $conversion )
              if $total > $MAX_UPLOAD_BYTES;
            my $destination = catfile( $workspace, sprintf( '%03d-%s', ++$index, $safe ) );
            $upload->move_to($destination);
            push @{ $files{$role} }, {
                path     => $destination,
                filename => $filename,
                size     => $size,
            };
        }

        return render_service_call(
            $c, $conversion,
            sub {
                execute_files( $conversion, $request, \%files,
                    { workspace => $workspace } );
            }
        );
    }

    my $request = $c->req->json;
    return render_error( $c, 422, 'invalid_request',
        'Request body must contain valid JSON', $conversion )
      unless defined $request;
    return render_service_call( $c, $conversion,
        sub { execute( $conversion, $request ) } );
};

# The workbench can load only these bundled, synthetic examples. The source
# name is resolved through the allowlist above and is never treated as a path.
get '/examples/:source' => sub {
    my $c       = shift;
    my $source  = $c->param('source');
    my $package = $EXAMPLE_FILE_FIXTURE{$source};
    my $transport = $c->param('transport');
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

# The production React bundle is optional in a source checkout and is copied
# into app/dist by the frontend build stage in the container image.
my $app_dist = catdir( $API_DIR, '..', '..', 'app', 'dist' );
push @{ app->static->paths }, $app_dist if -d $app_dist;

get '/' => sub {
    my $c = shift;
    return $c->reply->static('index.html') if -f "$app_dist/index.html";
    return $c->render(
        text   => 'Convert-Pheno UI has not been built. Run npm install && npm run build in app/.',
        status => 503,
    );
};

get '/*route_path' => sub {
    my $c = shift;
    return $c->reply->static('index.html')
      if -f "$app_dist/index.html" && $c->param('route_path') !~ m{\Aapi(?:/|\z)};
    return $c->reply->not_found;
};

app->config( hypnotoad => { listen => ['http://*:8080'] } );
app->max_request_size( $MAX_UPLOAD_BYTES + 1024 * 1024 );
app->start unless caller;
app;
