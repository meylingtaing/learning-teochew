#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);
use lib 'lib';

binmode STDOUT, ':encoding(UTF-8)';

use Data::Dumper;
use Term::ANSIColor qw(colored);
use Getopt::Long qw(GetOptionsFromArray);

use Input qw(confirm input_via_editor);
use Teochew;
use Teochew::Edit;
use Teochew::Utils qw(split_out_parens);

my ($english, @other_args) = @ARGV;

die "Must include English!\n" unless $english;

my $edit_translation_note;
my $getopt_success = GetOptionsFromArray(\@other_args,
    translation => \$edit_translation_note,
);

exit unless $getopt_success;

my $db = Teochew::Edit->new;

# Make sure the english word exists already
my ($word, $notes) = split_out_parens($english);
my ($row) = Teochew::get_english_from_database(
    word => $word, notes => $notes);
die "$english does not exist!\n" unless $row;

# Do we want to insert notes for the english word or for any translations?
my $existing;
my $translation_id;
if ($edit_translation_note) {
    my %translation = $db->choose_translation_from_english($english);
    $translation_id = $translation{teochew}{translation_id};
    $existing = Teochew::extra_translation_information_by_id($translation_id);
}
else {
    $existing = Teochew::extra_information_by_id($row->{id});
}

# Check if we already have notes
my $info = input_via_editor($existing);

if ($info eq '') {
    say "Deleting extra notes for $english\n";
    $info = undef;
}
else {
    say "Inserting these notes for $english:\n$info";
}

if (confirm()) {
    if ($edit_translation_note) {
        if ($existing) {
            $db->dbh->do(qq{
                update TranslationExtra
                set info = ?
                where translation_id = ?
            }, undef, $info, $translation_id);
        }
        else {
            $db->dbh->do(qq{
                insert into TranslationExtra (translation_id, info)
                values (?, ?)
            }, undef, $translation_id, $info);
        }
    }
    else {
        Teochew::Edit->insert_extra(
            english_id => $row->{id},
            info       => $info,
        );
    }
    say colored("Successfully updated the extra info for $english", 'green');
}
