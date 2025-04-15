package Teochew::Edit;

=head1 NAME

Teochew::Edit

=head1 DESCRIPTION

Class for modifying the Teochew database

    my $db = Teochew::Edit->new;
    $db->insert_synonym('hello', 'hi');

=cut

use strict;
use warnings;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# Needed for reading/modifying the DB
use parent 'SqliteDB';
use DBI qw(:sql_types);

use Teochew::Utils qw(split_out_parens);

# Needed for interacting with the user
use feature qw(say);
use Term::ANSIColor qw(colored);
use Input qw(confirm input_from_prompt);

use Data::Dumper;

sub new { shift->create_db_object('Teochew.sqlite') }

=head1 METHODS THAT UPDATE THE DB DIRECTLY

=head2 insert_translation

    my $success = $teochew->insert_translation(
        category_id  => $category_id,
        english      => $english_main,
        notes        => $notes,
        english_sort => $sort,
        pengim       => $pengim,
        chinese      => $simplified,
        hidden       => $hidden,
        hidden_from_flashcards => 1,
    );

=cut

sub insert_translation {
    my ($self, %params) = @_;

    my $english_id = undef;
    if (defined $params{english}) {
        # Insert into the English table. It's possible this is a dupe, so check
        # for that first
        my %english_params =
            map { $_ => $params{$_} }
            qw(english notes category_id hidden english_sort);

        $english_id = $self->_get_english_id(%english_params) ||
                         $self->insert_english(%english_params);
    }

    # Insert into the Teochew table
    my $teochew_id = $self->_get_teochew_id(
        pengim  => $params{pengim},
        chinese => $params{chinese},
    );

    if ($teochew_id) {
        say colored("Teochew entry already exists", "yellow");
    }
    else {
        my $sth = $self->dbh->prepare(qq{
            insert into Teochew (pengim, chinese) values (?, ?)
        });

        $sth->bind_param(1, $params{pengim});
        $sth->bind_param(2, $params{chinese});

        $sth->execute;

        $teochew_id = $self->dbh->sqlite_last_insert_rowid;
    }

    # Now insert the Translation. If this is a dupe, this will fail since
    # there is a unique constraint on each english/teochew translation pair
    $self->dbh->do(qq{
        insert into Translation
        (english_id, teochew_id, hidden_from_flashcards)
        values (?, ?, ?)
    }, {}, $english_id, $teochew_id, $params{hidden_from_flashcards} ? 1 : 0);

    return $self->dbh->sqlite_last_insert_rowid;
}

=head2 update_english

    $teochew->update_english(
        $english_id,
        category_id => '',
        sort        => '',
    );

I will support more types of updates in the future

=cut

sub update_english {
    my ($self, $english_id, %params) = @_;
    $self = $self->new unless ref $self;

    die "No english_id given!" unless $english_id;

    my $sql = 'update english set ';
    my @binds;
    my @sets;

    if ($params{category_id}) {
        push @sets, "category_id = ?";
        push @binds, $params{category_id};
    }

    if ($params{sort}) {
        push @sets, "sort = ?";
        push @binds, $params{sort};
    }

    $self->dbh->do(
        'update english set ' . join(', ', @sets) .
        ' where id = ?',
        undef, @binds, $english_id
    );
}

=head2 insert_english

    $teochew->insert_english(
        category_id  => $category_id,
        english      => $english_main,
        notes        => $notes,
        hidden       => $hidden,
        english_sort => $sort,
    );

=cut

sub insert_english {
    my ($self, %params) = @_;

    # We want to insert NULL, not empty string if there are no notes
    $params{notes} = undef if $params{notes} eq '';

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare(
        "insert into English (category_id, word, notes, hidden, sort) " .
        "values (?,?,?,?,?)"
    );
    $sth->bind_param(1, $params{category_id}, SQL_INTEGER);
    $sth->bind_param(2, $params{english});
    $sth->bind_param(3, $params{notes});
    $sth->bind_param(4, $params{hidden} ? 1 : 0, SQL_INTEGER);
    $sth->bind_param(5, $params{english_sort}, SQL_INTEGER);
    $sth->execute;

    return $dbh->sqlite_last_insert_rowid;
}

=head2 update_teochew

    $teochew->update_teochew(
        $teochew_id,
        pengim  => '',
        chinese => '',
    );

=cut

sub update_teochew {
    my ($self, $teochew_id, %params) = @_;
    $self = $self->new unless ref $self;

    if (my $pengim = $params{pengim}) {
        $self->dbh->do(qq{
            update Teochew set pengim = ? where Teochew.id = ?
        }, undef, $pengim, $teochew_id);
    }

    if (my $chinese = $params{chinese}) {
        # If we're getting both simplified and traditional, just insert the
        # simplified
        my ($simplified, $traditional) = split_out_parens($chinese);
        $self->dbh->do(qq{
            update Teochew set chinese = ? where Teochew.id = ?
        }, undef, $simplified, $teochew_id);
    }
}

