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

my $db = Teochew::Edit->new;

# First argument should be the English word
my $english_input = shift @ARGV;

die colored("Must provide an English word!", "red") . "\n"
    unless defined $english_input;


# Let's see what the user wants to update
my (
    $category, $category_sort,
    $chinese, $alt_chinese,
    $pengim,
    $hidden_from_flashcards);
GetOptions(
    "category=s"    => \$category,
    "category-sort" => \$category_sort,
    "chinese=s"     => \$chinese,
    "alt-chinese=s" => \$alt_chinese,
    "pengim=s"      => \$pengim,

    "hidden-from-flashcards=i" => \$hidden_from_flashcards,
);

# XXX There's probably an easier way of handling this
unless ($category ||
        $category_sort ||
        $alt_chinese ||
        $pengim ||
        $chinese ||
        defined $hidden_from_flashcards)
{
    say "Must provide one of these options:";
    say "\t--category";
    say "\t--category-sort";
    say "\t--chinese";
    say "\t--alt-chinese";
    say "\t--pengim";
    say "\t--hidden-from-flashcards";
    exit;
}

# Gather up the relevant information from the database for this translation
my %translation = $db->choose_translation_from_english($english_input);

my $english     = $translation{english};
my $teochew     = $translation{teochew};

my %update_english_params;

if ($category) {
    # First check if category exists already (you can only add new categories
    # manually, using sql, for now)
    my %categories = map { $_->{name} => $_->{id} } Teochew::categories;

    my $new_category_id = $categories{$category};
    die "Category '$category' doesn't exist!" unless $new_category_id;

    say "Changing category from $english->{category_name} to $category";
    if (confirm()) {
        $update_english_params{category_id} = $new_category_id;
        $english->{category_id} = $new_category_id;
    }

    $category_sort = 1;
}

# Sorta copy pasted from the insert-flashcards script
if ($category_sort) {
    my @words_by_sort =
        Teochew::category_words_by_sort_order($english->{category_id});
    for (@words_by_sort) {
        $_->{sort} //= '';
        say "$_->{sort}: " . substr($_->{words}, 0, 50);
    }
    my $sort = input_from_prompt("Sort order:");
    say "Changing sort order of english word to $sort";
    if (confirm()) {
        $update_english_params{sort} = $sort;
    }
}

if (%update_english_params) {
    $db->update_english($english->{id}, %update_english_params);
    say colored("Updated english word!", "green");
}

if ($alt_chinese) {

    # First check and see if these Chinese characters exist in the database
    $db->ensure_chinese_is_in_database(
        chinese => $alt_chinese,
        pengim  => $teochew->{pengim},
    );

    say "Adding $alt_chinese as an alternate for $teochew->{chinese}";
    if (confirm()) {
        $db->insert_alt_chinese(
            teochew_id => $teochew->{teochew_id},
            chinese    => $alt_chinese
        );
        say colored("Added $alt_chinese as an alternate!", "green");
    }
}

if ($chinese) {
    # First make sure these Chinese characters exist in the database
    $db->ensure_chinese_is_in_database(
        chinese => $chinese,
        pengim  => $teochew->{pengim},
    );

    # Maybe this one doesn't have any Chinese yet?
    my $teochew_id = $db->_get_teochew_id(
        pengim  => $teochew->{pengim},
        chinese => '?',
    );

    # TODO: Be able to smartly modify the related Chinese entry. Maybe.
    die "I haven't supported replacing the Chinese character yet\n"
        unless $teochew_id;

    say "Adding $chinese as the Chinese for $english->{word}";
    if (confirm()) {
        $db->update_teochew($teochew_id, chinese => $chinese);
    }
}

if ($pengim) {
    say "Modifying $english->{word} translation from " .
        "'$teochew->{pengim}' to '$pengim'";
    if (confirm()) {
        $db->update_teochew(
            $teochew->{teochew_id},
            pengim => $pengim,
        );
        say colored("Updated $english->{word} pengim to $pengim!", "green");
    }
}

if (defined $hidden_from_flashcards) {
    my $msg = "Modifying $english->{word} translation to be";
    my $hidden_shown = $hidden_from_flashcards ? "hidden from flashcards" :
                                                 "shown in flashcards";

    say "$msg $hidden_shown";
    if (confirm()) {
        $db->update_translation(
            $teochew->{translation_id},
            hidden_from_flashcards => $hidden_from_flashcards
        );
    }
    say colored("Updated $english->{word} to be $hidden_shown", "green");
}
