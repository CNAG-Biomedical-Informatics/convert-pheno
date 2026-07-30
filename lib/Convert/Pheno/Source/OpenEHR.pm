package Convert::Pheno::Source::OpenEHR;

use strict;
use warnings;

use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);
use Convert::Pheno::Source::Result;

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};

    if ( exists $converter->{data} ) {
        return Convert::Pheno::Source::Result->new(
            {
                data  => [ _normalize_documents( $converter->{data} ) ],
                # Normalization creates a new top-level document buffer. Its
                # nested values may still reference caller-owned structures.
                owned => 1,
            }
        );
    }

    my @files = @{ $converter->{in_files} || [] };
    push @files, $converter->{in_file}
      if !@files && defined $converter->{in_file};

    my @documents;
    for my $file (@files) {
        my $loaded = io_yaml_or_json(
            {
                filepath => $file,
                mode     => 'read',
            }
        );
        push @documents, _normalize_documents($loaded);
    }

    return Convert::Pheno::Source::Result->new(
        {
            data  => \@documents,
            owned => 1,
        }
    );
}

sub _normalize_documents {
    my ($data) = @_;
    return () unless defined $data;

    if ( ref($data) eq 'ARRAY' ) {
        my $all_envelopes = 1;
        for my $item ( @{$data} ) {
            if ( ref($item) ne 'HASH' || !exists $item->{compositions} ) {
                $all_envelopes = 0;
                last;
            }
        }

        return map { _normalize_document($_) } @{$data}
          if @{$data} && $all_envelopes;
        return ( _normalize_document($data) );
    }

    return ( _normalize_document($data) );
}

sub _normalize_document {
    my ($document) = @_;
    return $document
      if ref($document) eq 'HASH' && exists $document->{compositions};
    return { compositions => $document } if ref($document) eq 'ARRAY';
    return { compositions => [$document] };
}

1;
