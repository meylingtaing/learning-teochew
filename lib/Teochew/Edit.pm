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
    my $note    = undef;

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
