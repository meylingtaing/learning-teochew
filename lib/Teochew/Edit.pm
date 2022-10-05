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

use parent 'SqliteDB';
use DBI qw(:sql_types);

sub new { shift->create_db_object('Teochew.sqlite') }

=head2 insert_translation

    my $success = $teochew->insert_word(
        category_id => $category_id,
        english     => $english_main,
        notes       => $notes,
        pengim      => $pengim,
        chinese     => $simplified,
        hidden      => $hidden,
        hidden_from_flashcards => 1,
    );

=cut

sub insert_translation {
    my ($self, %params) = @_;
    my $sth;

    # Insert into the English table. It's possible this is a dupe, so check for
    # that first
    my %english_params =
        map { $_ => $params{$_} } qw(english notes category_id hidden);

    my $english_id = $self->_get_english_id(%english_params) ||
                     $self->insert_english(%english_params);

    # Now insert the translation
    $sth = $self->dbh->prepare(qq{
        insert into Teochew
        (english_id, pengim, chinese, hidden_from_flashcards)
        values (?, ?, ?, ?)
    });

    $sth->bind_param(1, $english_id);
    $sth->bind_param(2, $params{pengim});
    $sth->bind_param(3, $params{chinese});
    $sth->bind_param(4, $params{hidden_from_flashcards} ? 1 : 0);

    $sth->execute;
}

=head2 insert_english

    $teochew->insert_english(
        category_id => $category_id,
        english     => $english_main,
        notes       => $notes,
        hidden      => $hidden,
    );

=cut

sub insert_english {
    my ($self, %params) = @_;

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare(
        "insert into English (category_id, word, notes, hidden) " .
        "values (?,?,?,?)"
    );
    $sth->bind_param(1, $params{category_id}, SQL_INTEGER);
    $sth->bind_param(2, $params{english});
    $sth->bind_param(3, $params{notes});
    $sth->bind_param(4, $params{hidden} ? 1 : 0, SQL_INTEGER);
    $sth->execute;

    return $dbh->sqlite_last_insert_rowid;
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
        pengim      => '',
        simplified  => '',
        traditional => '',
        meaning     => '',
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

    if ($params{meaning}) {
        push @columns, 'meaning';
        push @binds, $params{meaning};
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

    my $sth = $self->dbh->prepare(
        "insert into Phrases (sentence, words) values (?,?)"
    );
    $sth->bind_param(1, $params{sentence});
    $sth->bind_param(2, $params{words});
    $sth->execute;
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

1;
