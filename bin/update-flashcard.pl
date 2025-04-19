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
use List::Util qw(any);

use Teochew;
use Teochew::Edit;
use Teochew::Utils qw(split_out_parens);
use Input qw(confirm input_from_prompt);

my $db = Teochew::Edit->new;

# First argument should be the English word
my $english_input = shift @ARGV;

die colored("Must provide an English word!", "red") . "\n"
    unless defined $english_input;

# Let's see what the user wants to update about this flashcard
my %inputs;
my %options = (
    new_word      => 's',
    category      => 's',
    category_sort => '',
    chinese       => 's',
    alt_chinese   => 's',
    pengim        => 's',
    tag           => 's',
    hidden        => 'i',
    hidden_from_flashcards => 'i',
);

GetOptions( map {
    my $key = $_;
    $key .= '=' . $options{$_} if $options{$_};
    $key => \$inputs{$_}
} keys %options);

# All of the %options are optional, but we need at least one of them
# specified or else this script isn't doing anything
unless (any { defined $inputs{$_} } keys %inputs)
{
    say "Must provide one of these options:";
    say "\t--$_" for keys %options;
    exit;
}

# It's possible that there is more than one translation here, so we need
# the user to choose which one they want to edit. Once we know which one,
# gather up the relevant information from the database for this translation.
my %translation = $db->choose_translation_from_english($english_input);

# XXX: Actually, translation only matters for the teochew parts. hmm. maybe i'll
# clean this up a bit later

my $english = $translation{english};
my $teochew = $translation{teochew};

my %update_english_params;

if (my $new_word = $inputs{new_word}) {
    say "Changing English word '$english->{word}' to '$new_word'";

    my ($word, $notes) = split_out_parens($new_word);
    if (confirm()) {
        $update_english_params{word}  = $word;
        $update_english_params{notes} = $notes if $notes ne '';
    }
}

if (my $category = $inputs{category}) {
    # First check if category exists already (you can only add new categories
    # manually, using sql, for now)
    my %categories = map { $_->{name} => $_->{id} } Teochew::categories;

    my $new_category_id = $categories{$category};
    die "Category '$category' doesn't exist!" unless $new_category_id;

    say sprintf("Changing '%s' category from %s to %s",
        $english->{word}, ucfirst($english->{category_name}), $category);
    if (confirm()) {
        $update_english_params{category_id} = $new_category_id;
        $english->{category_id} = $new_category_id;
    }

    $inputs{category_sort} = 1;
}

# Sorta copy pasted from the insert-flashcards script
if (my $category_sort = $inputs{category_sort}) {
    my @words_by_sort =
        Teochew::category_words_by_sort_order($english->{category_id});
    if (scalar @words_by_sort > 1)
    {
        for (@words_by_sort) {
            $_->{sort} //= '';
            say "$_->{sort}: " . substr($_->{words}, 0, 50);
        }
        my $sort = input_from_prompt("Sort order:");
        say "Changing sort order of '$english->{word}' to $sort";
        if (confirm()) {
            $update_english_params{sort} = $sort;
        }
    }
}

if (defined $inputs{hidden}) {
    my $hidden = $inputs{hidden};
    my $hiding = $hidden ? 'Hiding' : 'Un-hiding';
    say "$hiding English word '$english->{word}'";
    if (confirm()) {
        $update_english_params{hidden} = $hidden;
    }
}

if (%update_english_params) {
    $db->update_english($english->{id}, %update_english_params);
    say colored("Updated english word!", "green");
}

# For now, I'm just going to support adding new tags
if (my $tag = $inputs{tag}) {

    # First see if the tag exists or not
    my $tag_id = $db->tag_id($tag);

    unless ($tag_id) {
        say "Creating new tag '$tag'";
        if (confirm()) {
            $tag_id = $db->insert_tag($tag);
            if ($tag_id) {
                say colored("Added tag $tag!", "green");
            }
            else {
                exit;
            }
        }
    }

    # Now add the tag to the english word
    say "Adding tag '$tag' to '$english->{word}'";
    if (confirm()) {
        $db->add_tag_to_english(
            english_id => $english->{id},
            tag_id     => $tag_id
        );
        say colored("Added tag '$tag' to '$english->{word}'!", "green");
    }
}

if (my $alt_chinese = $inputs{alt_chinese}) {

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

if (my $chinese = $inputs{chinese}) {
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

if (my $pengim = $inputs{pengim}) {
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

if (defined $inputs{hidden_from_flashcards}) {
    my $hidden_from_flashcards = $inputs{hidden_from_flashcards};
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
