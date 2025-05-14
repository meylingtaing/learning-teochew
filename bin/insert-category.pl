#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);
use lib 'lib';

use Data::Dumper;
use Getopt::Long qw(GetOptionsFromArray);
use Term::ANSIColor qw(colored);

use Teochew;
use Teochew::Edit;
use Input qw(confirm input_from_prompt);

# Usage:
#   bin/insert-category.pl "FlashcardSet" "NewCategory" "DisplayName"
# Note that display name is optional

my ($flashcardset, $category, $display_name) = @ARGV;

my $db = Teochew::Edit->new;

my %categories = map { $_->{name} => $_->{id} } Teochew::categories;
my $category_id = $categories{$category};

if ($category_id) {
    say colored("Category $category already exists", "red");
    exit;
}

die "Need a flashcard set!\n" unless $flashcardset;

say "Creating new category $category under $flashcardset";
if (confirm()) {
    $category_id = $db->insert_category(
        category      => $category,
        flashcard_set => $flashcardset,
        display_name  => $display_name
    );
    say colored("Successfully added new category $category!", "green");
}
else {
    exit;
}
