#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

use Term::ANSIColor qw(colored);

use lib 'lib';

use Input;
use Teochew;
use Teochew::Edit;

my ($sentence, $words) = @ARGV;

die "Must include English sentence and words!\n" unless $sentence and $words;

my @translations = Teochew::translate_string_of_english_words({
    sentence => $sentence,
    words    => [$words],
});

say "Inserting phrase \"$sentence\" with translation \"" .
    $translations[0]{full_translation}{pengim} . "\"";

if (Input::confirm()) {
    Teochew::Edit->insert_phrase(
        sentence => $sentence,
        words => $translations[0]{components}
    );
    say colored("Inserted sentence '$sentence'", "green");
}
