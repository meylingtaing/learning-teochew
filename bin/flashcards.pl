#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);
use utf8;

use DBI qw(:sql_types);
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);
use Data::Dumper;

use lib 'lib';

use Input;
use Teochew;
use Teochew::Edit;
use Teochew::Utils qw(split_out_parens);
use Term::ANSIColor;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

# Get all the categories
my @category_rows = $dbh->selectall_array("select id, name from Categories");
my %categories = map { $_->[1] => $_->[0] } @category_rows;

# XXX: Use a module for IO stuff?

# Determine what the user wants to do
my $command = (shift @ARGV) || '';
if ($command eq 'insert') {
    die "This is not supported anymore. Use insert-flashcard.pl instead\n";
}
elsif ($command eq 'update') {
    my ($english) = @ARGV;

    my ($word, $notes) = split_out_parens($english);

    # Find the word in english to make sure it exists
    my $english_id = get_english_id(
        english => $word, notes => $notes, no_insert => 1);

    die "$english doesn't exist in the database!\n"
        unless $english_id;

    # Get existing translations -- there might be more than one
    my @rows = Teochew::get_all_translations_by_id($english_id);

    my $row_id = 0;

    if (scalar @rows == 0) {
        die "No translations found for $english!\n";
    }
    elsif (scalar @rows > 1) {
        # Need the user to select which translation they want to modify
        for (my $i = 0; $i < scalar @rows; $i++) {
            my $row = $rows[$i];
            say "$i: $row->{chinese} $row->{pengim}";
        }
        $row_id = get_input_from_prompt(
            "Which translation would you like to modify?");
    }

    # Look up the category
    my ($category, $category_id) = $dbh->selectrow_array(qq{
        select name, category_id from English
        join Categories on category_id = Categories.id
        where English.id = ?
    }, undef, $english_id);

    # Now allow the user to change things
    my $new_category = get_input_from_prompt("Category ($category):");

    my $new_note = get_input_from_prompt("Note ($notes):");
    my $pengim   = get_input_from_prompt("Pengim ($rows[$row_id]{pengim}):");
    my $chinese  = get_input_from_prompt("Chinese ($rows[$row_id]{chinese}):");

    die "Nothing to modify!\n"
        unless $new_note || $new_category || $pengim || $chinese;

    # XXX This does not let you clear out a note
    if ($new_note || $new_category) {
        say "Modifying english to $new_category: $word ($new_note)";
        if (confirm()) {
            $notes ||= $new_note;
            if ($new_category) {
                # Check and see if category exists...
                $category_id = $categories{$new_category};
                unless ($category_id) {
                    die "Category doesn't exist!\n";
                }
            }

            my $rows_affected =
                $dbh->do(qq{
                    update english set notes = ?, category_id = ?
                    where id = ?
                }, undef, $notes, $category_id, $english_id);
            die "Failed to update note!" unless $rows_affected;
            say colored(
                "Updated english to $new_category: $word ($new_note)!",
                "green"
            );
        }
    }

    # TODO: Finish this
    if ($pengim || $chinese) {
        $pengim  ||= $rows[$row_id]{pengim};
        $chinese ||= $rows[$row_id]{chinese};

        # Find the existing chinese entry for this character, in case the
        # user wants to modify it
        my $existing_chinese = Teochew::chinese_character_details(
            $rows[$row_id]{chinese}, $rows[$row_id]{pengim});
        if ($existing_chinese) {
            say "Found a Chinese entry for " .
                "$rows[$row_id]{chinese} $rows[$row_id]{pengim}. Update?";
            if (confirm()) {
                my $rows_affected = $dbh->do(qq{
                    update chinese set pengim = ?, simplified = ? where id = ?
                }, undef, $pengim, $chinese, $existing_chinese->[0]{chinese_id});
            }
        }

        say "Modifying $english translation to $chinese $pengim";
        if (confirm()) {
            my $rows_affected = $dbh->do(qq{
                update teochew set pengim = ?, chinese = ? where id = ?
            }, undef, $pengim, $chinese, $rows[$row_id]{teochew_id});
            die "Failed to update translation!" unless $rows_affected;
            say colored("Updated teochew to $chinese $pengim", "green");
        }
    }
}
elsif ($command eq 'insert_phrase') {
    my ($sentence, $words) = @ARGV;

    # First check and make sure this is translatable using the words we
    # already have. This will die if we can't translate it.
    my $phrase = Teochew::replace_variables({
        sentence => $sentence, words => $words });

    my $translation = Teochew::_translate_phrase($phrase);

    say "Inserting phrase \"$sentence\" with translation \"" .
        $translation->{pengim} . "\"";

    if (confirm()) {
        insert_phrase(sentence => $sentence, words => $words);
    }
}
elsif ($command eq 'insert_chinese') {
    my ($chinese, $pengim, $meaning) = @ARGV;

    # Require both Chinese and pengim
    die "Must include chinese and pengim!" unless $chinese and $pengim;

    # See if we have both simplified AND traditional given
    my ($simplified, $traditional) = split_out_parens($chinese);
    $meaning ||= '';

    # Tell the user what we're doing before proceeding
    say "Inserting Chinese [$simplified ($traditional), $pengim, $meaning]";
    if (confirm()) {
        insert_chinese(
            simplified  => $simplified,
            traditional => $traditional,
            pengim      => $pengim,
            meaning     => $meaning,
        );
    }
}
elsif ($command eq 'insert_synonym') {
    my ($english, $synonym) = @ARGV;

    die "Must include English and synonym!\n" unless $english and $synonym;

    my ($word, $notes) = split_out_parens($english);

    # Make sure the english word exists already
    my $english_id = get_english_id(
        english => $word, notes => $notes, no_insert => 1);
    die "$english does not exist!\n" unless $english_id;

    say "Inserting $synonym as synonym for $english";
    if (confirm()) {
        Teochew::Edit->insert_synonym(english_id => $english_id, synonym => $synonym);
    }
}
elsif ($command eq 'hide') {
    my ($english) = @ARGV;

    die "Must include English!\n" unless $english;

    # Make sure the english word exists already
    my $english_id = Teochew::Edit->_get_english_id(english => $english);
    die "$english does not exist!\n" unless $english_id;

    say "Hiding English word '$english'";
    if (confirm()) {
        Teochew::Edit->make_fully_hidden(english_id => $english_id);
    }
}
elsif ($command eq 'insert_extra') {
    my ($english) = @ARGV;

    die "Must include English!\n" unless $english;

    # Make sure the english word exists already
    my $english_id = get_english_id(english => $english, no_insert => 1);
    die "$english does not exist!\n" unless $english_id;

    # Check if we already have notes
    my $existing = get_info($english_id);

    my $info = Input::via_editor($existing);

    say "Inserting these notes for $english:\n$info";
    if (confirm()) {
        insert_extra(
            english_id => $english_id,
            info       => $info,
            replacing  => $existing ? 1 : 0
        );
    }
}
else {
    die "Need an insert command!\n";
}

