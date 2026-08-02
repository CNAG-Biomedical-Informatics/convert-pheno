package Convert::Pheno::CDISC::ODM::Metadata;

use strict;
use warnings;

use Scalar::Util qw(looks_like_number);

use Convert::Pheno::CDISC::ODM::Util qw(attr child children element_text);

sub from_document {
    my ( $class, $descriptor ) = @_;
    my %providers;

    for my $study ( @{ children( $descriptor->{root}, 'Study' ) } ) {
        my $study_oid = attr( $study, 'OID' );
        next unless defined $study_oid;

        for my $version ( @{ children( $study, 'MetaDataVersion' ) } ) {
            my $version_oid = attr( $version, 'OID' );
            next unless defined $version_oid;
            my $key = _catalog_key( $study_oid, $version_oid );
            die "Duplicate CDISC-ODM MetaDataVersion <StudyOID=$study_oid, MetaDataVersionOID=$version_oid>\n"
              if exists $providers{$key};
            $providers{$key} = _provider_from_version($version);
        }
    }

    return bless { providers => \%providers }, $class;
}

sub provider_for {
    my ( $self, $study_oid, $version_oid ) = @_;
    my $provider = $self->{providers}{ _catalog_key( $study_oid, $version_oid ) };
    die "CDISC-ODM ClinicalData references missing metadata <StudyOID=$study_oid, MetaDataVersionOID=$version_oid>\n"
      unless $provider;
    return $provider;
}

sub _provider_from_version {
    my ($version) = @_;
    my %code_lists;

    for my $code_list ( @{ children( $version, 'CodeList' ) } ) {
        my $oid = attr( $code_list, 'OID' );
        next unless defined $oid;
        die "Duplicate CDISC-ODM CodeList OID <$oid>\n"
          if exists $code_lists{$oid};
        my %labels;
        for my $item (
            @{ children( $code_list, 'CodeListItem' ) },
            @{ children( $code_list, 'EnumeratedItem' ) }
          )
        {
            my $code = attr( $item, 'CodedValue' );
            next unless defined $code;
            my $decode = child( $item, 'Decode' );
            my $label = _translated_text($decode);
            $label = attr( $item, 'Name' ) unless defined $label;
            $labels{$code} = $label if defined $label;
        }
        $code_lists{$oid} = \%labels;
    }

    my %fields;
    for my $item_def ( @{ children( $version, 'ItemDef' ) } ) {
        my $oid = attr( $item_def, 'OID' );
        next unless defined $oid;
        die "Duplicate CDISC-ODM ItemDef OID <$oid>\n" if exists $fields{$oid};

        my @code_list_refs = @{ children( $item_def, 'CodeListRef' ) };
        die "CDISC-ODM ItemDef <$oid> has multiple CodeListRef elements; conditional code-list selection is not supported\n"
          if @code_list_refs > 1;
        my $code_list_ref = $code_list_refs[0];
        my $code_list_oid = attr( $code_list_ref, 'CodeListOID' );
        my $label = _translated_text( child( $item_def, 'Question' ) );
        $label = _translated_text( child( $item_def, 'Description' ) )
          unless defined $label;
        $label = attr( $item_def, 'Name' ) unless defined $label;
        my $note = _translated_text( child( $item_def, 'Description' ) );

        $fields{$oid} = {
            'Field Label' => defined $label ? $label : $oid,
            'Field Note'  => defined $note  ? $note  : q{},
            'Field Type'  => attr( $item_def, 'DataType' ) // 'text',
            _labels => defined $code_list_oid
            ? ( $code_lists{$code_list_oid} || {} )
            : undef,
        };
    }

    return bless { rows => \%fields }, 'Convert::Pheno::CDISC::ODM::Metadata::Provider';
}

sub _translated_text {
    my ($node) = @_;
    return unless defined $node;
    my $translated = child( $node, 'TranslatedText' );
    return element_text($translated) if defined $translated;
    return element_text($node);
}

sub _catalog_key {
    return join "\x1e", map { defined $_ ? $_ : q{} } @_;
}

package Convert::Pheno::CDISC::ODM::Metadata::Provider;

use strict;
use warnings;

sub field_meta {
    my ( $self, $field ) = @_;
    return $self->{rows}{$field};
}

sub field_label {
    my ( $self, $field ) = @_;
    my $meta = $self->field_meta($field) or return;
    return $meta->{'Field Label'};
}

sub field_note {
    my ( $self, $field ) = @_;
    my $meta = $self->field_meta($field) or return;
    return $meta->{'Field Note'};
}

sub choice_labels {
    my ( $self, $field ) = @_;
    my $meta = $self->field_meta($field) or return;
    return $meta->{_labels};
}

sub choice_label {
    my ( $self, $field, $code ) = @_;
    my $labels = $self->choice_labels($field) or return;
    return $labels->{$code};
}

sub has_choice_labels {
    my ( $self, $field ) = @_;
    my $labels = $self->choice_labels($field);
    return ref($labels) eq 'HASH' && keys %{$labels} ? 1 : 0;
}

sub coerce_value {
    my ( $self, $field, $value ) = @_;
    return unless defined $value && $value ne q{};
    my $meta = $self->field_meta($field) || {};
    my $type = lc( $meta->{'Field Type'} // q{} );
    return 0 + $value
      if $type =~ /\A(?:integer|float|double|decimal|number)\z/
      && Scalar::Util::looks_like_number($value);
    return $value;
}

sub as_hashref {
    return $_[0]->{rows};
}

1;
