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
        $db->insert_category($category);
    }
}

# Split up Chinese characters with simpl. and trad. We might need to add them
# to the Chinese table in the database.
my ($simplified, $traditional) = split_out_parens($chinese);
my @simplified_chars  = split //, $simplified;
my @traditional_chars = split //, $traditional;
my @pengim_syllables  = split / /, $pengim;

# Look at the Chinese character by character
for (my $i = 0; $i < scalar @simplified_chars; $i++) {
    next if $simplified_chars[$i] eq '?';

    # XXX: Check if pengim exists in the Pengim table in the database, just
    # for completeness sake? We're not actually doing anything with it unless
    # there's an alternate pronunciation though

    # The pengim might have had tone change -- if so, it would be inputted like
    # "ma3(2)", with the base tone listed first, and the changed tone in parens
    #
    # We need to associate the Chinese character with the base tone
    my ($pengim_orig, $changed_tone) = split_out_parens($pengim_syllables[$i]);

    die "Poorly formatted pengim! [$pengim_orig]\n"
        unless $pengim_orig =~ /(1|2|3|4|5|6|7|8)$/;

    unless (scalar Teochew::chinese_character_details(
                        $simplified_chars[$i], $pengim_orig))
    {
        my $insert_traditional =
            scalar @traditional_chars == 0                  ? '' :
            $simplified_chars[$i] eq $traditional_chars[$i] ? '' :
            $traditional_chars[$i];

        say sprintf "Inserting Chinese [%s (%s), %s]",
            $simplified_chars[$i],
            $insert_traditional,
            $pengim_orig;

        if (confirm()) {
            $db->insert_chinese(
                simplified  => $simplified_chars[$i],
                traditional => $insert_traditional,
                pengim      => $pengim_orig,
            );
        }
        else {
            exit;
        }
    }
}

# Split notes out of english if applicable
my ($english_main, $notes) = split_out_parens($english);

# Remove any parens from the pengim - this turns lao6(7) to lao67
$pengim =~ s/(\d) \( (\d) \)/$1$2/gx;

# Aaaaand, we're almost ready to insert. Let's confirm everything with the user
say "Inserting into $category ";
say "\tEnglish: $english";
say "\tPeng'im: $pengim";
say "\tSimplified Chinese: $simplified";

say "\thidden: 1" if $hidden;
say "\thidden_from_flashcards: 1" if $hidden_from_flashcards;

if (confirm()) {

    # Add the translation!!
    my $success = $db->insert_translation(
        category_id => $category_id,
        english     => $english_main,
        notes       => $notes,
        pengim      => $pengim,
        chinese     => $simplified,
        hidden      => $hidden,
        hidden_from_flashcards => $hidden_from_flashcards,
    );
    if ($success) {
        my $success_message = "Successfully added $english_main";
        $success_message .= "($notes)" if $notes;
        say colored($success_message, "green");
    }
}
