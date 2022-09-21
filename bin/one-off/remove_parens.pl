#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use v5.10;

use DBI qw(:sql_types);
use Data::Dumper;
use String::Util qw(trim);

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_unicode} = 1;

my @rows = $dbh->selectall_array(
    "select id, word from English where word like '%(%' and hidden = 0",
    { Slice => {} }
);

for my $row (@rows) {
    # Extract the description in the parens
    my ($word, $notes) = $row->{word} =~ /^(.*)\((.*)\)$/;
    $word = trim($word);
    warn "$word: $notes\n";

    my $sth = $dbh->prepare(
        "update English set word = ?, notes = ? where id = ?");

    $sth->bind_param(1, $word);
    $sth->bind_param(2, $notes);
    $sth->bind_param(3, $row->{id}, SQL_INTEGER);

    $sth->execute;
}
