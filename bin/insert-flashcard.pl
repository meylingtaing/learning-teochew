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
my ($hidden, $hidden_from_flashcards);
GetOptionsFromArray(\@other_args,
    hidden => \$hidden,
    hidden_from_flashcards => \$hidden_from_flashcards
);

my $db = Teochew::Edit->new;

# Check and see if the category exists, or if we need to create it
my %categories = map { $_->{name} => $_->{id} } Teochew::categories;
my $category_id = $categories{$category};

unless ($category_id) {
    say "Creating new category: $category";
    if (confirm()) {
        $category_id = $db->insert_category($category);
    }
    else {
        exit;
    }
}

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
my $simplified = $db->ensure_chinese_is_in_database(
    chinese => $chinese,
    pengim  => $pengim,
);
exit unless $simplified;

# Split notes out of english if applicable
my ($english_main, $notes) = split_out_parens($english);

# Remove any parens from the pengim - this turns lao6(7) to lao67
$pengim =~ s/(\d) \( (\d) \)/$1$2/gx;

# Aaaaand, we're almost ready to insert. Let's confirm everything with the user
say "Inserting into $category ";
say "\tEnglish: $english";
say "\tPeng'im: $pengim";
say "\tSimplified Chinese: $simplified";

say "\tSort: $sort" if defined $sort;

say "\thidden: 1" if $hidden;
say "\thidden_from_flashcards: 1" if $hidden_from_flashcards;

if (confirm()) {

    # Add the translation!!
    my $success = $db->insert_translation(
        category_id  => $category_id,
        english      => $english_main,
        notes        => $notes,
        english_sort => $sort,
        pengim       => $pengim,
        chinese      => $simplified,
        hidden       => $hidden,
        hidden_from_flashcards => $hidden_from_flashcards,
    );
    if ($success) {
        my $success_message = "Successfully added $english_main";
        $success_message .= "($notes)" if $notes;
        say colored($success_message, "green");
    }
}
