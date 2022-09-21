package Teochew::Utils;

use Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
    change_tone
    add_tone_marks
    link_teochew_words
    split_out_parens
);

use strict;
use warnings;

use POSIX;
use String::Util qw(trim);
#use Data::Dumper;

=head1 NAME

Teochew::Utils

=head1 DESCRIPTION

Provides utility methods

=cut

my %tone_marks = (
    1 => "",
    2 => "\N{U+0340}",
    3 => "\N{U+0306}",
    4 => "",
    5 => "\N{U+0304}",
    6 => "\N{U+0341}",
    7 => "\N{U+0323}",
    8 => "\N{U+0304}",
);

my %tone_changes = (
    1 => 1,
    2 => 6,
    3 => 2,
    4 => 8,
    5 => 7,
    6 => 7,
    7 => 7,
    8 => 4,
);

=head2 change_tone

Given pengim, this will change the tone of the last syllable so it has the
correct tone if it's before another word.

=cut

sub change_tone {
    my $input = shift;

    my @syllables = split / /, $input;
    my $pengim = pop @syllables;

    my $tone_number;
    if ($pengim =~ /(\d)$/) {
        $tone_number = $1;
        $pengim =~ s/(\d)$//;
    }

    die "change_tone: Poorly formatted pengim [$pengim]" unless $tone_number;

    if ($tone_number eq $tone_changes{$tone_number}) {
        $pengim .= "$tone_changes{$tone_number}";
    }
    else {
        $pengim .= "($tone_changes{$tone_number})";
    }

    return join(' ', @syllables, $pengim);
}

=head2 add_tone_marks

=cut

sub add_tone_marks {
    my $input = shift;

    return $input;
}

=head2 add_tone_marks__old

Given a pengim string using a tone number, this will return the form of pengim
with accents instead

=cut

sub add_tone_marks__old {
    my $input = shift;
    my @syllables = split / /, $input;
    my @return;

    for my $syllable (@syllables) {
        my ($pengim, $number) = $syllable =~ /^([a-z]+)(\d)$/;

        die "add_tone_marks: Poorly formatted pengim [$input]"
            unless $pengim && $number;

        # Any syllable ending in 'n' is nasal
        $pengim =~ s/n$/:/;

        my $mark = $tone_marks{$number};

        # Add the tone mark
        # XXX: There might be a better way to do this
        if ($mark) {
            $pengim =~ s/(a)/$1$mark/ or
            $pengim =~ s/(e)/$1$mark/ or
            $pengim =~ s/(o)/$1$mark/ or
            $pengim =~ s/(u)/$1$mark/ or
            $pengim =~ s/(i)/$1$mark/ or
            $pengim .= $mark;
        }

        push @return, $pengim;
    }

    return join ' ', @return;
}

=head2 link_teochew_words

Given a list of teochew translations, this will link them together and apply
tone changes as necessary. This returns a single translation.

=cut

sub link_teochew_words {
    my ($list, $params) = @_;

    my @components = @$list;
    my $last = $params->{tone_change_last_word} ? undef : pop @components;

    # Apply tone changes
    my @pengim_parts =
        map { $_->{no_tone_change} ? $_->{pengim} : change_tone($_->{pengim}) }
        @components;

    if ($last) {
        push @pengim_parts, $last->{pengim};
        push @components, $last;
    }

    my $pengim  = join ' ', @pengim_parts;
    my $chinese = join '', map { $_->{chinese} } @components;

    return { pengim => $pengim, chinese => $chinese };
}

=head2 split_out_parens

Given an english string, this will split the string and return two strings:
anything before the parentheses, and anything inside the parentheses.

=cut

sub split_out_parens {
    my $input = shift;
    my $inside_parens = '';

    if ($input =~ /(.*)\((.*)\)/) {
        $input = trim $1;
        $inside_parens = $2;
    }

    return ($input, $inside_parens);
}
