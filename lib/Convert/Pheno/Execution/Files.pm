package Convert::Pheno::Execution::Files;

use strict;
use warnings;
use Exporter 'import';
use Convert::Pheno::IO::Atomic qw(write_atomically);
use Convert::Pheno::Sink::FileSet;

our @EXPORT_OK = qw(execute_file_conversion);

# Transport-independent file execution. The caller owns destination selection
# and overwrite policy; the existing sinks own serialization and atomic writes.
sub execute_file_conversion {
    my ($convert, $request, %callbacks) = @_;
    my $method = $request->{method};
    my $target = $request->{out_file};
    my $entities = $request->{entities} || [];
    my $bundle_mode = $method =~ /2bff$/
      && (@$entities != 1 || ($entities->[0] || 'individuals') ne 'individuals');
    my ($data, $bundle);
    # OMOP file readers can emit directly. In-memory API inputs return records
    # instead, and those records must reach the file sink even for OMOP routes.
    my $file_input = !exists $request->{data};
    if ($file_input && $request->{stream} && $method eq 'omop2bff' && $bundle_mode) {
        $convert->$method;
    }
    elsif ($bundle_mode) {
        $bundle = $convert->_run_bundle_view;
    }
    elsif ($file_input && ($request->{stream} || $method eq 'omop2bff' || $method eq 'omop2pxf')) {
        write_atomically($target, sub {
            my ($staged) = @_;
            local $convert->{out_file} = $staged;
            $convert->$method;
        });
    }
    else {
        $data = $convert->$method;
    }
    Convert::Pheno::Sink::FileSet->new({
        request => $request, out_file => $target, %callbacks,
    })->write_result(data => $data, bundle => $bundle);
    return 1;
}

1;
