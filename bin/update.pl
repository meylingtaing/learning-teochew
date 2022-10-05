#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use lib 'lib';

use Input qw(input_via_editor);
use DBI;

my $command = (shift @ARGV) || 'new';
my $dbh = DBI->connect("DBI:SQLite:dbname=Updates.sqlite");
my $content = '';
my $id;

if ($command eq 'edit') {

    # Find the latest update
    my @row = $dbh->selectall_array(
        "select id, content from Updates " .
        "order by time_stamp desc limit 1"
    );

    if (scalar @row) {
        $id      = $row[0]->[0];
        $content = $row[0]->[1];
    }
}

$content = input_via_editor($content);

# Save it to the database
my $sth;
if ($id) {
    $sth = $dbh->prepare(qq{
        update Updates
        set content = ?, time_stamp = datetime('now', 'localtime')
        where id = ?
    });
    $sth->bind_param(1, $content);
    $sth->bind_param(2, $id);
}
else {
    $sth = $dbh->prepare(
        "insert into Updates (content, time_stamp) " .
        "values (?, datetime('now', 'localtime'))");
    $sth->bind_param(1, $content);
}

$sth->execute;
