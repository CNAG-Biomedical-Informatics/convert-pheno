package Convert::Pheno::Tabular::REDCap::Dictionary;

use strict;
use warnings;
use autodie;
use File::Basename qw(fileparse);
use IO::Uncompress::Gunzip qw($GunzipError);
use Text::CSV_XS;

sub from_file {
    my ( $class, $filepath ) = @_;
    my $separator = _default_separator_for_path($filepath);

    my $key    = 'Variable / Field Name';
    my $labels = 'Choices, Calculations, OR Slider Labels';

    my $csv = Text::CSV_XS->new(
        {
            sep_char  => $separator,
            binary    => 1,
            auto_diag => 1,
        }
    );

    my $fh = _open_filehandle($filepath);
    my $headers = $csv->getline($fh);
    $csv->column_names(@$headers);

    my $rows = {};
    while ( my $row = $csv->getline_hr($fh) ) {
        $row->{_labels} = _parse_choice_labels( $row->{$labels} );
        $rows->{ $row->{$key} } = $row;
    }

    close $fh;
    return bless { rows => $rows }, $class;
}

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
    return defined $self->choice_labels($field) ? 1 : 0;
}

sub as_hashref {
    my ($self) = @_;
    return $self->{rows};
}

sub _default_separator_for_path {
    my ($filepath) = @_;
    my @exts = map { $_, $_ . '.gz' } qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $filepath, @exts );
    return ( $ext eq '.csv' || $ext eq '.csv.gz' ) ? ';' : "\t";
}

sub _open_filehandle {
    my ($filepath) = @_;
    return IO::Uncompress::Gunzip->new( $filepath, MultiStream => 1 )
      if $filepath =~ /\.gz$/;

    open my $fh, '<:encoding(UTF-8)', $filepath;
    return $fh;
}

sub _parse_choice_labels {
    my $value = shift;
    return undef unless $value;

    my @choices = grep { length }
      map { _trim($_) } split /\s*\|\s*/, $value;    # perlcritic Severity: 5
    return undef unless @choices;

    my %labels;
    for my $choice (@choices) {
        my ( $code, $label ) = split /\s*,\s*/, $choice, 2;
        return undef unless defined $label;

        $code  = _trim($code);
        $label = _trim($label);
        return undef unless length($code) && length($label);

        $labels{$code} = $label;
    }

    return \%labels;
}

sub _trim {
    my $value = shift;
    return q{} unless defined $value;
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;
    return $value;
}

1;
