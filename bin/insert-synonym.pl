#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

use Term::ANSIColor qw(colored);
use Getopt::Long qw(GetOptionsFromArray);

use lib 'lib';

use Input qw(confirm);
use Teochew;
use Teochew::Edit;
use Teochew::Utils qw(split_out_parens);

my ($english, $synonym, @other_args) = @ARGV;

die "Must include English and synonym!\n" unless $english and $synonym;

my $show_on_flashcard;
my $getopt_success = GetOptionsFromArray(\@other_args,
    show_on_flashcard => \$show_on_flashcard,
);

my ($word, $notes) = split_out_parens($english);

# Make sure the english word exists already -- I know I'm ignoring the notes,
# but with the way my app works, the english page just lumps all the English
# words with the same base word together
my ($row) = Teochew::get_english_from_database(word => $word);

die "$english does not exist!\n" unless $row;

say "Inserting $synonym as synonym for $word";
say "show_on_flashcard: 1" if $show_on_flashcard;
if (confirm()) {
    Teochew::Edit->insert_synonym(
        english_id        => $row->{id},
        synonym           => $synonym,
        show_on_flashcard => $show_on_flashcard,
    );
    say colored("Inserted $synonym as a synonym for $row->{word}", "green");
}