sub confirm {
    print "Is this okay? ";
    my $yesno = <STDIN>;
    chomp $yesno;
    return 1 if substr($yesno, 0, 1) eq 'y';
    return 0;
}

sub add_accents {
    my $word = shift;

    # Add grave accent
    $word =~ s/([a-z])`/$1\N{U+0340}/g;

    # Add acute accent
    $word =~ s/([a-z])'/$1\N{U+0341}/g;

    # Add dot
    $word =~ s/([a-z])\./$1\N{U+0323}/g;

    # Add macron
    $word =~ s/([a-z])-/$1\N{U+0304}/g;

    # Add breve
    $word =~ s/([a-z])3/$1\N{U+0306}/g;

    return $word;
}

sub get_english_id {
    my %params = @_;
    my $english_id;

    my $sql = "select id from English where word = ? ";
    my @binds = ($params{english});

    if ($params{notes}) {
        $sql .= "and notes = ?";
        push @binds, $params{notes};
    }
    else {
        $sql .= "and (notes is null or notes = '')";
    }

    # Check and see if english exists already
    my @rows = $dbh->selectall_array($sql, {}, @binds);

    if (scalar @rows) {
        printf "English word %s already exists\n", $params{english}
            unless $params{no_insert};
        $english_id = $rows[0]->[0];
    }
    else {
        return undef if $params{no_insert};

        # Insert into english
        my $sth = $dbh->prepare(
            "insert into English (category_id, word, notes, hidden) " .
            "values (?,?,?,?)"
        );
        $sth->bind_param(1, $params{category}, SQL_INTEGER);
        $sth->bind_param(2, $params{english});
        $sth->bind_param(3, $params{notes});
        $sth->bind_param(4, $params{hidden}, SQL_INTEGER);
        $sth->execute;

        $english_id = $dbh->sqlite_last_insert_rowid;
    }

    return $english_id;
}

sub insert_synonym {
    my %params = @_;
    my $sth = $dbh->prepare(
        "insert into Synonyms (english_id, word) values (?,?)"
    );
    $sth->bind_param(1, $params{english_id});
    $sth->bind_param(2, $params{synonym});
    $sth->execute;
}

sub insert_extra {
    my %params = @_;
    my $sth;
    if ($params{replacing}) {
        $sth = $dbh->prepare(
            "update Extra set info = ? where english_id = ?"
        );
    }
    else {
        $sth = $dbh->prepare(
            "insert into Extra (info, english_id) values (?,?)"
        );
    }
    $sth->bind_param(1, $params{info});
    $sth->bind_param(2, $params{english_id});
    $sth->execute;
}

sub insert_phrase {
    my %params = @_;
    my $sth = $dbh->prepare(
        "insert into Phrases (sentence, words) values (?,?)"
    );
    $sth->bind_param(1, $params{sentence});
    $sth->bind_param(2, $params{words});
    $sth->execute;
}

# XXX: Error checking?
sub insert_word {
    my %params = @_;
    my $sth;

    # Insert into english first
    my $english_id = get_english_id(%params);

    # Now insert the translation
    if ($params{characters}) {
        $sth = $dbh->prepare(
            "insert into Teochew (english_id, pengim, chinese) " .
            "values (?,?,?)"
        );

        $sth->bind_param(3, $params{characters});
    }
    else {
        $sth = $dbh->prepare(
            "insert into Teochew (english_id, pengim) values (?,?)"
        );
    }

    $sth->bind_param(1, $english_id);
    $sth->bind_param(2, $params{teochew});

    $sth->execute;
}

sub insert_chinese {
    my %params = @_;

    my @columns = qw(simplified pengim);
    my @binds = ($params{simplified}, $params{pengim});

    if ($params{traditional}) {
        push @columns, 'traditional';
        push @binds, $params{traditional};
    }

    if ($params{meaning}) {
        push @columns, 'meaning';
        push @binds, $params{meaning};
    }

    my $col_str  = join ', ', @columns;
    my $bind_str = join ', ', ('?') x scalar @columns;

    my $sql = "insert into Chinese ($col_str) values ($bind_str)";
    my $sth = $dbh->prepare($sql);
    $sth->execute(@binds);
}

sub get_info {
    my $english_id = shift;
    my @rows = $dbh->selectall_array(
        'select info from Extra where english_id = ?',
        {}, $english_id
    );

    return undef unless scalar @rows;
    return $rows[0]->[0];
}

sub get_input_from_prompt {
    my $prompt = shift;
    print "$prompt ";
    my $input = <STDIN>;
    chomp $input;
    return $input;
}
