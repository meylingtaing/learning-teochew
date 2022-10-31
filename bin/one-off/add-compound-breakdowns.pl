#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use utf8;
use feature qw(say);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

use lib 'lib';
use Teochew;
use Teochew::Edit;

use Teochew::Utils qw();
use Input qw(confirm input_from_prompt);

use Data::Dumper;
use Term::ANSIColor qw(colored);

my $db = Teochew::Edit->new;

# Usage: add-compound-breakdowns.pl "hello"
#        add-compound-breakdowns.pl "week" "一,礼拜"
#
# This takes the english word as the first argument.
# You can optionally provide a second argument to show the breakdown of words.
# It will assume to break it down character by character if not given.
my $input     = shift @ARGV;
my $breakdown = shift @ARGV;

die colored("Must provide an English word!", "red") . "\n"
    unless defined $input;

my $chinese = $breakdown ? $breakdown =~ s/,//gr : undef;
my %translation = $db->choose_translation_from_english($input, $chinese);
my $teochew = $translation{teochew};

if (length($teochew->{chinese}) == 1) {
    say "Only one Chinese character: $teochew->{chinese}!";
    exit;
}

# Break down the word character by character and see if there are other Teochew
# entries that match
my @chars;
if ($breakdown) {
    @chars = split /,/, $breakdown;
}
else {
    @chars = split //, $teochew->{chinese};
}

my @syllables = split / /, $teochew->{pengim};

my @child_ids;
my $confirm_str = "Compound breakdown:";
for (my $i = 0; $i < scalar @chars; $i++) {

    # Determine the corresponding pengim for this set of characters
    my @pengim_parts;
    for (1..length($chars[$i])) {
        my $syllable = shift @syllables;
        push @pengim_parts, $syllable;
    }
    my $pengim_str = join ' ', @pengim_parts;

    say "Character: $chars[$i]";
    say "Pengim syllable: $pengim_str\n";

    # The pengim might have a tone change, but we only want the base tone for
    # searching
    $pengim_str =~ s/(\d)(\d)$/$1/;

    my @rows = $db->dbh->selectall_array(qq{
        select
            Translation.id translation_id,
            English.word english,
            English.notes notes
        from Teochew
        join Translation on Translation.teochew_id = Teochew.id
        left join English on Translation.english_id = English.id
        where chinese = ? and pengim = ?
        order by Teochew.id
    }, { Slice => {} }, $chars[$i], $pengim_str);

    if (scalar @rows == 0) {
        say colored(
            "Need to create empty translation for $chars[$i] $pengim_str",
            "yellow"
        );
        if (confirm()) {
            # XXX fill this in...
            my $translation_id = $db->insert_translation(
                chinese => $chars[$i],
                pengim  => $syllables[$i],
            );
            $rows[0] = {
                translation_id => $translation_id,
                english        => undef,
                notes          => undef,
            };
        }
    }

    # If there's a single match, then use that. If there are multiple matches,
    # prompt the user for the correct one
    my $row_id = 0;
    if (scalar @rows > 1) {
        for (my $j = 0; $j < scalar @rows; $j++) {
            my $msg = "$j: $rows[$j]{english}";
            $msg .= " ($rows[$j]{notes})" if $rows[$j]{notes};
            say $msg;
        }
        $row_id = input_from_prompt(
            "Which translation to use for $chars[$i] $pengim_str?");
    }

    $rows[$row_id]{english} //= '--';

    # XXX: I did not error check
    push @child_ids, $rows[$row_id]{translation_id};
    $confirm_str .= "\n\t$rows[$row_id]{english}";
    $confirm_str .= " ($rows[$row_id]{notes})" if $rows[$row_id]{notes};
}

say $confirm_str;
if (confirm()) {
    $db->insert_compound_breakdown(
        parent_teochew_id => $teochew->{teochew_id},
        translation_ids   => \@child_ids,
    );
    say colored("Added compound breakdown!", "green");
}
