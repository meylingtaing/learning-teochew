#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use v5.10;

use DBI qw(:sql_types);
use Data::Dumper;

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_unicode} = 1;

# Get all the distinct english words
my @rows = $dbh->selectall_array(
    "select english, category_id from WordsBackup");

for my $row (@rows) {
    my $sth = $dbh->prepare(
        "update English set category_id = ? where word = ?");
    $sth->bind_param(1, $row->[1]);
    $sth->bind_param(2, $row->[0]);
    $sth->execute;
}
