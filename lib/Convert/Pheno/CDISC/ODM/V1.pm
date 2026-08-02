package Convert::Pheno::CDISC::ODM::V1;

use strict;
use warnings;

use Convert::Pheno::CDISC::ODM::Detector qw(attribute_by_namespace);
use Convert::Pheno::CDISC::ODM::Record;
use Convert::Pheno::CDISC::ODM::Util qw(as_array attr children);

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
        my $metadata = _metadata_provider(
            $descriptor,
            \%arg,
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
    my ( $context, $context_order ) = _record_context(
        $descriptor,
        $subject,
        $subject_key,
        $event,
        $event_oid,
        $event_repeat,
    );
    my @groups;

    for my $form ( @{ children( $event, 'FormData' ) } ) {
        my $form_oid = _required_attr( $form, 'FormOID', 'FormData' );
        my $form_repeat = attr( $form, 'FormRepeatKey' );
        my $form_scope = _scope_part( 'form', $form_oid, $form_repeat );

        for my $group ( @{ children( $form, 'ItemGroupData' ) } ) {
            my $group_oid = _required_attr(
                $group,
                'ItemGroupOID',
                'ItemGroupData',
            );
            my $group_repeat = attr( $group, 'ItemGroupRepeatKey' );
            my $group_seq = _item_group_data_seq( $group, $descriptor );
            my $group_scope = _scope_part(
                'itemGroup',
                $group_oid,
                $group_repeat,
                $group_seq,
            );

            push @groups, {
                context => {
                    studyOID           => $study_oid,
                    metaDataVersionOID => $metadata_oid,
                    subjectKey         => $subject_key,
                    studyEventOID      => $event_oid,
                    studyEventRepeatKey => $event_repeat,
                    formOID            => $form_oid,
                    formRepeatKey      => $form_repeat,
                    itemGroupOID       => $group_oid,
                    itemGroupRepeatKey => $group_repeat,
                    itemGroupDataSeq   => $group_seq,
                },
                scopePath => [ $form_scope, $group_scope ],
                items     => _v1_items($group),
            };
        }
    }

    die "CDISC-ODM StudyEventData <StudyEventOID=$event_oid> contains no ItemGroupData\n"
      unless @groups;

    return Convert::Pheno::CDISC::ODM::Record->new(
        {
            context         => $context,
            context_order   => $context_order,
            descriptor      => _record_descriptor($descriptor),
            groups          => \@groups,
            metadata        => $metadata,
            record_profile  => $descriptor->{recordProfile},
        }
    );
}

sub _record_context {
    my (
        $descriptor, $subject, $subject_key, $event, $event_oid,
        $event_repeat,
    ) = @_;

    if ( $descriptor->{recordProfile} eq 'redcap' ) {
        my $event_name = attribute_by_namespace(
            $event,
            $descriptor->{namespaces},
            qr{projectredcap\.org}i,
            'UniqueEventName',
        );
        return (
            {
                study_id          => $subject_key,
                redcap_event_name => $event_name,
            },
            [qw(study_id redcap_event_name)],
        );
    }

    my $subject_id = attribute_by_namespace(
        $subject,
        $descriptor->{namespaces},
        qr{openclinica}i,
        'StudySubjectID',
    );
    $subject_id = attr( $subject, 'StudySubjectID' ) unless defined $subject_id;
    $subject_id = $subject_key unless defined $subject_id && length $subject_id;

    return (
        {
            subjectId          => $subject_id,
            subjectKey         => $subject_key,
            studyEventOID      => $event_oid,
            studyEventRepeatKey => $event_repeat,
        },
        [qw(subjectId subjectKey studyEventOID studyEventRepeatKey)],
    );
}

sub _v1_items {
    my ($group) = @_;
    my @items;

    for my $key ( sort keys %{$group} ) {
        ( my $local_name = $key ) =~ s/^.*://;
        next unless $local_name =~ /\AItemData(?:[A-Z]\w*)?\z/;

        for my $item ( @{ as_array( $group->{$key} ) } ) {
            next unless ref($item) eq 'HASH';
            push @items, {
                itemOID => attr( $item, 'ItemOID' ),
                value   => attr( $item, 'Value' ),
            };
        }
    }
    return \@items;
}

sub _item_group_data_seq {
    my ( $group, $descriptor ) = @_;
    my $plain = attr( $group, 'ItemGroupDataSeq' );
    return $plain if defined $plain;
    return attribute_by_namespace(
        $group,
        $descriptor->{namespaces},
        qr{Dataset-XML}i,
        'ItemGroupDataSeq',
    );
}

sub _metadata_provider {
    my ( $descriptor, $arg, $study_oid, $metadata_oid ) = @_;
    return $arg->{metadata} if $descriptor->{recordProfile} eq 'redcap';
    return $arg->{metadata_catalog}->provider_for( $study_oid, $metadata_oid );
}

sub _record_descriptor {
    my ($descriptor) = @_;
    return {
        odmVersion   => $descriptor->{odmVersion},
        sourceSystem => $descriptor->{sourceSystem},
        vendor       => $descriptor->{vendor},
    };
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
