#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

use Term::ANSIColor qw(colored);

use lib 'lib';

use Input qw(confirm);
use Teochew;
use Teochew::Edit;

my ($sentence, $words) = @ARGV;

die "Must include English sentence and words!\n" unless $sentence and $words;

# Need to find the existing PhraseTranslation. If there is more than one,
# prompt the user for which one to replace

my $db = Teochew::Edit->new;
my @rows = $db->dbh->selectall_array(qq{
    select PhraseTranslations.id, phrase_id, words from PhraseTranslations
    join Phrases on Phrases.id = PhraseTranslations.phrase_id
    where sentence = ?
}, { Slice => {} }, $sentence);

die "No existing phrase found!\n" unless scalar @rows;

my $translation = $rows[0];
if (scalar @rows > 1) {
    # Need the user to select which translation they want to modify
    for (my $i = 0; $i < scalar @rows; $i++) {
        my $row = $rows[$i];
        say "$i: $row->{words}";
    }

    # TODO Error check that the user gave a valid output
    my $row_id = input_from_prompt(
        "Which translation would you like to modify?");
    $translation = $rows[$row_id];
}

# Check and make sure this is translatable using the words we
# already have. This will die if we can't translate it.
my $phrase = Teochew::replace_variables({
    sentence => $sentence, words => $words
});

my @translations = Teochew::translate_phrase({
    sentence => $sentence,
    words    => [$words],
});

say "Updating phrase \"$sentence\" with translation \"" .
    $translations[0]{pengim} . "\"";

if (confirm()) {
    $db->dbh->do('update PhraseTranslations set words = ? where id = ?',
        undef, $words, $translation->{id});
    say colored("Updated sentence '$sentence'", "green");
}

