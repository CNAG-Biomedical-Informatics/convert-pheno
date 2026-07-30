package Convert::Pheno::Source::FHIR;

use strict;
use warnings;

use Scalar::Util qw(refaddr);
use Storable qw(dclone);

use Convert::Pheno::FHIR::Util qw(
  canonical_reference
  reference_aliases
  resolve_reference
);
use Convert::Pheno::IO::FileIO qw(read_json);
use Convert::Pheno::Source::Result;

my %BUNDLE_TYPE = map { $_ => 1 } qw(
  batch
  batch-response
  collection
  document
  history
  message
  searchset
  transaction
  transaction-response
);

sub new {
    my ( $class, $converter ) = @_;
    return bless { converter => $converter }, $class;
}

sub load {
    my ($self) = @_;
    my $converter = $self->{converter};

    my ( @bundles, @labels );
    if ( exists $converter->{data} ) {
        my $data = $converter->{data};
        my @documents = ref($data) eq 'ARRAY' ? @{$data} : ($data);
        @bundles = map { dclone($_) } @documents;
        @labels = map { 'in-memory FHIR Bundle ' . ( $_ + 1 ) }
          0 .. $#bundles;
    }
    else {
        my @files = @{ $converter->{in_files} || [] };
        push @files, $converter->{in_file}
          if !@files && defined $converter->{in_file};
        die "FHIR input requires at least one JSON Bundle file\n" unless @files;

        for my $file (@files) {
            push @bundles, read_json($file);
            push @labels,  $file;
        }
    }

    my $normalized = _normalize_bundles( \@bundles, \@labels );

    return Convert::Pheno::Source::Result->new(
        {
            data  => $normalized->{patients},
            owned => 1,
            artifacts => {
                bundle_metadata         => $normalized->{bundle_metadata},
                unassigned_resources    => $normalized->{unassigned_resources},
                derived_entity_overrides => _derived_entity_overrides(
                    $converter,
                    $normalized,
                ),
            },
        }
    );
}

sub _normalize_bundles {
    my ( $bundles, $labels ) = @_;
    die "FHIR input does not contain any Bundle documents\n" unless @{$bundles};

    my ( @records, @bundle_metadata );
    for my $index ( 0 .. $#{$bundles} ) {
        my $bundle = $bundles->[$index];
        my $label  = $labels->[$index];

        die "FHIR input <$label> must contain a JSON object\n"
          unless ref($bundle) eq 'HASH';
        die "FHIR input <$label> must contain a FHIR Bundle resource\n"
          unless ( $bundle->{resourceType} || q{} ) eq 'Bundle';
        die "FHIR Bundle <$label> has an invalid or missing type\n"
          unless defined $bundle->{type}
          && !ref( $bundle->{type} )
          && $BUNDLE_TYPE{ $bundle->{type} };
        die "FHIR Bundle <$label> must contain an entry array\n"
          unless ref( $bundle->{entry} ) eq 'ARRAY';

        push @bundle_metadata, _bundle_metadata( $bundle, $label );

        for my $entry_index ( 0 .. $#{ $bundle->{entry} } ) {
            my $entry = $bundle->{entry}[$entry_index];
            my $number = $entry_index + 1;
            die "FHIR Bundle <$label> entry $number must contain an object\n"
              unless ref($entry) eq 'HASH';
            die "FHIR Bundle <$label> entry $number is missing its resource object\n"
              unless ref( $entry->{resource} ) eq 'HASH';

            my $resource = $entry->{resource};
            die "FHIR Bundle <$label> entry $number is missing resourceType\n"
              unless defined $resource->{resourceType}
              && !ref( $resource->{resourceType} )
              && length $resource->{resourceType};

            push @records,
              {
                resource    => $resource,
                fullUrl     => $entry->{fullUrl},
                bundleIndex => $index,
                label       => "$label entry $number",
              };
        }
    }

    my %index;
    for my $record (@records) {
        for my $alias (
            @{ reference_aliases( $record->{resource}, $record->{fullUrl} ) }
          )
        {
            if ( exists $index{$alias}
                && refaddr( $index{$alias} ) != refaddr( $record->{resource} ) )
            {
                my $previous = $index{$alias};
                next
                  if $previous->{resourceType} eq 'Patient'
                  && $record->{resource}{resourceType} eq 'Patient'
                  && defined $previous->{id}
                  && defined $record->{resource}{id}
                  && $previous->{id} eq $record->{resource}{id};
                die "FHIR input contains duplicate resource reference <$alias>\n";
            }
            $index{$alias} = $record->{resource};
        }
    }

    my ( %patients, @patient_order, %patient_alias, %patient_refaddr );
    for my $record (@records) {
        my $patient = $record->{resource};
        next unless $patient->{resourceType} eq 'Patient';

        my $patient_id = _resource_identifier($patient);
        die "FHIR Patient in <$record->{label}> has neither id nor identifier.value\n"
          unless defined $patient_id && length $patient_id;
        if ( exists $patients{$patient_id} ) {
            $patient_refaddr{ refaddr($patient) } = $patient_id;
            for my $alias (
                @{ reference_aliases( $patient, $record->{fullUrl} ) }
              )
            {
                $patient_alias{$alias} = $patient_id;
            }
            next;
        }

        $patients{$patient_id} = {
            id             => $patient_id,
            patient        => $patient,
            resources      => [],
            resourceIndex  => \%index,
            bundleMetadata => \@bundle_metadata,
        };
        $patient_refaddr{ refaddr($patient) } = $patient_id;
        for my $alias (
            @{ reference_aliases( $patient, $record->{fullUrl} ) }
          )
        {
            $patient_alias{$alias} = $patient_id;
        }
        push @patient_order, $patient_id;
    }

    die "FHIR Bundle input must contain at least one Patient resource\n"
      unless @patient_order;

    my @unassigned;
    for my $record (@records) {
        my $resource = $record->{resource};
        next if $resource->{resourceType} eq 'Patient';

        my $patient_id = _resource_patient_id(
            $resource,
            \%index,
            \%patient_alias,
            \%patient_refaddr,
        );

        if ( defined $patient_id ) {
            push @{ $patients{$patient_id}{resources} }, $resource;
        }
        else {
            push @unassigned, $resource;
        }
    }

    return {
        patients             => [ map { $patients{$_} } @patient_order ],
        records              => \@records,
        resource_index       => \%index,
        bundle_metadata      => \@bundle_metadata,
        unassigned_resources => \@unassigned,
    };
}

