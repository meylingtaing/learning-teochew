#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use v5.10;

use DBI qw(:sql_types);
use Data::Dumper;

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_unicode} = 1;

# Get all the distinct english words
my @rows = $dbh->selectall_array("select distinct(english) from WordsBackup");

for my $row (@rows) {

    my $english = $row->[0];

    # Insert word into English table
    my $sth = $dbh->prepare('insert into English (word) values (?)');
    $sth->bind_param(1, $english);
    $sth->execute;

    my $english_id = $dbh->sqlite_last_insert_rowid;

    # Update teochew words with that English
    $sth = $dbh->prepare(
        'update Words set english_id = ? where teochew in ' .
        '(select teochew from WordsBackup where english = ?)'
    );
    $sth->bind_param(1, $english_id);
    $sth->bind_param(2, $english);
    $sth->execute;
}
