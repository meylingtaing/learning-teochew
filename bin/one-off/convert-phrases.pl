#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

# These are required to print non-ascii characters to STDOUT or
# read them in @ARGV
binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

# We almost certainly want access to these
use lib 'lib';
use Teochew;
use Teochew::Edit;

# need to explicitly include exported functions
use Teochew::Utils qw();
use Input;

use Data::Dumper;
use Term::ANSIColor qw(colored);

my $db = Teochew::Edit->new;

# Get all the sentences
my @rows = $db->dbh->selectall_array(qq{
    select sentence, words, hidden
    from Phrases join PhraseTranslations on phrase_id = Phrases.id 
}, { Slice => {} });

my $previous_sentence = '';

for my $row (@rows) {
    my $sentence = $row->{sentence};

    next if $sentence =~ /\$/;

    # Make sure it doesn't already exist
    my $count = $db->dbh->selectall_array(qq{
        select id from EnglishSentence
        where sentence = ?
    }, undef, $sentence);

    if ($count > 0 && $sentence ne $previous_sentence) {
        say colored("Skipping '$sentence'", "red");
        next;
    }

    my @translations = Teochew::translate_string_of_english_words({
        sentence => $sentence,
        words    => [$row->{words}],
    });

    if ($sentence =~ /\.\.\.$/) {
        $translations[0]{components}[-1]{no_tone_change} = 0;
    }

    Teochew::Edit->insert_phrase(
        sentence => $sentence,
        words => $translations[0]{components}
    );
    say colored("Inserted sentence '$sentence'", "green");

    $previous_sentence = $sentence;
}
