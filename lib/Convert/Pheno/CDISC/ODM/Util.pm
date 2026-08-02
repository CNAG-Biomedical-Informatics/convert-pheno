package Convert::Pheno::CDISC::ODM::Util;

use strict;
use warnings;

use Exporter 'import';

our @EXPORT_OK = qw(
  as_array
  attr
  child
  children
  element_text
);

sub as_array {
    my ($value) = @_;
    return [] unless defined $value;
    return $value if ref($value) eq 'ARRAY';
    return [$value];
}

sub children {
    my ( $node, $local_name ) = @_;
    return [] unless ref($node) eq 'HASH';

    my @values;
    for my $key ( sort keys %{$node} ) {
        next unless $key eq $local_name || $key =~ /:\Q$local_name\E\z/;
        push @values, @{ as_array( $node->{$key} ) };
    }
    return \@values;
}

sub child {
    my ( $node, $local_name ) = @_;
    my $values = children( $node, $local_name );
    return $values->[0];
}

sub attr {
    my ( $node, $local_name ) = @_;
    return unless ref($node) eq 'HASH';
    return $node->{ '-' . $local_name };
}

sub element_text {
    my ($node) = @_;
    return unless defined $node;
    return "$node" unless ref($node);
    return unless ref($node) eq 'HASH';

    return $node->{'~'} if exists $node->{'~'};
    return $node->{'#text'} if exists $node->{'#text'};
    return;
}

1;
