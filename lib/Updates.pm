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

=head2 new

=cut

sub new {
    my $class = shift;

    # Just hardcoding the name of the database file for now, but maybe I should
    # add a configuration file later, and put it there
    my $dbh = DBI->connect("DBI:SQLite:dbname=Updates.sqlite")
        or die $DBI::errstr;
    $dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

    my $self = { dbh => $dbh };
    bless $self, $class;
    return $self;
}

=head2 get_updates

Gets the updates from the database

=cut

sub get_updates {
    my ($self, $page) = @_;
    $page ||= 0;

    # Fetch updates from the database
    my @rows = $self->{dbh}->selectall_array(
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

1;
