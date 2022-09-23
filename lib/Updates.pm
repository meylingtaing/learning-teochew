package Updates;

use strict;
use warnings;

use Date::Format;
use Date::Parse;

=head1 NAME

Updates

=head1 DESCRIPTION

A class for handling operations on the Updates database

=cut

use parent 'SqliteDB';
use DBI qw(:sql_types);

sub new { shift->create_db_object('Updates.sqlite') }

=head1 METHODS

=head2 get_updates

Gets the updates from the database

=cut

sub get_updates {
    my ($self, $page) = @_;
    $page ||= 0;

    # Fetch updates from the database
    my @rows = $self->dbh->selectall_array(
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
