#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

# TODO: THIS SCRIPT IS NOT DONE

use strict;
use warnings;

use feature qw(say);
use lib 'lib';

use utf8;
binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

use Data::Dumper;
use Getopt::Long qw(GetOptionsFromArray);
use Term::ANSIColor qw(colored);

use Teochew;
use Teochew::Edit;
use Teochew::Utils qw(split_out_parens);
use Input qw(confirm input_from_prompt);

my $db = Teochew::Edit->new;

# First argument should be the simplified Chinese character
my $simplified = shift @ARGV;

# Let's see what the user wants to update
# TODO: Add more options
my ($pengim, $standard_pengim);
GetOptions(
    "pengim=s"          => \$pengim,
    "standard-pengim=s" => \$standard_pengim,
);

die colored ("Must provide pengim or standard-pengim!", "red") . "\n"
    unless $pengim || $standard_pengim;

# Find the Chinese character in the database
my $rows = Teochew::chinese_character_details(
    $simplified, undef, no_alt_pengim => 1);

die colored("Could not find entry in the database for $simplified!", "red") . "\n"
    unless $rows;

my $row = $rows->[0];
if (scalar @$rows > 1) {
    # Need the user to select which Chinese entry to update
    for (my $i = 0; $i < scalar @$rows; $i++) {
        my $row = $rows->[$i];
        say "$i: $row->{pengim}";
    }
    my $row_id = input_from_prompt(
        "Which translation would you like to modify?");
    $row = $rows->[$row_id];
}

if ($pengim) {
    $db->dbh->do("update Chinese set pengim = ? where id = ?",
        undef, $pengim, $row->{chinese_id});

    # Check and see if there are any teochew entries to update
    my @teochew_rows = $db->dbh->selectall_array(qq{
        select * from Teochew where Chinese like ? and pengim like ?
    }, { Slice => {} }, "%$simplified%", "%$row->{pengim}%");

    # Next, I need to double check that the pengim actually does match for the
    # particular syllable. And then I need to prompt the user to see if they want
    # to fix it
}

if ($standard_pengim) {
    $db->dbh->do("update Chinese set standard_pengim = ? where id = ?",
        undef, $standard_pengim, $row->{chinese_id});
    say colored("Added standard pengim!", "green");
}
