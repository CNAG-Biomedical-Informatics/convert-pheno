package Convert::Pheno::HTTP::Jobs;

use strict;
use warnings;
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Encode qw(decode FB_DEFAULT);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path remove_tree);
use File::Spec;
use Fcntl qw(LOCK_EX LOCK_SH LOCK_NB);
use IPC::Open3 qw(open3);
use JSON::XS;
use Mojo::IOLoop;
use Mojo::Util qw(sha1_sum);
use Path::Tiny qw(path);
use POSIX qw(WNOHANG);
use Symbol qw(gensym);
use Convert::Pheno::HTTP::Service qw(execute execute_files catalog);
use Convert::Pheno::IO::Atomic qw(write_atomically);

my $JSON = JSON::XS->new->utf8->canonical->pretty;
my $MAX_CONCURRENT_JOBS = 16;

sub _validate_job_limit {
    my ($value, $maximum) = @_;
    $maximum //= $MAX_CONCURRENT_JOBS;
    die "Maximum concurrent jobs must be an integer from 1 to $maximum\n"
      unless defined($value) && !ref($value) && "$value" =~ /\A[1-9][0-9]*\z/
      && $value <= $maximum;
    return 0 + $value;
}

sub _metadata_lock {
    my ($file, $mode) = @_;
    # Lock a stable sibling, not the JSON inode replaced by atomic writes.
    # Windows readers must not overlap replacement (including its backup gap).
    # Keep this file in place: unlinking it could create two independent locks.
    my $lockfile = path($file)->parent->child('.metadata.lock');
    open my $lock, '>>', $lockfile
      or die "Cannot open job metadata lock <$lockfile>: $!\n";
    flock($lock, $mode)
      or die "Cannot lock job metadata <$lockfile>: $!\n";
    return $lock;
}

sub _write {
    my ($file, $data) = @_;
    my $lock = _metadata_lock($file, LOCK_EX);
    write_atomically($file, sub { path($_[0])->spew_raw($JSON->encode($data)) });
}
sub _read {
    my ($file) = @_;
    my $lock = _metadata_lock($file, LOCK_SH);
    return $JSON->decode(path($file)->slurp_raw);
}
sub _id { sha1_sum(join ':', $$, rand(), time(), {}) }
sub _resolved_path {
    my ($value) = @_;
    return unless defined $value;
    $value = "$value";
    my $resolved = abs_path($value);
    if (!defined $resolved) {
        my $candidate = path($value);
        my $parent = abs_path("@{[$candidate->parent]}");
        $resolved = defined($parent)
          ? File::Spec->catfile($parent, $candidate->basename)
          : File::Spec->rel2abs($value);
    }
    return File::Spec->canonpath($resolved);
}
sub _path_key {
    my ($value) = @_;
    my $key = _resolved_path($value);
    return unless defined $key;
    if ($^O eq 'MSWin32') {
        $key =~ tr{\\}{/};
        $key = lc $key;
    }
    return $key;
}
sub _same_path {
    my ($left, $right) = @_;
    return defined($left) && defined($right) && _path_key($left) eq _path_key($right);
}
sub _worker_lock {
    my ($dir) = @_;
    open my $fh, '>>', path($dir, '.worker.lock') or die "Cannot lock run folder\n";
    flock($fh, LOCK_EX | LOCK_NB) or die "A previous conversion is still finishing; wait before reopening this workspace\n";
    return $fh;
}

