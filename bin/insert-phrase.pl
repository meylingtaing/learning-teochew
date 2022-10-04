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

# First check and make sure this is translatable using the words we
# already have. This will die if we can't translate it.
my $phrase = Teochew::replace_variables({
    sentence => $sentence, words => $words
});

my $translation = Teochew::translate_phrase($phrase);

say "Inserting phrase \"$sentence\" with translation \"" .
    $translation->{pengim} . "\"";

if (confirm()) {
    Teochew::Edit->insert_phrase(sentence => $sentence, words => $words);
    say colored("Inserted sentence '$sentence'", "green");
}
