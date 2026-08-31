package Convert::Pheno::Source::OpenEHR;

use strict;
use warnings;

use Convert::Pheno::IO::FileIO qw(io_yaml_or_json);
use Convert::Pheno::Mapping::Shared qw(get_info);
use Convert::Pheno::OpenEHR::ToBFF qw(
  extract_openehr_compositions
  resolve_openehr_embedded_patient_id
  resolve_openehr_patient_id
);
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

sub prepare {
    my ($self) = @_;
    my $converter = $self->{converter};
    return 1 if $converter->{openehr_input_prepared};

    my $source = $self->load;
    my @documents = @{ $source->data };
    my $grouped = _group_documents_by_patient( $converter, \@documents );

    $converter->{data} = @{$grouped} == 1 ? $grouped->[0] : $grouped;
    $converter->{_owns_prepared_data} = 1 if $source->owned;
    delete $converter->{mapping_file_derived_entity_overrides};
    $converter->{convertPheno} ||= get_info($converter);
    $converter->{openehr_input_prepared} = 1;
    return 1;
}

sub _group_documents_by_patient {
    my ( $converter, $documents ) = @_;
    my ( %by_patient, @order );

    for my $document ( @{$documents} ) {
        for my $patient_document (
            _split_document_by_patient( $converter, $document )
          )
        {
            my $patient_id =
              resolve_openehr_patient_id( $converter, $patient_document );
            die "The input <openEHR> data could not be resolved to a patient id; please provide one composition set with a stable patient identifier in the payload or envelope\n"
              unless defined $patient_id && length $patient_id;

            if ( !exists $by_patient{$patient_id} ) {
                $by_patient{$patient_id} = {
                    patient      => { id => $patient_id },
                    compositions => [],
                };
                push @order, $patient_id;
            }
            push @{ $by_patient{$patient_id}{compositions} },
              @{ extract_openehr_compositions($patient_document) };
        }
    }

    return [ map { $by_patient{$_} } @order ];
}

sub _split_document_by_patient {
    my ( $converter, $document ) = @_;
    return ($document) if _document_has_patient_context($document);

    my $compositions = extract_openehr_compositions($document);
    return ($document)
      unless ref($compositions) eq 'ARRAY' && @{$compositions} > 1;

    my ( %by_patient, @order );
    my $missing = 0;
    for my $composition ( @{$compositions} ) {
        my $patient_id = resolve_openehr_embedded_patient_id(
            $composition,
            [$composition],
        );
        if ( !defined $patient_id || !length $patient_id ) {
            $missing = 1;
            next;
        }
        if ( !exists $by_patient{$patient_id} ) {
            $by_patient{$patient_id} = [];
            push @order, $patient_id;
        }
        push @{ $by_patient{$patient_id} }, $composition;
    }

    return ($document) unless @order > 1;
    die "The input <openEHR> data mixes patient-identified and unidentified compositions; please provide patient-bearing envelopes or per-patient composition sets\n"
      if $missing;

    return map {
        {
            patient      => { id => $_ },
            compositions => $by_patient{$_},
        }
    } @order;
}

sub _document_has_patient_context {
    my ($document) = @_;
    return 0 unless ref($document) eq 'HASH';

    return 1
      if ref( $document->{patient} ) eq 'HASH'
      && defined $document->{patient}{id}
      && length $document->{patient}{id};

    return 1
      if ref( $document->{ehr_status} ) eq 'HASH'
      && exists $document->{ehr_status}{subject};

    return 0;
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
