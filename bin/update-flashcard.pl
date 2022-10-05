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
use Input qw(confirm);

# First argument should be the English word
my $english = shift @ARGV;

die colored("Must provide an English word!", "red") . "\n"
    unless defined $english;

my ($word, $notes) = split_out_parens($english);
my ($row) = Teochew::get_english_from_database(word => $word, notes => $notes);

die colored("$english does not exist!", "red") . "\n" unless $row;

# Get existing translations -- there might be more than one. If so, have the
# user select the one they want to modify
my @rows = Teochew::get_all_translations_by_id($row->{id});
my $row_id = 0;
if (scalar @rows == 0) {
    die "No translations found for $english!\n";
}
elsif (scalar @rows > 1) {
    # Need the user to select which translation they want to modify
    for (my $i = 0; $i < scalar @rows; $i++) {
        my $row = $rows[$i];
        say "$i: $row->{chinese} $row->{pengim}";
    }
    $row_id = get_input_from_prompt(
        "Which translation would you like to modify?");
}

# Let's see what the user wants to update
my ($category, $alt_chinese);
GetOptions(
    "category=s"    => \$category,
    "alt-chinese=s" => \$alt_chinese,
);

my $db = Teochew::Edit->new;

if ($alt_chinese) {
    # First check and see if these Chinese characters exist in the database
    # XXX Will need to support simplified and traditional at some point
    my @simplified_chars  = split //, $alt_chinese;
    my @pengim_syllables  = split / /, $rows[$row_id]{pengim};

    die colored(
        "The number of characters doesn't match $rows[$row_id]{pengim}!", "red"
    ) . "\n" if scalar @simplified_chars != scalar @pengim_syllables;

    for (my $i = 0; $i < scalar @simplified_chars; $i++) {
        unless (scalar Teochew::chinese_character_details(
                        $simplified_chars[$i], $pengim_syllables[$i]))
        {
            # Copy pasted from insert-flashcard.pl
            say sprintf "Inserting Chinese [%s %s]",
                $simplified_chars[$i],
                $pengim_syllables[$i];

            if (confirm()) {
                $db->insert_chinese(
                    simplified  => $simplified_chars[$i],
                    pengim      => $pengim_syllables[$i],
                );
                say colored("Added $alt_chinese to Chinese table", "green");
            }
            else {
                exit;
            }
        }
    }

    say "Adding $alt_chinese as an alternate for $rows[$row_id]{chinese}";
    if (confirm()) {
        $db->insert_alt_chinese(
            teochew_id => $rows[$row_id]{teochew_id},
            chinese    => $alt_chinese
        );
        say colored("Added $alt_chinese as an alternate!", "green");
    }
}