=head2 insert_synonym

    $teochew->insert_synonym(
        english => 'hello',
        synonym => 'hi'
    );

=cut

sub insert_synonym {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    my $english_id = $params{english_id} || _get_english_id(%params);
    return unless $english_id;

    my $sth = $self->dbh->prepare(
        "insert into Synonyms (english_id, word) values (?,?)"
    );
    $sth->bind_param(1, $params{english_id}, SQL_INTEGER);
    $sth->bind_param(2, $params{synonym});
    return $sth->execute;
}

=head2 tag_id

Returns the id of the tag with the given name

XXX: Maybe this would be more appropriate in the Teochew class?

=cut

sub tag_id {
    my ($self, $name) = @_;
    $self = $self->new unless ref $self;

    my $dbh = $self->dbh;
    my $id = $dbh->selectrow_array('select id from Tags where name = ?',
        undef, $name);

    return $id;
}

=head2 insert_tag

    my $id = $teochew->insert_tag('new tag name');

=cut

sub insert_tag {
    my ($self, $tag_name) = @_;
    $self = $self->new unless ref $self;

    my $dbh = $self->dbh;
    $dbh->do("insert into Tags (name) values (?)", undef, $tag_name);
    return $dbh->sqlite_last_insert_rowid;
}

=head2 add_tag_to_english

=cut

sub add_tag_to_english {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    my $english_id = $params{english_id};
    my $tag_id     = $params{tag_id};

    $self->dbh->do('insert into EnglishTags (english_id, tag_id) values (?,?)',
        undef, $english_id, $tag_id);
}

=head2 insert_category

    my $id = $teochew->insert_category('NewCategoryName');

Returns the id of the Categories row that was inserted

=cut

sub insert_category {
    my ($self, $category) = @_;
    $self = $self->new unless ref $self;

    my $dbh = $self->dbh;
    $dbh->do("insert into Categories (name) values (?)", undef, $category);
    return $dbh->sqlite_last_insert_rowid;
}

=head2 insert_chinese

    $teochew->insert_chinese(
        pengim          => 'chek8',
        standard_pengim => 'chik8', # optional
        simplified      => '',
        traditional     => '',
    );

=cut

sub insert_chinese {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    my @columns = qw(simplified pengim);
    my @binds = ($params{simplified}, $params{pengim});

    if ($params{traditional}) {
        push @columns, 'traditional';
        push @binds, $params{traditional};
    }

    if ($params{standard_pengim}) {
        push @columns, 'standard_pengim';
        push @binds, $params{standard_pengim};
    }

    my $col_str  = join ', ', @columns;
    my $bind_str = join ', ', ('?') x scalar @columns;

    my $sql = "insert into Chinese ($col_str) values ($bind_str)";
    my $sth = $self->dbh->prepare($sql);
    $sth->execute(@binds);
}

=head2 insert_alt_chinese

    $teochew->insert_alt_chinese(
        teochew_id => '',
        chinese    => '',
    );

=cut

sub insert_alt_chinese {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    my $sql = qq{
        insert into TeochewAltChinese (teochew_id, chinese)
        values (?, ?)
    };

    $self->dbh->do($sql, undef, $params{teochew_id}, $params{chinese});
}

=head2 insert_extra

    $teochew->insert_extra(
        english_id => '',
        info       => '',
    );

This will replace whatever extra information is already stored for this
English word.

=cut