sub _recover_publication {
    my ($dir, $status) = @_;
    my $journal = path($dir, 'publication.json');
    return $status unless -f $journal;
    my $publication = _read($journal);
    my $final = $status->{outputDirectory};
    my $default = path($dir, 'outputs');
    my $is_default = _same_path($final, $default);
    die "Invalid publication record\n" unless defined($final)
      && _same_path($publication->{final}, $final)
      && (path($final)->basename eq 'convert-pheno-'.$status->{id} || $is_default);
    my $staging = $is_default ? path($dir,'staging')
      : path($final)->parent->child('.convert-pheno-'.$status->{id});
    die "Invalid export staging record\n" unless _same_path($publication->{staging}, $staging);
    # Ownership markers prevent cleanup from following a replaced directory.
    # A final folder is published atomically only after every output was copied.
    for my $folder ($final, "$staging") {
        next unless -e $folder || -l $folder;
        my $marker = path($folder, '.convert-pheno-owner');
        next if _same_path($folder, $final) && !-e $marker && !-l $marker && !-l $folder
          && _same_path(abs_path($folder), $folder) && $status->{status} eq 'completed'
          && _same_path($status->{directory}, $final);
        die "Export folder changed; automatic recovery was not performed\n"
          if -l $folder || !_same_path(abs_path($folder), $folder) || !-f $marker || -l $marker
          || $marker->slurp_raw ne $publication->{owner};
    }
    if (-d $final) {
        $status = $publication->{completed};
        _write(path($dir,'status.json'), $status);
        my $marker = path($final,'.convert-pheno-owner');
        unlink $marker or die "Cannot clear publication marker\n" if -e $marker;
    }
    if (-d $staging) {
        remove_tree("$staging", {error => \my $errors});
        die "Cannot clean incomplete export\n" if @$errors;
    }
    unlink $journal or die "Cannot clear publication record\n";
    return $status;
}

