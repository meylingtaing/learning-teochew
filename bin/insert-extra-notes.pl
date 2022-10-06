#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);
use lib 'lib';

binmode STDOUT, ':encoding(UTF-8)';

use Term::ANSIColor qw(colored);

use Input qw(confirm input_via_editor);
use Teochew;
use Teochew::Edit;

my ($english) = @ARGV;

die "Must include English!\n" unless $english;

# Make sure the english word exists already
my ($row) = Teochew::get_english_from_database(word => $english);
die "$english does not exist!\n" unless $row;

# Check if we already have notes
my $existing = Teochew::extra_information_by_id($row->{id});
my $info = input_via_editor($existing);

if ($info eq '') {
    say "Deleting extra notes for $english\n";
    $info = undef;
}
else {
    say "Inserting these notes for $english:\n$info";
}

if (confirm()) {
    Teochew::Edit->insert_extra(
        english_id => $row->{id},
        info       => $info,
    );
    say colored("Successfully updated the extra info for $english", 'green');
}
