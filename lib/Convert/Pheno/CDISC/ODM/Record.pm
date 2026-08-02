package Convert::Pheno::CDISC::ODM::Record;

use strict;
use warnings;

use JSON::PP;
use Scalar::Util qw(blessed);

use Convert::Pheno::Mapping::Shared qw(dotify_and_coerce_number);

my $JSON = JSON::PP->new->canonical;

sub new {
    my ( $class, $arg ) = @_;
    $arg ||= {};

    my $self = bless {
        context       => { %{ $arg->{context} || {} } },
        context_order => [ @{ $arg->{context_order} || [] } ],
        descriptor    => { %{ $arg->{descriptor} || {} } },
        entries       => {},
        field_order   => [],
        groups        => [],
        metadata      => $arg->{metadata},
        overrides     => {},
        recordProfile => $arg->{record_profile} || 'cdisc-odm',
        sourceFormat  => 'cdisc-odm',
    }, $class;

    my ( %seen_field, %seen_group );
    for my $group ( @{ $arg->{groups} || [] } ) {
        my $context = { %{ $group->{context} || {} } };
        my $identity = $JSON->encode($context);
        die "Duplicate CDISC-ODM item-group occurrence "
          . _format_context($context) . "\n"
          if $seen_group{$identity}++;

        my $group_index = @{ $self->{groups} };
        push @{ $self->{groups} }, {
            context   => $context,
            itemOrder => [],
            scopePath => [ @{ $group->{scopePath} || [] } ],
        };

        my %seen_item;
        for my $item ( @{ $group->{items} || [] } ) {
            my $field = $item->{itemOID};
            die "CDISC-ODM ItemData is missing ItemOID "
              . _format_context($context) . "\n"
              unless defined $field && length $field;
            die "Duplicate CDISC-ODM ItemOID <$field> in item-group occurrence "
              . _format_context($context) . "\n"
              if $seen_item{$field}++;
            if (
                $self->{recordProfile} eq 'cdisc-odm'
                && blessed( $self->{metadata} )
                && $self->{metadata}->can('field_meta')
                && !defined $self->{metadata}->field_meta($field)
              )
            {
                die "CDISC-ODM ItemData <ItemOID=$field> references no ItemDef in the active MetaDataVersion "
                  . _format_context($context) . "\n";
            }

            my $raw = _coerce_value( $self, $field, $item->{value} );
            my $entry = {
                groupIndex => $group_index,
                raw        => $raw,
                sourceValue => $item->{value},
                working    => $raw,
            };
            push @{ $self->{entries}{$field} }, $entry;
            push @{ $self->{groups}[$group_index]{itemOrder} }, $field;
            push @{ $self->{field_order} }, $field unless $seen_field{$field}++;
        }
    }

    return $self;
}

sub source_format  { return 'cdisc-odm' }
sub record_profile { return _root( $_[0] )->{recordProfile} }

sub headers {
    my ($self) = @_;
    my $root = _root($self);
    my %seen;
    return [
        grep { !$seen{$_}++ }
          @{ $root->{context_order} },
        sort( keys %{ $root->{context} } ),
        @{ $root->{field_order} },
    ];
}

sub raw_value {
    my ( $self, $field ) = @_;
    return _resolved_value( $self, $field, 'raw' );
}

sub working_value {
    my ( $self, $field ) = @_;
    return _resolved_value( $self, $field, 'working' );
}

sub value {
    my ( $self, $field ) = @_;
    my $value = _resolved_value( $self, $field, 'working' );
    return _mapped_value( _root($self), $field, $value );
}

