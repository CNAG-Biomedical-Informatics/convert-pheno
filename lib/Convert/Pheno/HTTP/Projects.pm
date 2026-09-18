package Convert::Pheno::HTTP::Projects;

use strict;
use warnings;
use File::Spec;
use Path::Tiny qw(path);
use JSON::XS;
use Convert::Pheno::IO::Atomic qw(write_atomically);

my $json = JSON::XS->new->utf8->canonical->pretty;
sub _settings {
    my ($data) = @_;
    die "Invalid project settings\n" unless ref($data) eq 'HASH' && defined($data->{conversion}) && !ref($data->{conversion})
      && ref($data->{options}) eq 'HASH' && ref($data->{output}) eq 'HASH';
    if (exists $data->{output}{entities}) {
        die "Invalid project entities\n" unless ref($data->{output}{entities}) eq 'ARRAY'
          && !grep { !defined($_) || ref($_) } @{$data->{output}{entities}};
    }
}
sub _write {
    my ($file, $value) = @_;
    write_atomically($file, sub { path($_[0])->spew_raw($json->encode($value)) });
}
sub _read {
    my ($file) = @_;
    die "Select a project smaller than 4 MiB\n" unless -f $file && !-l $file && -s $file <= 4194304;
    my $data = $json->decode(path($file)->slurp_raw);
    die "Unsupported Convert-Pheno project\n" unless ref($data) eq 'HASH'
      && ($data->{format} || '') eq 'convert-pheno-project' && ($data->{version} || 0) == 1
      && ref($data->{settings}) eq 'HASH' && ref($data->{sources}) eq 'HASH';
    _settings($data->{settings});
    die "Invalid project run references\n" if exists($data->{runs}) && (ref($data->{runs}) ne 'ARRAY' || grep {ref($_) || !defined($_)} @{$data->{runs}});
    return $data;
}

# These operations are available only behind native authorization. A project
# manifest must never grant arbitrary filesystem access to an HTTP client.
sub save {
    my ($jobs, $file, $data) = @_;
    die "Invalid project contents\n" unless ref($data) eq 'HASH' && ref($data->{settings}) eq 'HASH';
    _settings($data->{settings});
    die "Invalid project files\n" unless ref($data->{files} || {}) eq 'HASH';
    die "Use a .cpheno project filename\n" unless defined($file) && !ref($file) && $file =~ /\.cpheno\z/i;
    die "Project location is unavailable\n" unless -d path($file)->parent && !-l $file;
    _read($file) if -e $file;
    # Grants use canonical paths. Resolve the project directory too, otherwise
    # macOS /var -> /private/var (or another directory symlink) breaks references.
    my $parent = path($file)->parent->realpath;
    $file = "@{[$parent->child(path($file)->basename)]}";
    my $assets = path("$file.data");
    die "Project data folder must not be a symbolic link\n" if -l $assets;
    # Use a new snapshot so a failed save cannot invalidate the previous manifest.
    $assets->mkpath({mode => 0700});
    my $snapshot = Path::Tiny->tempdir('save-XXXXXXXX', DIR => "$assets", CLEANUP => 0);
    my $reference = sub { File::Spec->abs2rel("$_[0]", "$parent") };
    my %sources;
    for my $role (keys %{$data->{files} || {}}) {
        next if $role eq 'mapping' && length($data->{mapping} || '');
        die "Invalid input role\n" unless $role =~ /\A[a-zA-Z0-9_-]+\z/ && ref($data->{files}{$role}) eq 'ARRAY';
        for my $id (@{$data->{files}{$role}}) {
            my $source = $jobs->resolve_grant($id);
            my $relative = File::Spec->abs2rel($source, $jobs->{root});
            if ($jobs->{project_owned}{$id} || ($relative !~ /^\.\.(?:[\\\/]|$)/ && !File::Spec->file_name_is_absolute($relative))) {
                die "Managed input must be a file\n" unless -f $source;
                my $copy = $snapshot->child($role . '-' . scalar(@{$sources{$role} || []}) . '-' . path($source)->basename);
                path($source)->copy($copy);
                $copy->chmod(0600);
                $source = "$copy";
            }
            push @{$sources{$role}}, {path => $reference->($source), directory => -d $source ? JSON::XS::true : JSON::XS::false,
                owned => "$source" =~ /^\Q$snapshot\E/ ? JSON::XS::true : JSON::XS::false};
        }
    }
    my %saved = (format => 'convert-pheno-project', version => 1,
        settings => $data->{settings}, sources => \%sources,
        runs => $data->{runs} || [], mappingDirty => $data->{mappingDirty} ? JSON::XS::true : JSON::XS::false);
    for my $part (qw(jsonInput mapping)) {
        next unless defined($data->{$part}) && length($data->{$part});
        die "Invalid project text\n" if ref($data->{$part}) || length($data->{$part}) > 104857600;
        my $target = $snapshot->child($part eq 'mapping' ? 'mapping.yaml' : 'input.json');
        $target->spew_utf8($data->{$part});
        $target->chmod(0600);
        $saved{$part} = $reference->($target);
        # Reopen with the exact editor snapshot, not a potentially changed
        # original mapping. Unfinished edits still require validation in the UI.
        $sources{mapping} = [{path => $saved{$part}, directory => JSON::XS::false, owned => JSON::XS::true}]
          if $part eq 'mapping';
    }
    $saved{destination} = $reference->($jobs->resolve_grant($data->{destination})) if $data->{destination};
    _write($file, \%saved);
    my $handle = $jobs->register_file($file);
    $handle->{displayPath} = $jobs->resolve_grant($handle->{id});
    return {file => $handle};
}

