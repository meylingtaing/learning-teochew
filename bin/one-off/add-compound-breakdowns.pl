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

# TODO: There is some duplicated code between this and the
# potential_compound_breakdown method, find a way to consolidate it

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

$db->confirm_and_insert_compound_breakdown(
    breakdown         => $breakdown // $teochew->{chinese},
    pengim            => $teochew->{pengim},
    parent_teochew_id => $teochew->{teochew_id},
);