sub info_value {
    my ( $self, $field ) = @_;
    my $root = _root($self);
    return $self->value($field) if exists $self->{boundGroup};
    my $entries = $root->{entries}{$field};
    return $self->value($field) unless $entries && @{$entries} > 1;

    my @values = map {
        {
            context => _public_group_context(
                $root->{groups}[ $_->{groupIndex} ]{context}
            ),
            value => _mapped_value( $root, $field, $_->{working} ),
        }
    } @{$entries};

    my %distinct;
    for my $item (@values) {
        my $comparison = $item->{value};
        my $key = defined $comparison ? "$comparison" : "\x00undef";
        $distinct{$key} = 1;
    }
    return $values[0]{value} if keys(%distinct) == 1;
    return \@values;
}

sub set_value {
    my ( $self, $field, $value ) = @_;
    my $root = _root($self);

    if ( exists $self->{boundGroup} ) {
        my @exact = grep { $_->{groupIndex} == $self->{boundGroup} }
          @{ $root->{entries}{$field} || [] };
        if (@exact) {
            $_->{working} = $value for @exact;
            return 1;
        }
    }

    $root->{overrides}{$field} = $value;
    return 1;
}

sub has_choice_labels {
    my ( $self, $field ) = @_;
    my $metadata = _root($self)->{metadata};
    return 0 unless blessed($metadata) && $metadata->can('has_choice_labels');
    return $metadata->has_choice_labels($field);
}

sub field_meta {
    my ( $self, $field ) = @_;
    my $metadata = _root($self)->{metadata};
    return unless blessed($metadata) && $metadata->can('field_meta');
    return $metadata->field_meta($field);
}

sub field_note {
    my ( $self, $field ) = @_;
    my $metadata = _root($self)->{metadata};
    return unless blessed($metadata) && $metadata->can('field_note');
    return $metadata->field_note($field);
}

sub views_for {
    my ( $self, $field ) = @_;
    my $root = _root($self);
    my $entries = $root->{entries}{$field} || [];
    return [$self] if exists $root->{overrides}{$field};

    if ( exists $self->{boundGroup} ) {
        my $bound = $root->{groups}[ $self->{boundGroup} ];
        my @exact = grep { $_->{groupIndex} == $self->{boundGroup} } @{$entries};
        return [ map { _bound_view( $root, $_->{groupIndex} ) } @exact ] if @exact;

        my @descendants = grep {
            _path_is_prefix(
                $bound->{scopePath},
                $root->{groups}[ $_->{groupIndex} ]{scopePath},
            )
        } @{$entries};
        return [ map { _bound_view( $root, $_->{groupIndex} ) } @descendants ]
          if @descendants;

        return [$self] if defined $self->working_value($field);
        return [];
    }

    return [ map { _bound_view( $root, $_->{groupIndex} ) } @{$entries} ]
      if @{$entries};
    return [$self] if exists $root->{context}{$field};
    return [];
}

sub columns_snapshot {
    my ($self) = @_;
    my $root = _root($self);
    my %snapshot = %{ $root->{context} };

    for my $field ( @{ $root->{field_order} } ) {
        my ( $value, $ambiguous ) = _collapse_entries(
            $root,
            $field,
            $root->{entries}{$field},
            'raw',
            0,
        );
        $snapshot{$field} = $value unless $ambiguous;
    }
    return \%snapshot;
}

sub has_repeated_fields {
    my ($self) = @_;
    my $root = _root($self);
    return scalar grep { @{ $root->{entries}{$_} } > 1 }
      keys %{ $root->{entries} };
}

sub odm_provenance {
    my ($self) = @_;
    my $root = _root($self);
    my @groups;

    for my $group_index ( 0 .. $#{ $root->{groups} } ) {
        my $group = $root->{groups}[$group_index];
        my @items;
        for my $field ( @{ $group->{itemOrder} } ) {
            for my $entry ( @{ $root->{entries}{$field} || [] } ) {
                next unless $entry->{groupIndex} == $group_index;
                push @items, {
                    itemOID => $field,
                    value   => $entry->{sourceValue},
                };
            }
        }
        push @groups, {
            %{ _public_group_context( $group->{context} ) },
            items => \@items,
        };
    }

    return {
        %{ $root->{descriptor} },
        %{ $root->{context} },
        itemGroups => \@groups,
    };
}

