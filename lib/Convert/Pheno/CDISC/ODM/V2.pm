package Convert::Pheno::CDISC::ODM::V2;

use strict;
use warnings;

use Convert::Pheno::CDISC::ODM::Detector qw(attribute_by_namespace);
use Convert::Pheno::CDISC::ODM::Record;
use Convert::Pheno::CDISC::ODM::Util qw(attr children element_text);

sub parse_records {
    my ( $class, $descriptor, %arg ) = @_;
    my @records;

    for my $clinical_data ( @{ children( $descriptor->{root}, 'ClinicalData' ) } ) {
        my $study_oid = _required_attr( $clinical_data, 'StudyOID', 'ClinicalData' );
        my $metadata_oid = _required_attr(
            $clinical_data,
            'MetaDataVersionOID',
            'ClinicalData',
        );
        my $metadata = $descriptor->{recordProfile} eq 'redcap'
          ? $arg{metadata}
          : $arg{metadata_catalog}->provider_for(
            $study_oid,
            $metadata_oid,
          );

        for my $subject ( @{ children( $clinical_data, 'SubjectData' ) } ) {
            my $subject_key = _required_attr( $subject, 'SubjectKey', 'SubjectData' );
            my @events = @{ children( $subject, 'StudyEventData' ) };
            die "CDISC-ODM SubjectData <SubjectKey=$subject_key> has no StudyEventData\n"
              unless @events;

            for my $event (@events) {
                push @records, _event_record(
                    $descriptor,
                    $metadata,
                    $study_oid,
                    $metadata_oid,
                    $subject,
                    $subject_key,
                    $event,
                );
            }
        }
    }

    die "CDISC-ODM input contains no subject-event records\n" unless @records;
    return \@records;
}

sub _event_record {
    my (
        $descriptor, $metadata,    $study_oid, $metadata_oid,
        $subject,    $subject_key, $event,
    ) = @_;

    my $event_oid = _required_attr( $event, 'StudyEventOID', 'StudyEventData' );
    my $event_repeat = attr( $event, 'StudyEventRepeatKey' );
    my ( $context, $context_order );
    if ( $descriptor->{recordProfile} eq 'redcap' ) {
        my $event_name = attribute_by_namespace(
            $event,
            $descriptor->{namespaces},
            qr{projectredcap\.org}i,
            'UniqueEventName',
        );
        $context = {
            study_id          => $subject_key,
            redcap_event_name => $event_name,
        };
        $context_order = [qw(study_id redcap_event_name)];
    }
    else {
        my $subject_id = attribute_by_namespace(
            $subject,
            $descriptor->{namespaces},
            qr{openclinica}i,
            'StudySubjectID',
        );
        $subject_id = attr( $subject, 'StudySubjectID' )
          unless defined $subject_id;
        $subject_id = $subject_key
          unless defined $subject_id && length $subject_id;
        $context = {
            subjectId           => $subject_id,
            subjectKey          => $subject_key,
            studyEventOID       => $event_oid,
            studyEventRepeatKey => $event_repeat,
        };
        $context_order = [
            qw(subjectId subjectKey studyEventOID studyEventRepeatKey)
        ];
    }

    my @groups;
    for my $group ( @{ children( $event, 'ItemGroupData' ) } ) {
        _collect_group(
            \@groups,
            $group,
            [],
            {
                studyOID            => $study_oid,
                metaDataVersionOID  => $metadata_oid,
                subjectKey          => $subject_key,
                studyEventOID       => $event_oid,
                studyEventRepeatKey => $event_repeat,
            },
        );
    }

    die "CDISC-ODM StudyEventData <StudyEventOID=$event_oid> contains no ItemGroupData\n"
      unless @groups;

    return Convert::Pheno::CDISC::ODM::Record->new(
        {
            context       => $context,
            context_order => $context_order,
            descriptor => {
                odmVersion   => $descriptor->{odmVersion},
                sourceSystem => $descriptor->{sourceSystem},
                vendor       => $descriptor->{vendor},
            },
            groups         => \@groups,
            metadata       => $metadata,
            record_profile => $descriptor->{recordProfile},
        }
    );
}

sub _collect_group {
    my ( $out, $group, $parent_path, $base_context ) = @_;
    my $group_oid = _required_attr( $group, 'ItemGroupOID', 'ItemGroupData' );
    my $group_repeat = attr( $group, 'ItemGroupRepeatKey' );
    my $group_seq = attr( $group, 'ItemGroupDataSeq' );
    my $scope = _scope_part(
        'itemGroup',
        $group_oid,
        $group_repeat,
        $group_seq,
    );
    my @scope_path = ( @{$parent_path}, $scope );
    my @path_labels = map {
        my ( undef, $oid, $repeat, $seq ) = split /\x1f/, $_, -1;
        my $label = $oid;
        $label .= "[$repeat]" if defined $repeat && length $repeat;
        $label .= "#$seq" if defined $seq && length $seq;
        $label;
    } @scope_path;

    my @items;
    for my $item ( @{ children( $group, 'ItemData' ) } ) {
        my $item_oid = _required_attr( $item, 'ItemOID', 'ItemData' );
        my @values = @{ children( $item, 'Value' ) };
        die "CDISC-ODM 2.0 ItemData <ItemOID=$item_oid> contains multiple Value elements; this conversion requires one scalar value per item occurrence\n"
          if @values > 1;
        push @items, {
            itemOID => $item_oid,
            value   => @values ? element_text( $values[0] ) : undef,
        };
    }

    push @{$out}, {
        context => {
            %{$base_context},
            itemGroupOID       => $group_oid,
            itemGroupRepeatKey => $group_repeat,
            itemGroupDataSeq   => $group_seq,
            itemGroupPath      => join( '/', @path_labels ),
        },
        scopePath => \@scope_path,
        items     => \@items,
    };

    for my $nested ( @{ children( $group, 'ItemGroupData' ) } ) {
        _collect_group(
            $out,
            $nested,
            \@scope_path,
            $base_context,
        );
    }
    return;
}

sub _scope_part {
    my ( $kind, @parts ) = @_;
    return join "\x1f", $kind, map { defined $_ ? $_ : q{} } @parts;
}

sub _required_attr {
    my ( $node, $name, $element ) = @_;
    my $value = attr( $node, $name );
    die "CDISC-ODM <$element> is missing required attribute <$name>\n"
      unless defined $value && length $value;
    return $value;
}

1;