sub insert_extra {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    my $dbh = $self->dbh;
    my $sth;

    if (!defined $params{info}) {
        $dbh->do("delete from Extra where english_id = ?", undef,
            $params{english_id});
        return;
    }

    if (defined Teochew::extra_information_by_id($params{english_id})) {
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

=head2 insert_phrase

    $teochew->insert_phrase(
        sentence => '',
        words    => '',
    );

=cut

sub insert_phrase {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    # First insert into the Phrases table if necessary
    my $phrase_id = $self->dbh->selectrow_array(
        "select id from Phrases where sentence = ?",
        undef, $params{sentence}
    );

    unless ($phrase_id) {
        my $sth = $self->dbh->prepare(
            "insert into Phrases (sentence) values (?)"
        );
        $sth->bind_param(1, $params{sentence});
        $sth->execute;

        $phrase_id = $self->dbh->sqlite_last_insert_rowid;
    }

    # And then insert into PhraseTranslations
    $self->dbh->do(qq{
        insert into PhraseTranslations (phrase_id, words)
        values (?, ?)
    }, undef, $phrase_id, $params{words});
}

=head2 make_fully_hidden

    $teochew->make_fully_hidden('hello');

=cut

sub make_fully_hidden {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    my $english_id = $params{english_id} || _get_english_id(%params);
    my $sth = $self->dbh->prepare(qq{
        update English set hidden = 1, hidden_from_flashcards = 1 where id = ?
    });
    $sth->bind_param(1, $params{english_id}, SQL_INTEGER);
    return $sth->execute;
}

=head2 update_translation

    $teochew->update_translation(
        $translation_id,
        hidden_from_flashcards => 1,
    );

=cut

sub update_translation {
    my ($self, $translation_id, %params) = @_;
    $self = $self->new unless ref $self;

    $self->dbh->do(qq{
        update Translation set hidden_from_flashcards = ?
        where id = ?
    }, undef, $params{hidden_from_flashcards}, $translation_id);
}

=head2 insert_compound_breakdown

    $teochew->insert_compound_breakdown(
        parent_teochew_id => 1,
        translation_ids   => [2, 3, 4],
    );

=cut

sub insert_compound_breakdown {
    my ($self, %params) = @_;

    my $i = 0;
    my @binds;
    for my $child_id (@{ $params{translation_ids} }) {
        push @binds, $params{parent_teochew_id}, ++$i, $child_id;
    }

    $self->dbh->do(qq{
        insert into Compound
        (parent_teochew_id, sort, translation_id)
        values
    } . join(", ", ("(?,?,?)") x $i), undef, @binds);
}

=head1 HELPERS FOR PROMPTING THE USER

=head2 choose_translation_from_english

    $teochew->choose_translation_from_english('hello');

Given an english word, this returns a hash with relevant translation
information. If there are multiple translations found, this will prompt the
user to choose one

The return hash will consist of three keys: C<english> and C<teochew>. Here is
an example of one:

  'english' => {
                 'id' => 1
                 'word' => 'hello',
                 'notes' => undef,
                 'category_name' => 'common',
                 'flashcard_set_name' => 'basics',
                 'category_display' => 'Common Phrases',
                 'category_id' => 1,
               },
  'teochew' => {
                 'teochew_id' => 1,
                 'chinese' => "\x{6c5d}\x{597d}",
                 'pengim' => 'leu2 ho2',
                 'translation_id' => 1
               },
=cut

sub choose_translation_from_english {
    my ($self, $english, $chinese) = @_;
    $self = $self->new unless ref $self;

    return undef unless defined $english;

    my %ret;

    my ($word, $notes) = split_out_parens($english);
    my ($english_row) = Teochew::get_english_from_database(
                    word => $word,
                    notes => $notes,
                    include_category_in_output => 1);

    die colored("$english does not exist!", "red") . "\n" unless $english_row;

    $ret{english} = $english_row;

    # Get existing translations -- there might be more than one. If so, have
    # the user select the one they want to modify
    my @rows = Teochew::get_all_translations_by_id($english_row->{id});

    if ($chinese) {
        @rows = grep { $_->{chinese} eq $chinese } @rows;
    }

    my $row_id = 0;
    if (scalar @rows == 0) {
        die "No matching translations found for $english!\n";
    }
    elsif (scalar @rows > 1) {
        # Need the user to select which translation they want to modify
        for (my $i = 0; $i < scalar @rows; $i++) {
            my $row = $rows[$i];
            say "$i: $row->{chinese} $row->{pengim}";
        }
        $row_id = input_from_prompt(
            "Which translation would you like to modify?");
    }

    $ret{teochew} = $rows[$row_id];

    return %ret;
}

=head2 ensure_chinese_is_in_database

    $teochew->ensure_chinese_is_in_database(
        chinese => "simp (trad)",
        pengim  => "syl1 syl2",
    );

Given a "simp (trad)" Chinese string and its corresponding pengim, this will
check each character, and make sure it exists in the database.

Returns the simplified Chinese string on success, and undef on error

=cut

sub ensure_chinese_is_in_database {
    my ($self, %params) = @_;
    $self = $self->new unless ref $self;

    my $chinese = $params{chinese};
    my $pengim  = $params{pengim};

    # Split up Chinese characters with simpl. and trad. We might need to add
    # them to the Chinese table in the database.
    my ($simplified, $traditional) = split_out_parens($chinese);
    my @simplified_chars  = split //, $simplified;
    my @traditional_chars = split //, $traditional;
    my @pengim_syllables  = split / /, $pengim;

    if (scalar @simplified_chars != scalar @pengim_syllables) {
        say colored(
            "The number of characters doesn't match $pengim!", "red"
        );
        return undef;
    }

    # Look at the Chinese character by character
    for (my $i = 0; $i < scalar @simplified_chars; $i++) {
        next if $simplified_chars[$i] eq '?';

        # The pengim might have had tone change -- if so, it would be inputted
        # like "ma3(2)", with the base tone listed first, and the changed tone
        # in parens. We need to associate the Chinese character with the base
        # tone
        my $pengim_orig = $pengim_syllables[$i] =~ tr/()//dr;
        $pengim_orig =~ s/(\d)(\d)/$1/;

        die "Poorly formatted pengim! [$pengim_orig]\n"
            unless $pengim_orig =~ /(1|2|3|4|5|6|7|8)$/;

        # Insert Chinese if it doesn't exist
        my $inserted = $self->confirm_and_insert_chinese(
            simplified  => $simplified_chars[$i],
            traditional => ($traditional_chars[$i] // ''),
            pengim      => $pengim_orig,
        );
        return undef unless $inserted;
    }

    return $simplified;
}

=head2 confirm_and_insert_chinese

Takes the same parameters as L</insert_chinese>. This will check and make sure
the chinese character doesn't already exist in the database, and if it doesn't,
it will prompt the user for confirmation to add it, and then add it.

=cut

sub confirm_and_insert_chinese {
    my ($self, %params) = @_;

    my $simplified      = $params{simplified};
    my $traditional     = $params{traditional};
    my $pengim          = $params{pengim};
    my $standard_pengim = $params{standard_pengim};

    unless (scalar Teochew::chinese_character_details($simplified, $pengim))
    {
        # Only insert the traditional character if it's different than
        # the simplified one
        my $insert_traditional =
            !$traditional               ? '' :
            $simplified eq $traditional ? '' : $traditional;

        my $prompt = sprintf "Inserting Chinese [%s (%s), %s]",
            $simplified,
            $insert_traditional,
            $pengim;

        $prompt .= ", standard pengim '$standard_pengim'" if $standard_pengim;

        say $prompt;
        if (confirm()) {
            $self->insert_chinese(
                simplified      => $simplified,
                traditional     => $insert_traditional,
                pengim          => $pengim,
                standard_pengim => $standard_pengim,
            );
        }
        else {
            return undef;
        }
    }
}

=head2 potential_compound_breakdown

Checks to see if there's a way we can automatically add a compound breakdown,
and if so, it returns that breakdown in a hash in this form:

    chinese => ['煮', '食'],
    pengim  => ['jeu2', 'jiah8'],
    english => ['to cook', 'to eat'],
    notes   => ['', ''],
    child_translation_ids => [1, 2],

Otherwise, this returns undef

TODO: There is some duplicated code between this and the add-compound-breakdown
script, find a way to consolidate it

=cut

sub potential_compound_breakdown {
    my ($self, %params) = @_;

    my $chinese = $params{chinese};
    my $pengim  = $params{pengim};

    my @chars     = split //,  $chinese;
    my @syllables = split / /, $pengim;

    my %breakdown = (chinese => \@chars);

    # Iterate through each syllable/character set
    for (my $i = 0; $i < scalar @chars; $i++) {

        # Determine the corresponding pengim for this set of characters
        my @pengim_parts;
        for (1..length($chars[$i])) {
            my $syllable = shift @syllables;
            push @pengim_parts, $syllable;
        }
        my $pengim_str = join ' ', @pengim_parts;

        push @{ $breakdown{pengim} }, $pengim_str;

        # Seach for a translation for this set of pengim and chinese. Note that
        # the pengim might have a tone change, but we only want the base tone
        # for searching
        $pengim_str =~ s/(\d)(\d)$/$1/;

        my @rows = $self->dbh->selectall_array(qq{
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

        # TODO: handle multiple rows?
        # For now, just return early if we can't find the right translation
        if (scalar @rows != 1) {
            return;
        }

        push @{ $breakdown{english} }, ($rows[0]{english} // '--');
        push @{ $breakdown{notes} }, ($rows[0]{notes} // '');
        push @{ $breakdown{child_translation_ids} }, $rows[0]{translation_id};
    }

    return %breakdown;
}

=head1 INTERNALS

=cut

sub _get_english_id {
    my ($self, %params) = @_;

    my $english = $params{english};
    my $note    = $params{notes};

    # Split out notes if it hasn't been done yet
    if ($english =~ /(.*) \((.*)\)/) {
        $english = $1;
        $note    = $2;
    }

    my $sql = "select id from English where word = ? ";
    my @binds = ($english);
    if ($note) {
        $sql .= "and notes = ?";
        push @binds, $note;
    }
    my @rows = $self->dbh->selectall_array($sql, {}, @binds);

    return unless scalar @rows;
    return $rows[0]->[0];
}

sub _get_teochew_id {
    my ($self, %params) = @_;

    my $pengim  = $params{pengim};
    my $chinese = $params{chinese};

    my @rows = $self->dbh->selectall_array(qq{
        select id from Teochew where pengim = ? and chinese = ?
    }, undef, $pengim, $chinese);

    return unless scalar @rows;
    return $rows[0]->[0];
}

1;
