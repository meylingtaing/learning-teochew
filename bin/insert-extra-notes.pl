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
my @other_english;

my $getopt_success = GetOptionsFromArray(\@other_args,
    "other_english=s" => \@other_english,
    translation       => \$edit_translation_note,
);

exit unless $getopt_success;

my $db = Teochew::Edit->new;

# Make sure the english word exists already
my @all_english;
for my $input ($english, @other_english) {
    my ($word, $notes) = split_out_parens($input);
    my ($row) = Teochew::get_english_from_database(
        word => $word, notes => $notes);
    die "$english does not exist!\n" unless $row;
    push @all_english, $row;
}

# Do we want to insert notes for the english word or for any translations?
my $existing;
my $translation_id;
if ($edit_translation_note) {
    die "Can't edit translation notes for multiple words at once!\n"
        if @all_english > 1;
    my %translation = $db->choose_translation_from_english($english);
    $translation_id = $translation{teochew}{translation_id};
    $existing = Teochew::extra_translation_information_by_id($translation_id);
}
else {

    # XXX I guess I should error check here that they all have the same note
    $existing = Teochew::extra_information_by_id($all_english[0]{id});
}

# Check if we already have notes
my $info = input_via_editor($existing);

my $english_words_str = join(", ", ($english, @other_english));
if ($info eq '') {
    say "Deleting extra notes for $english_words_str\n";
    $info = undef;
}
else {
    say "Inserting these notes for $english_words_str:\n$info";
}

if (confirm()) {
    if ($edit_translation_note) {

        # TODO: handle deleting extra translation notes

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
            english_ids => [ map { $_->{id} } @all_english ],
            info        => $info,
        );
    }
    say colored(
        "Successfully updated the extra info for $english_words_str", 'green');
}
