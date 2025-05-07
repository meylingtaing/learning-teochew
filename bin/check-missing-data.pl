#!/usr/bin/env -S perl -Ilocal/lib/perl5

# Usage: check-missing-data.pl $command
# where command is one of these:
#   chinese:           translation without chinese characters
#   audio:             translation without an audio recording
#   character_details: chinese character with details missing
#   phrase:            phrase without audio recording
#   hidden:            translations that are fully hidden

use strict;
use warnings;

use feature qw(say);

use DBI qw(:sql_types);
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);

use lib 'lib';
use open ':std', ':encoding(utf8)';

use Teochew;

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

my $command = (shift @ARGV) || '';
my @commands_to_run = $command ?
    ($command) : (
        'chinese',
        'audio',
        'character_details',
        'phrase',
        'compound_breakdown',
        'hidden',
    );

my @rows;

if (grep /^chinese$/, @commands_to_run) {
    @rows = $dbh->selectall_array(
        "select English.word as english, Teochew.pengim as teochew " .
        "from Teochew " .
        "join English on English.id = english_id " .
        "where hidden = 0 and chinese is null", { Slice => {} }
    );

    say "Missing Chinese character:";
    say $_->{english} . " " . $_->{teochew} for @rows;
    print "\n";
}

if (grep /^audio$/, @commands_to_run) {
    @rows = $dbh->selectall_array(
        "select English.word as english, Teochew.pengim as teochew " .
        "from Teochew " .
        "join English on English.id = english_id " .
        "where hidden = 0 and hidden_from_flashcards = 0",
        { Slice => {} }
    );

    say "Missing audio:";
    for (@rows) {

        # Look for the alt pronunication because that's the one I care about
        $_->{teochew} =~ s/\d(\d)/$1/g;
        my $alt = Teochew::_alternate_pronunciation($_->{teochew});

        say $_->{english} . " " . $_->{teochew}
            unless Teochew::find_audio($alt || $_->{teochew});
    }
    print "\n";
}

if (grep /^phrase$/, @commands_to_run) {
    @rows = Teochew::generate_translation_word_list(
        category => 'phrase', subcategory => 'all'
    );

    say "Missing phrase audio:";
    for (@rows) {
        say $_->{english} . " " . $_->{teochew}->[0]->{pengim}
            unless $_->{teochew}->[0]->{audio};
    }
    print "\n";
}

if (grep /^character_details$/, @commands_to_run) {
    @rows = $dbh->selectall_array(
        "select chinese, pengim from Teochew " .
        "where chinese is not null",
        { Slice => {} }
    );

    say "Missing chinese character details:";
    for (@rows) {
        # Split up each character by character
        # XXX: Maybe deal with pengim later? But that's a lot harder
        my @characters = split //,  $_->{chinese};
        my @pengim     = split / /, $_->{pengim};
        for (my $i = 0; $i < scalar @characters; $i++) {
            say $characters[$i] . " " . $pengim[$i]
                unless $characters[$i] eq '?'
                or Teochew::chinese_character_details($characters[$i]);
        }
    }
    print "\n";
}

if (grep /^hidden$/, @commands_to_run) {
    @rows = $dbh->selectall_array(qq{
        select word, notes from English
        join Translation on English.id = Translation.english_id
        join Teochew on Translation.teochew_id = Teochew.id
        where hidden = 1
    });

    say "Hidden words:";
    for (@rows) {
        my $word = $_->[0];
        $word .= " ($_->[1])" if $_->[1];
        say $word;
    }
    print "\n";
}

if (grep /^compound_breakdown/, @commands_to_run) {

    # Find all the english words that translate to multisyllable teochew
    # (if there's a space, then there are multiple syllables) that don't have
    # any corresponding "compound" entries
    @rows = $dbh->selectall_array(qq{
        select word, notes from English
        join Translation on English.id = Translation.english_id
        join Teochew on Translation.teochew_id = Teochew.id
        left join Compound on Compound.parent_teochew_id = Teochew.id
        where pengim like '% %' and Compound.id is null
        and English.hidden = 0
    });

    say "Missing compound breakdowns";
    for (@rows) {
        my $word = $_->[0];
        $word .= " ($_->[1])" if $_->[1];
        say $word;
    }
    print "\n";
}