sub open {
    my ($jobs, $file) = @_;
    my $saved = _read($file);
    my $parent = path($file)->parent->realpath;
    my $resolve = sub {
        my ($value) = @_;
        die "Invalid path in project\n" if !defined($value) || ref($value) || $value =~ /\0/;
        return File::Spec->rel2abs($value, "$parent");
    };
    my (%files, @missing);
    for my $role (sort keys %{$saved->{sources}}) {
        die "Invalid project sources\n" unless $role =~ /\A[a-zA-Z0-9_-]+\z/ && ref($saved->{sources}{$role}) eq 'ARRAY';
        for my $index (0 .. $#{$saved->{sources}{$role}}) {
            my $entry = $saved->{sources}{$role}[$index];
            die "Invalid project source\n" unless ref($entry) eq 'HASH';
            my $source = $resolve->($entry->{path});
            my $handle = eval {
                die "Input type changed\n" if $entry->{directory} ? !-d $source : !-f $source;
                $jobs->register_file($source);
            };
            if ($handle) {
                $handle->{displayPath} = $jobs->resolve_grant($handle->{id});
                $jobs->{project_owned}{$handle->{id}} = 1 if $entry->{owned};
                push @{$files{$role}}, $handle;
            }
            else { push @missing, {role => $role, index => $index, path => $entry->{path}, directory => $entry->{directory} || JSON::XS::false} }
        }
    }
    my %result = (file => $jobs->register_file($file), settings => $saved->{settings}, files => \%files,
        missing => \@missing, runs => $saved->{runs} || [], mappingDirty => $saved->{mappingDirty} || JSON::XS::false);
    $result{file}{displayPath} = $jobs->resolve_grant($result{file}{id});
    for my $part (qw(jsonInput mapping)) {
        next unless $saved->{$part};
        my $source = $resolve->($saved->{$part});
        # Project-owned text is required: silently dropping it would lose work.
        die "Missing project data: $saved->{$part}. Restore the companion .cpheno.data folder.\n"
          unless -f $source && !-l $source && -s $source <= 104857600;
        $result{$part} = path($source)->slurp_utf8;
    }
    if ($saved->{destination}) {
        $result{destination} = eval {$jobs->register_file($resolve->($saved->{destination}))};
        $result{destination}{displayPath} = $jobs->resolve_grant($result{destination}{id}) if $result{destination};
        push @missing, {role => 'destination', path => $saved->{destination}, directory => JSON::XS::true} unless $result{destination};
    }
    return \%result;
}
1;
