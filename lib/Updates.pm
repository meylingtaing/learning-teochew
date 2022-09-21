package Updates;

use strict;
use warnings;

use DBI;
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);
use Date::Format;
use Date::Parse;

=head1 NAME

Updates

=head1 SYNOPSIS

=head1 METHODS

=head2 get_updates

Gets the updates from the database

=cut

my $dbh = DBI->connect("DBI:SQLite:dbname=Updates.sqlite");
$dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

sub get_updates {
    my $page = shift || 0;

    # Fetch updates from the database
    my @rows = $dbh->selectall_array(
        "select time_stamp, content from Updates " .
        "order by time_stamp desc limit 6 offset ?",
        { Slice => {} }, $page * 5
    );

    # Make the timestamp look a little nicer
    for my $row (@rows) {
        my $datetime       = str2time($row->{time_stamp});
        $row->{time_stamp} = time2str("%B %e, %Y", $datetime);
    }

    return \@rows;
}
