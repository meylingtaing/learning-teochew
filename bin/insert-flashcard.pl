#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);
use lib 'lib';

binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

use Data::Dumper;
use Getopt::Long qw(GetOptionsFromArray);
use Term::ANSIColor qw(colored);

use Teochew;
use Teochew::Edit;
use Teochew::Utils qw(split_out_parens);
use Input qw(confirm input_from_prompt);

# Usage:
#   bin/insert-flashcard.pl $category $english $pengim $chinese [other options]
#
# Other options:
#   --hidden
#   --hidden_from_flashcards

# We can get the inputs either from the command line args or we prompt the
# user for them if they weren't provided
my ($category, $english, $pengim, $chinese, @other_args) = @ARGV;

$category //= input_from_prompt("Category:");
$english  //= input_from_prompt("English:");
$pengim   //= input_from_prompt("Pengim:");
$chinese  //= input_from_prompt("Chinese characters:");

# Also check and see if the user wanted to hide these words
my ($hidden, $hidden_from_flashcards, $is_grammar);
my $getopt_success = GetOptionsFromArray(\@other_args,
    hidden => \$hidden,
    hidden_from_flashcards => \$hidden_from_flashcards,
    grammar_definition => \$is_grammar
);

exit unless $getopt_success;

my $db = Teochew::Edit->new;

# Check and see if the category exists, or if we need to create it
my %categories = map { $_->{name} => $_->{id} } Teochew::categories;
my $category_id = $categories{$category};

die "Category '$category' doesn't exist!" unless $category_id;

# So, sometimes I insert words and then they need to be sorted. Check the
# sorts in the category and see if this makes sense to have a sort value
my $sort = undef;
my @words_by_sort = Teochew::category_words_by_sort_order($category_id);
if (scalar @words_by_sort > 1) {
    for (@words_by_sort) {
        $_->{sort} //= '';
        say "$_->{sort}: " . substr($_->{words}, 0, 50);
    }
    $sort = input_from_prompt("Sort order:");
}

# Make sure the Chinese characters are in the database
my $traditional = $db->ensure_chinese_is_in_database(
    chinese => $chinese,
    pengim  => $pengim,
);
exit unless $traditional;

# Split notes out of english if applicable
my ($english_main, $notes) = split_out_parens($english);

# Remove any parens from the pengim - this turns lao6(7) to lao67
$pengim =~ s/(\d) \( (\d) \)/$1$2/gx;

# Aaaaand, we're almost ready to insert. Let's confirm everything with the user
say "Inserting into $category ";
say "\tEnglish: $english";
say "\tPeng'im: $pengim";
say "\tTraditional Chinese: $traditional";

say "\tSort: $sort" if defined $sort;

say "\thidden: 1" if $hidden;
say "\thidden_from_flashcards: 1" if $hidden_from_flashcards;
say "\tgrammar_definition: 1" if $is_grammar;

if (confirm()) {

    # Add the translation!!
    my $success = $db->insert_translation(
        category_id  => $category_id,
        english      => $english_main,
        notes        => $notes,
        english_sort => $sort,
        pengim       => $pengim,
        chinese      => $traditional,
        hidden       => $hidden,
        hidden_from_flashcards => $hidden_from_flashcards,
        grammar_definition => $is_grammar,
    );
    if ($success) {
        my $success_message = "Successfully added $english_main";
        $success_message .= " ($notes)" if $notes;
        say colored($success_message, "green");
    }
}

my $syllables = length $traditional;
exit unless $syllables > 1;

my $added_breakdown = 0;

# Check and see if we can automatically add a compound breakdown
my %potential_breakdown = $db->potential_compound_breakdown(
    chinese => $traditional,
    pengim  => $pengim,
);

my %translation = $db->choose_translation_from_english($english, $traditional);
my $teochew = $translation{teochew};

if (%potential_breakdown) {
    say "\nAdding a compound breakdown...\n";

    die "Can't find the teochew entry for this!" unless $teochew;

    my $confirm_str = "Compound breakdown:";

    for (my $i = 0; $i < $syllables; $i++) {
        say "Character: $potential_breakdown{chinese}[$i]";
        say "Pengim syllable: $potential_breakdown{pengim}[$i]\n";

        $confirm_str .= "\n\t$potential_breakdown{english}[$i]";
        $confirm_str .= " ($potential_breakdown{notes}[$i])"
            if $potential_breakdown{notes}[$i];
    }

    say $confirm_str;

    if (confirm()) {
        $db->insert_compound_breakdown(
            parent_teochew_id => $teochew->{teochew_id},
            translation_ids   => $potential_breakdown{child_translation_ids},
        );
        say colored("Added compound breakdown!", "green");
        $added_breakdown = 1;
    }
}

exit if $added_breakdown;

# If not, let's try and add one anyway with some empty bits
my $compound_breakdown =
    input_from_prompt("Enter the breakdown for $traditional: ");

$db->confirm_and_insert_compound_breakdown(
    breakdown         => $compound_breakdown || $teochew->{chinese},
    pengim            => $teochew->{pengim},
    parent_teochew_id => $teochew->{teochew_id},
);
