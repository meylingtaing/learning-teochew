#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

use DBI qw(:sql_types);
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);
use List::MoreUtils qw(uniq);

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

# All of the alternate pronunciations that I know of
my %alt = (
    ek    => 'ik',
    ngeng => 'nging',
    chek  => 'chik',
    geng  => 'ging',
    yek   => 'yik',
);
my %skip = map { $_ => 1 } values %alt;

# Find all of the pengim from Chinese characters
my $rows = $dbh->selectall_arrayref('select pengim from Chinese');

# Remove the tone number, and fix all the pronunciations that end in 't' to
# end in 'h' instead
my @pengims = uniq sort map {
    my $pengim = $_->[0];
    $pengim =~ s/(.*)t$/$1h/;
    $pengim =~ s/\d//g;
    $pengim;
} @$rows;

for my $pengim (@pengims) {

    # Figure out the beginning sound
    my $beginning;
    if ($pengim =~ /^([aeiou])/) {
        $beginning = $1;
    }
    elsif ($pengim =~ /^([^aeiou]+)/) {
        $beginning = $1;
    }
    else {
        die "$pengim doesn't seem to make sense";
    }

    # Add it to the database
    my @rows = $dbh->selectall_array(qq{
        select beginning, full from pengim
        where full = ?
    }, { Slice => {} }, $pengim);
    unless (@rows) {
        $dbh->do("insert into Pengim (beginning, full) values (?, ?)",
           undef, $beginning, $pengim); 

        if ($alt{$pengim}) {
            $dbh->do(qq{
                insert into PengimAlt (pengim_id, beginning, full)
                values (?, ?, ?)
            }, undef, $dbh->sqlite_last_insert_rowid, $beginning, $alt{$pengim});
        }
        say "Inserted $pengim";
    }
}