sub _resource_patient_id {
    my ( $resource, $index, $patient_alias, $patient_refaddr ) = @_;

    for my $reference ( _patient_references($resource) ) {
        return $patient_alias->{$reference}
          if exists $patient_alias->{$reference};

        my $canonical = canonical_reference($reference);
        return $patient_alias->{$canonical}
          if defined $canonical && exists $patient_alias->{$canonical};

        my $resolved = resolve_reference( $index, $reference );
        next unless defined $resolved;
        my $address = refaddr($resolved);
        return $patient_refaddr->{$address}
          if exists $patient_refaddr->{$address};
    }

    return;
}

sub _patient_references {
    my ($resource) = @_;
    my @references;

    for my $field (qw(subject patient beneficiary)) {
        next unless ref( $resource->{$field} ) eq 'HASH';
        my $reference = $resource->{$field}{reference};
        push @references, $reference
          if defined $reference && !ref($reference) && length $reference;
    }

    if ( $resource->{resourceType} eq 'ResearchSubject'
        && ref( $resource->{individual} ) eq 'HASH' )
    {
        my $reference = $resource->{individual}{reference};
        push @references, $reference
          if defined $reference && !ref($reference) && length $reference;
    }

    return @references;
}

sub _resource_identifier {
    my ($resource) = @_;
    return $resource->{id}
      if defined $resource->{id} && !ref( $resource->{id} ) && length $resource->{id};

    for my $identifier ( @{ $resource->{identifier} || [] } ) {
        next unless ref($identifier) eq 'HASH';
        return $identifier->{value}
          if defined $identifier->{value}
          && !ref( $identifier->{value} )
          && length $identifier->{value};
    }

    return;
}

sub _bundle_metadata {
    my ( $bundle, $label ) = @_;
    my $metadata = {
        source => $label,
        type   => $bundle->{type},
    };

    for my $field (qw(id identifier meta timestamp total)) {
        next unless exists $bundle->{$field};
        $metadata->{$field} = ref( $bundle->{$field} )
          ? dclone( $bundle->{$field} )
          : $bundle->{$field};
    }

    return $metadata;
}

sub _derived_entity_overrides {
    my ( $converter, $normalized ) = @_;
    my ($study) = map { $_->{resource} }
      grep { $_->{resource}{resourceType} eq 'ResearchStudy' }
      @{ $normalized->{records} };
    my ($group) = map { $_->{resource} }
      grep { $_->{resource}{resourceType} eq 'Group' }
      @{ $normalized->{records} };

    my $overrides = {};
    if ($study) {
        my $id = _resource_identifier($study) // 'fhir-study-1';
        $overrides->{datasets} = {
            id   => $id,
            name => $study->{title} // $study->{name} // $id,
        };
        $overrides->{datasets}{description} = $study->{description}
          if defined $study->{description} && !ref( $study->{description} );
    }
    elsif ( @{ $normalized->{bundle_metadata} } ) {
        my $metadata = $normalized->{bundle_metadata}[0];
        my $id = $metadata->{id} // 'fhir-bundle-1';
        $overrides->{datasets} = {
            id          => $id,
            name        => "FHIR Bundle $id",
            description => 'Dataset synthesized from FHIR R4 Bundle input.',
        };
    }

    if ($group) {
        my $id = _resource_identifier($group) // 'fhir-group-1';
        my $size = $group->{quantity};
        $size = scalar @{ $group->{member} || [] }
          unless defined $size && !ref($size);

        $overrides->{cohorts} = {
            id         => $id,
            name       => $group->{name} // $id,
            cohortType => 'study-defined',
            cohortSize => 0 + $size,
        };
    }

    if ( ( $converter->{source_info} // 1 )
        && exists $overrides->{datasets} )
    {
        $overrides->{datasets}{info}{fhir} = {
            version => 'R4',
            bundles => dclone( $normalized->{bundle_metadata} ),
        };
        $overrides->{datasets}{info}{fhir}{researchStudy} = dclone($study)
          if $study;
        $overrides->{datasets}{info}{fhir}{unassignedResources} =
          dclone( $normalized->{unassigned_resources} )
          if @{ $normalized->{unassigned_resources} };
    }

    return $overrides;
}

1;
