#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use v5.10;

use DBI qw(:sql_types);
use Data::Dumper;

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_unicode} = 1;

# Select id, english, teochew rows with new lines in teochew
my @rows = $dbh->selectall_array(
    "select id, english, teochew, category_id from Words " .
    "where teochew like ?",
    { Slice => {} }, "%\n%"
);

for my $row (@rows) {

    # Split up the teochew
    my @teochew = split /\n/, $row->{teochew};

    # Insert new rows
    for (@teochew) {
        my $sth = $dbh->prepare(
            "insert into Words (english, teochew, category_id) " .
            "values (?, ?, ?)"
        );
        $sth->bind_param(1, $row->{english});
        $sth->bind_param(2, $_);
        $sth->bind_param(3, $row->{category_id}, SQL_INTEGER);
        $sth->execute;
    }

    # Delete the original row
    my $sth = $dbh->prepare("delete from Words where id = ?");
    $sth->bind_param(1, $row->{id}, SQL_INTEGER);
    $sth->execute;
}