sub new {
    my ($class, %args) = @_;
    die "Job storage and worker executable are required\n" unless $args{root} && $args{worker};
    make_path($args{root}, { mode => 0700 });
    my $self = bless { %args, root => _resolved_path($args{root}), queue => [], grants => {}, active => {} }, $class;
    # Recovery may rewrite run state, so only one supervisor may own this store.
    # Keep the handle open for its lifetime; do not unlink the lock file.
    open my $lock, '>>', path($self->{root}, '.supervisor.lock') or die "Cannot lock job storage\n";
    flock($lock, LOCK_EX | LOCK_NB) or die "This job storage is already in use by another Convert-Pheno service\n";
    $self->{storage_lock} = $lock;
    # Desktop supplies its platform-detected CPU limit. Standalone services
    # default to one worker unless the operator explicitly configures a limit.
    $self->{max_allowed_jobs} = _validate_job_limit($ENV{CONVERT_PHENO_JOB_LIMIT} // 1);
    my $settings_file = path($self->{root}, 'scheduler-settings.json');
    my $settings = -f $settings_file ? _read($settings_file) : {maxConcurrentJobs => 1};
    $self->{max_concurrent_jobs} = _validate_job_limit($settings->{maxConcurrentJobs});
    $self->{max_concurrent_jobs} = $self->{max_allowed_jobs}
      if $self->{max_concurrent_jobs} > $self->{max_allowed_jobs};
    my %worker_locks;
    # Preflight all runs before changing any state. A surviving child still owns
    # its run even if its former supervisor's store lock has been released.
    for my $dir (path($self->{root})->children) {
        next unless $dir->basename =~ /\A[a-f0-9]{40}\z/ && -f "$dir/status.json";
        $worker_locks{"$dir"} = _worker_lock($dir);
    }
    for my $dir (path($self->{root})->children) {
        next unless -f "$dir/status.json";
        my $status = eval { _read("$dir/status.json") } or next;
        $status = _recover_publication($dir, $status);
        if ($status->{status} =~ /\A(?:queued|running|cancelling)\z/) {
            $status->{status} = 'interrupted';
            $status->{message} = 'The service stopped before this run completed';
            $status->{finished} = time();
            _write("$dir/status.json", $status);
            remove_tree("$dir/staging");
        }
        unlink "$dir/request.json";
    }
    return $self;
}

sub settings {
    my ($self) = @_;
    return {maxConcurrentJobs => $self->{max_concurrent_jobs}, maxAllowedConcurrentJobs => $self->{max_allowed_jobs}};
}

sub update_settings {
    my ($self, $settings) = @_;
    die "The job service has stopped\n" if $self->{stopped};
    die "Provide only maxConcurrentJobs\n" unless ref($settings) eq 'HASH'
      && keys(%$settings) == 1 && exists $settings->{maxConcurrentJobs};
    my $limit = _validate_job_limit($settings->{maxConcurrentJobs}, $self->{max_allowed_jobs});
    _write(path($self->{root}, 'scheduler-settings.json'), {maxConcurrentJobs => $limit});
    $self->{max_concurrent_jobs} = $limit;
    $self->_next;
    return $self->settings;
}

sub register_file {
    my ($self, $file) = @_;
    die "Select an existing file or directory\n" if !defined($file) || ref($file) || -l $file;
    my $resolved = _resolved_path($file);
    die "Selected location is unavailable\n" unless $resolved && (-f $resolved || -d $resolved);
    my $id = _id();
    $self->{grants}{$id} = $resolved;
    return { id => $id, filename => path($resolved)->basename,
        directory => -d $resolved ? JSON::XS::true : JSON::XS::false,
        bytes => -f $resolved ? -s $resolved : 0 };
}

sub resolve_grant {
    my ($self, $id) = @_;
    die "Unknown or expired file selection; select the file again\n"
      unless defined($id) && !ref($id) && exists $self->{grants}{$id};
    my $file = $self->{grants}{$id};
    die "Selected location changed or is no longer available\n"
      unless !-l $file && -e $file && _same_path(abs_path($file), $file);
    return $file;
}

sub submit {
    my ($self, $request) = @_;
    die "The job service has stopped\n" if $self->{stopped};
    die "Request must be an object\n" unless ref($request) eq 'HASH';
    my %allowed = map { $_ => 1 } qw(conversion input output options destination);
    die "Unknown job field\n" if grep { !$allowed{$_} } keys %$request;
    die "The conversion queue is full\n" if @{$self->{queue}} >= 16;
    my $conversion = $request->{conversion};
    my ($route) = grep { defined($conversion) && !ref($conversion) && $_->{id} eq $conversion } @{catalog()->{data}};
    die "Unknown conversion\n" unless $route;
    die "$route->{unavailableReason}\n" unless $route->{available};
    my $input = $request->{input};
    die "Provide JSON data or selected input files\n" unless ref($input) eq 'HASH'
      && keys(%$input) == 1 && (exists $input->{data} || ref($input->{files}) eq 'HASH');
    my %files;
    for my $role (keys %{$input->{files} || {}}) {
        die "Selected files must be an array\n" unless ref($input->{files}{$role}) eq 'ARRAY';
        $files{$role} = [map {
            my $file = $self->resolve_grant($_);
            +{path => $file, filename => path($file)->basename};
        } @{$input->{files}{$role}}];
    }
    my $destination = exists $request->{destination} ? $self->resolve_grant($request->{destination}) : undef;
    die "Output destination must be a directory\n" if defined($destination) && !-d $destination;
    my $id = _id();
    my $dir = path($self->{root}, $id);
    $dir->mkpath({mode => 0700});
    my $status = { id => $id, conversion => $conversion, status => 'queued', created => time(),
        outputDirectory => _resolved_path($destination ? File::Spec->catdir($destination, 'convert-pheno-'.$id)
          : File::Spec->catdir("$dir", 'outputs')),
        options => $request->{options} || {}, output => $request->{output} || {},
        sources => [map { map { $_->{filename} } @$_ } values %files] };
    _write($dir->child('request.json'), { conversion => $conversion, files => \%files,
        request => { (exists($input->{data}) ? (input => {data => $input->{data}}) : ()),
            options => $request->{options} || {}, output => $request->{output} || {} },
        destination => $destination });
    _write($dir->child('status.json'), $status);
    push @{$self->{queue}}, $id;
    $self->_next;
    return $status;
}

sub _directory {
    my ($self, $id) = @_;
    die "Unknown run\n" unless defined($id) && !ref($id) && $id =~ /\A[a-f0-9]{40}\z/;
    my $dir = path($self->{root}, $id);
    die "Unknown run\n" unless -d $dir;
    my $lock = _metadata_lock($dir->child('status.json'), LOCK_SH);
    die "Unknown run\n" unless -f $dir->child('status.json');
    return $dir;
}
sub status {
    my ($self,$id)=@_;
    my $dir = $self->_directory($id);
    my $status = _read($dir->child('status.json'));
    # A worker records completed state before clearing its crash-recovery
    # journal. Do not expose that transient state as a finished run.
    $status = {%$status, status => 'running'}
      if $status->{status} eq 'completed' && -f $dir->child('publication.json');
    return $status;
}
sub delete_history {
    my ($self, $id) = @_;
    my $status = $self->status($id);
    die "Cancel this run and wait for it to stop before deleting it from history\n"
      unless $status->{status} =~ /\A(?:completed|failed|cancelled|interrupted)\z/;
    # Hide the entry, not its directory: default output files live beside status.json.
    # Never follow an outputDirectory or source path when removing a history entry.
    $status->{deletedFromHistory} = JSON::XS::true;
    _write($self->_directory($id)->child('status.json'), $status);
    return {id => $id, deletedFromHistory => JSON::XS::true};
}
sub delete_files {
    my ($self, $id) = @_;
    die "This run is still finishing; wait before deleting its files\n"
      if $self->{active}{$id};
    my $dir = $self->_directory($id);
    my $status = $self->status($id);
    die "Cancel this run and wait for it to stop before deleting files\n"
      unless $status->{status} =~ /\A(?:completed|failed|cancelled|interrupted)\z/;
    die "Run folder has moved or is a symbolic link\n"
      if -l $dir || !_same_path(abs_path($dir), $dir);
    my $output = $status->{directory} || $status->{outputDirectory};
    my $default = $dir->child('outputs');
    if (defined $output && (-e $output || -l $output)) {
        # Only the published run subfolder is eligible, never its selected parent.
        die "Output folder has moved or is not owned by this run\n"
          if -l $output || !-d $output || !_same_path(abs_path($output), $output)
          || (!_same_path($output, $default) && path($output)->basename ne "convert-pheno-$id")
          || !_same_path($output, $status->{outputDirectory});
        my %expected;
        for my $entry (@{$status->{result}{artifacts} || []}) {
            my $name = $entry->{filename};
            die "Invalid output filename\n" unless defined($name) && $name !~ m{[/\\]} && $name ne '.' && $name ne '..';
            $expected{$name} = 1;
        }
        for my $file (path($output)->children) {
            die "Output folder contains unrecognized files; remove them manually before deleting this run\n"
              unless $expected{$file->basename} && -f $file && !-l $file;
        }
    }
    for my $file ($dir->children) {
        die "Run folder contains unrecognized files; deletion was not performed\n"
          if -l $file || ($file->basename !~ /\A(?:status\.json|request\.json|\.worker\.lock|\.metadata\.lock|mapping-.+|outputs|staging)\z/);
    }
    # A previous output can be an input to another queued/running conversion.
    for my $other (@{$self->list}) {
        next unless $other->{status} =~ /\A(?:queued|running|cancelling)\z/;
        my $request = _read($self->_directory($other->{id})->child('request.json'));
        for my $files (values %{$request->{files} || {}}) {
            for my $entry (@$files) {
                for my $candidate ("$dir", defined($output) ? $output : ()) {
                    my $entry_key = _path_key($entry->{path});
                    my $candidate_key = _path_key($candidate);
                    die "Another active run uses these files; wait for it to finish\n"
                      if $entry_key eq $candidate_key || index($entry_key, "$candidate_key/") == 0;
                }
            }
        }
    }
    if (defined $output && -d $output) {
        for my $file (path($output)->children) { unlink $file or die "Could not delete an output file\n" }
        rmdir $output or die "Could not remove the output folder\n";
    }
    remove_tree("$dir", {error => \my $errors});
    die "Could not completely remove the run folder\n" if @$errors;
    return {id => $id, deletedFromDisk => JSON::XS::true};
}
sub list {
    my ($self, %args)=@_;
    my $runs = [sort { $b->{created} <=> $a->{created} } map { $self->status($_->basename) }
        grep {
            if ($_->basename =~ /\A[a-f0-9]{40}\z/ && -d $_) {
                my $lock = _metadata_lock($_->child('status.json'), LOCK_SH);
                -f $_->child('status.json');
            }
            else { 0 }
        } path($self->{root})->children];
    $runs = [grep { !$_->{deletedFromHistory} } @$runs] unless $args{include_deleted};
    my %positions;
    my $position = 0;
    $positions{$_} = ++$position for @{$self->{queue}};
    $_->{queuePosition} = $positions{$_->{id}} for grep { exists $positions{$_->{id}} } @$runs;
    return $runs;
}
sub delete_all {
    my ($self, $files) = @_;
    my (@deleted, @skipped, @failed);
    for my $run (@{$self->list(include_deleted => $files)}) {
        if ($run->{status} !~ /\A(?:completed|failed|cancelled|interrupted)\z/) {
            push @skipped, $run->{id}; next;
        }
        my $ok = eval { $files ? $self->delete_files($run->{id}) : $self->delete_history($run->{id}); 1 };
        if ($ok) { push @deleted, $run->{id} }
        else { my $message = "$@"; chomp $message; push @failed, {id=>$run->{id}, message=>$message} }
    }
    return {deleted=>\@deleted, skipped=>\@skipped, failed=>\@failed};
}

sub _next {
    my ($self)=@_;
    return if $self->{stopped};
    # Each independent conversion owns one process and a separate run folder.
    # Lowering the limit never interrupts existing workers.
    while (@{$self->{queue}} && keys(%{$self->{active}}) < $self->{max_concurrent_jobs}) {
        my $id = shift @{$self->{queue}};
        my $dir = $self->_directory($id);
        my $status = $self->status($id);
        $status->{status} = 'running';
        _write($dir->child('status.json'), $status);
        my ($stdin, $stdout, $stderr) = (gensym(), gensym(), gensym());
        my $pid = eval { open3($stdin, $stdout, $stderr, $^X, $self->{worker}, "$dir") };
        if (!$pid) {
            $status->{status} = 'failed'; $status->{message} = 'Could not start the conversion worker';
            $status->{finished} = time();
            _write($dir->child('status.json'), $status);
            unlink $dir->child('request.json');
            next;
        }
        close $stdin;
        $self->{active}{$id} = { id => $id, pid => $pid, stdout => $stdout, stderr => $stderr };
    }
    $self->{timer} = Mojo::IOLoop->recurring(0.2 => sub { $self->poll })
      if keys(%{$self->{active}}) && !defined($self->{timer});
}

sub poll {
    my ($self)=@_;
    for my $id (keys %{$self->{active}}) {
        my $active = $self->{active}{$id};
        next if waitpid($active->{pid}, WNOHANG) == 0;
        close $active->{stdout}; close $active->{stderr};
        my $dir = $self->_directory($active->{id});
        my $status = $self->status($active->{id});
        my $recovered = eval { _recover_publication($dir, $status) };
        if ($recovered) { $status = $recovered }
        else {
            $status->{status} = 'failed';
            $status->{message} = 'Export recovery could not safely clean the output folder. Files were retained for manual review.';
            $status->{finished} = time();
            _write($dir->child('status.json'), $status);
        }
        if ($status->{status} =~ /\A(?:running|cancelling)\z/) {
            $status->{status} = $active->{cancelled} ? 'cancelled' : 'failed';
            $status->{message} = $active->{cancelled} ? 'Conversion cancelled' : 'Conversion worker stopped unexpectedly';
            _write($dir->child('status.json'), $status);
        }
        remove_tree($dir->child('staging')) if $status->{status} ne 'completed';
        unlink $dir->child('request.json');
        delete $self->{active}{$id};
    }
    Mojo::IOLoop->remove(delete $self->{timer})
      if !keys(%{$self->{active}}) && defined($self->{timer});
    $self->_next;
}

sub cancel {
    my ($self,$id)=@_;
    $self->poll;
    my $status = $self->status($id);
    if ($status->{status} eq 'queued') {
        @{$self->{queue}} = grep { $_ ne $id } @{$self->{queue}};
        $status->{status} = 'cancelled';
        $status->{finished} = time();
        unlink $self->_directory($id)->child('request.json');
    } elsif ($status->{status} eq 'running') {
        die "This run does not belong to the active worker\n"
          unless $self->{active}{$id};
        $status->{status} = 'cancelling';
        $self->{active}{$id}{cancelled} = 1;
        kill 'KILL', $self->{active}{$id}{pid};
    }
    _write($self->_directory($id)->child('status.json'),$status);
    return $status;
}

sub cancel_pending {
    my ($self)=@_;
    # Detach the pending queue before polling, so none of these jobs can start
    # while the bulk cancellation is being processed.
    my @pending = @{$self->{queue}};
    $self->{queue} = [];
    return [map { $self->cancel($_) } @pending];
}

sub shutdown {
    my ($self)=@_;
    return if $self->{stopped};
    # Prevent polling/cancellation from starting queued work during shutdown.
    $self->{stopped} = 1;
    $self->cancel_pending;
    $self->cancel($_) for keys %{$self->{active}};
    for my $active (values %{$self->{active}}) {
        waitpid($active->{pid},0);
    }
    $self->poll;
    close(delete $self->{storage_lock}) if $self->{storage_lock};
}

sub artifact {
    my ($self,$id,$artifact)=@_;
    my $status = $self->status($id);
    die "Run has no completed outputs\n" unless $status->{status} eq 'completed';
    my ($entry) = grep { $_->{id} eq $artifact } @{$status->{result}{artifacts} || []};
    die "Unknown output file\n" unless $entry;
    my $file = path($status->{directory},$entry->{filename});
    die "Output file is missing or changed\n" if !-f $file || -l $file || -s $file != $entry->{bytes};
    return ($file, $entry);
}

sub preview {
    my ($self,$id,$artifact)=@_;
    my ($file,$entry)=$self->artifact($id,$artifact);
    return {kind => 'xlsx', text => 'Open the spreadsheet to inspect the complete report', truncated => JSON::XS::true}
      if $entry->{kind} eq 'xlsx';
    open my $fh,'<:raw',$file or die "Cannot open output\n";
    my $bytes=''; read($fh,$bytes,262144); close $fh;
    my $truncated = length($bytes) < -s $file;
    my $text = decode('UTF-8',$bytes,FB_DEFAULT);
    my $data = !$truncated && $entry->{kind} eq 'json' ? eval { $JSON->decode($bytes) } : undef;
    return {text => $text, (defined($data) ? (data => $data) : ()),
        truncated => $truncated ? JSON::XS::true : JSON::XS::false, kind => $entry->{kind}};
}

sub input_preview {
    my ($self,$handle)=@_;
    my $file=$self->resolve_grant($handle);
    if (-d $file) {
        opendir my $dh, $file or die "Cannot read selected directory\n";
        my (@names, $bytes, $truncated);
        while (defined(my $name = readdir $dh)) {
            next if $name eq '.' || $name eq '..';
            if (@names >= 1000 || ($bytes || 0) + length($name) + 1 > 262144) { $truncated = 1; last }
            push @names, $name;
            $bytes += length($name) + 1;
        }
        closedir $dh;
        return {text=>join("\n",sort @names),truncated=>$truncated ? JSON::XS::true : JSON::XS::false,
            previewNote=>'Directory listing: up to 1,000 entries and 256 KiB.'};
    }
    open my $fh,'<:raw',$file or die "Cannot read selected input\n";
    my $bytes=''; read($fh,$bytes,262144); close $fh;
    my ($kind) = $file =~ /\.(json|csv|tsv|yaml|xml)\z/i;
    return {text=>decode('UTF-8',$bytes,FB_DEFAULT),truncated=>length($bytes)<-s $file ? JSON::XS::true : JSON::XS::false,
        (defined($kind) ? (kind => lc($kind)) : ())};
}

sub save_mapping {
    my ($self,$text)=@_;
    die "Mapping text is missing or too large\n" if !defined($text) || ref($text) || length($text)>1048576;
    my $directory=path($self->{root},'mappings'); $directory->mkpath({mode=>0700});
    my $file=$directory->child(_id().'.yaml');
    $file->spew_utf8($text);
    my $ok=eval {
        require Convert::Pheno::IO::CSVHandler;
        Convert::Pheno::IO::CSVHandler::read_mapping_file({mapping_file=>"$file",
            schema_file=>File::Spec->catfile($Convert::Pheno::share_dir,'schema','mapping-v2.json')});
        1;
    };
    if (!$ok) {my $error=$@; unlink $file; die $error}
    return $self->register_file("$file");
}

# Worker entry point: request and outputs stay on disk, outside the HTTP event
# loop. The request is private operational state, never an application log.
sub perform {
    my ($class,$directory)=@_;
    my $dir=path($directory);
    my $lock = _worker_lock($dir);
    my $status=_read($dir->child('status.json'));
    die "This run is no longer active\n" unless $status->{status} eq 'running';
    my $job=_read($dir->child('request.json'));
    my $staging=$dir->child('staging'); $staging->mkpath({mode=>0700});
    my $ok=eval {
        my @fingerprints;
        for my $role (keys %{$job->{files}}) {
            for my $entry (@{$job->{files}{$role}}) {
                my $file=$entry->{path};
                die "Selected input is no longer available\n" if !-e $file || -l $file;
                if (-d $file) {
                    find({no_chdir=>1,wanted=>sub { die "Directory packages must not contain symbolic links\n" if -l $File::Find::name }},$file);
                }
                if (-f $file) {
                    open my $fh,'<:raw',$file or die "Cannot read selected input\n";
                    my $sha=Digest::SHA->new(256)->addfile($fh)->hexdigest; close $fh;
                    push @fingerprints,{filename=>$entry->{filename},role=>$role,sha256=>$sha};
                    if ($role eq 'mapping') {
                        my $snapshot=$dir->child('mapping-'.$entry->{filename});
                        copy($file,$snapshot) or die "Cannot snapshot mapping\n";
                        $entry->{path}="$snapshot";
                    }
                }
            }
        }
        my $delivery={directory=>"$staging",workspace=>"$staging",native=>1};
        my $result=exists($job->{request}{input})
          ? execute($job->{conversion},$job->{request},$delivery)
          : execute_files($job->{conversion},$job->{request},$job->{files},$delivery);
        my $final=path(_resolved_path($job->{destination}
          ? path($job->{destination},'convert-pheno-'.$status->{id}) : $dir->child('outputs')));
        die "Output destination already exists\n" if -e $final;
        if ($job->{destination}) {
            # Copy to a private sibling before the final rename so cross-volume
            # exports cannot expose a half-written run directory.
            my $sibling=path(_resolved_path(path($job->{destination},'.convert-pheno-'.$status->{id})));
            die "Output staging directory already exists\n" if -e $sibling;
            my $owner = _id();
            my $completed = {%$status, status=>'completed', result=>$result, directory=>"$final",
                fingerprints=>\@fingerprints, engineVersion=>$Convert::Pheno::VERSION, finished=>time()};
            # Journal ownership before copying large outputs. Recovery publishes
            # completed state if rename succeeded, otherwise removes only our copy.
            mkdir "$sibling",0700 or die "Cannot create export staging folder\n";
            $sibling->child('.convert-pheno-owner')->spew_raw($owner);
            _write($dir->child('publication.json'), {owner=>$owner,staging=>"$sibling",final=>"$final",completed=>$completed});
            eval { for my $file ($staging->children) { copy($file,$sibling->child($file->basename)) or die "Could not export output\n" } 1 }
              or do { my $err=$@; remove_tree($sibling); die $err };
            rename $sibling,$final or die "Could not publish output directory\n";
            remove_tree($staging);
        } else {
            my $owner = _id();
            my $completed = {%$status, status=>'completed', result=>$result, directory=>"$final",
                fingerprints=>\@fingerprints, engineVersion=>$Convert::Pheno::VERSION, finished=>time()};
            $staging->child('.convert-pheno-owner')->spew_raw($owner);
            _write($dir->child('publication.json'), {owner=>$owner,staging=>"$staging",final=>"$final",completed=>$completed});
            rename $staging,$final or die "Could not publish output directory\n";
        }
        $status->{status}='completed'; $status->{result}=$result; $status->{directory}="$final";
        $status->{fingerprints}=\@fingerprints; $status->{engineVersion}=$Convert::Pheno::VERSION;
        1;
    };
    if (!$ok) {
        $status->{status}='failed'; $status->{message}="$@";
        remove_tree($staging);
    }
    $status->{finished}=time();
    if ($ok) {
        unlink $dir->child('request.json');
        $status = _recover_publication($dir, $status);
    } else {
        _write($dir->child('status.json'),$status);
        unlink $dir->child('request.json');
    }
    return $ok;
}

1;