sub _resolved_value {
    my ( $self, $field, $kind ) = @_;
    my $root = _root($self);
    return $root->{overrides}{$field} if exists $root->{overrides}{$field};

    my $entries = $root->{entries}{$field} || [];
    if ( exists $self->{boundGroup} && @{$entries} ) {
        my @exact = grep { $_->{groupIndex} == $self->{boundGroup} } @{$entries};
        return $exact[0]{$kind} if @exact;

        my $bound_path = $root->{groups}[ $self->{boundGroup} ]{scopePath};
        my @ancestors = sort {
            @{ $root->{groups}[ $b->{groupIndex} ]{scopePath} }
              <=> @{ $root->{groups}[ $a->{groupIndex} ]{scopePath} }
        } grep {
            _path_is_prefix(
                $root->{groups}[ $_->{groupIndex} ]{scopePath},
                $bound_path,
            )
        } @{$entries};
        return $ancestors[0]{$kind} if @ancestors;
    }

    if ( @{$entries} ) {
        my ($value) = _collapse_entries( $root, $field, $entries, $kind, 1 );
        return $value;
    }
    return $root->{context}{$field} if exists $root->{context}{$field};
    return;
}

sub _collapse_entries {
    my ( $root, $field, $entries, $kind, $fatal ) = @_;
    my %distinct;
    for my $entry ( @{$entries} ) {
        # Compare through a copy. Stringifying the hash value directly changes
        # Perl's scalar flags and makes JSON::XS serialize numbers as strings.
        my $comparison = $entry->{$kind};
        my $key = defined $comparison ? "$comparison" : "\x00undef";
        push @{ $distinct{$key} }, $entry;
    }

    return ( $entries->[0]{$kind}, 0 ) if keys(%distinct) <= 1;
    return ( undef, 1 ) unless $fatal;

    my @occurrences = map {
        my $value = defined $_->{$kind} ? $_->{$kind} : 'null';
        $value . ' at '
          . _format_context( $root->{groups}[ $_->{groupIndex} ]{context} )
    } @{$entries};
    die "Ambiguous CDISC-ODM scalar field <$field> has differing occurrence values: "
      . join( '; ', @occurrences ) . "\n";
}

sub _mapped_value {
    my ( $root, $field, $value ) = @_;
    return unless defined $value;
    my $metadata = $root->{metadata};
    return $value
      unless blessed($metadata)
      && $metadata->can('has_choice_labels')
      && $metadata->has_choice_labels($field);

    my $mapped = $metadata->choice_label( $field, $value );
    return defined $mapped ? dotify_and_coerce_number($mapped) : $value;
}

sub _coerce_value {
    my ( $self, $field, $value ) = @_;
    return dotify_and_coerce_number($value)
      if $self->{recordProfile} eq 'redcap';

    my $metadata = $self->{metadata};
    return $metadata->coerce_value( $field, $value )
      if blessed($metadata) && $metadata->can('coerce_value');
    return $value;
}

sub _bound_view {
    my ( $root, $group_index ) = @_;
    return bless {
        parent     => $root,
        boundGroup => $group_index,
    }, __PACKAGE__;
}

sub _root {
    my ($self) = @_;
    return $self->{parent} || $self;
}

sub _path_is_prefix {
    my ( $candidate, $path ) = @_;
    return 0 if @{$candidate} > @{$path};
    for my $index ( 0 .. $#{$candidate} ) {
        return 0 if $candidate->[$index] ne $path->[$index];
    }
    return 1;
}

sub _public_group_context {
    my ($context) = @_;
    my %public = %{$context};
    delete $public{scopePath};
    return \%public;
}

sub _format_context {
    my ($context) = @_;
    my @parts = map {
        defined $context->{$_} && length "$context->{$_}"
          ? "$_=$context->{$_}"
          : ()
    } sort keys %{$context};
    return '<' . join( ', ', @parts ) . '>';
}

1;
