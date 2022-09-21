package Teochew::Edit;

use strict;
use warnings;

use DBI qw(:sql_types);
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

=head2 insert_synonym

    Teochew::Edit::insert_synonym(
        english => 'hello',
        synonym => 'hi'
    );

=cut

sub insert_synonym {
    my %params = @_;

    my $english_id = $params{english_id} || _get_english_id(%params);
    return unless $english_id;

    my $sth = $dbh->prepare(
        "insert into Synonyms (english_id, word) values (?,?)"
    );
    $sth->bind_param(1, $params{english_id}, SQL_INTEGER);
    $sth->bind_param(2, $params{synonym});
    return $sth->execute;
}

=head2 make_fully_hidden

    Teochew::Edit::make_fully_hidden('hello');

=cut

sub make_fully_hidden {
    my %params = @_;

    my $english_id = $params{english_id} || _get_english_id(%params);
    my $sth = $dbh->prepare(qq{
        update English set hidden = 1, hidden_from_flashcards = 1 where id = ?
    });
    $sth->bind_param(1, $params{english_id}, SQL_INTEGER);
    return $sth->execute;
}

sub _get_english_id {
    my %params = @_;

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
    my @rows = $dbh->selectall_array($sql, {}, @binds);

    return unless scalar @rows;
    return $rows[0]->[0];
}
