package SqliteDB;

use strict;
use warnings;

=head1 NAME

SqliteDB

=head1 DESCRIPTION

Helper class for creating other SQLite database classes. You can set up your
database class like so:

    package MyDBO;
    use parent 'SqliteDB';

    sub new { shift->create_db_object('MyDatabase.sqlite') }

    1;

And then when you instantiate that class, you can use the C<dbh> method to get
a L<DBI> database handle.

    my $my_db = MyDBO->new;
    $my_db->dbh->do("insert into foo (col1, col2) values ('hello', 'world')");

=cut

use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);

sub create_db_object {
    my ($class, $db_file) = @_;

    my $dbh = DBI->connect("DBI:SQLite:dbname=$db_file") or die $DBI::errstr;
    $dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

    my $self = { dbh => $dbh };
    bless $self, $class;
    return $self;
}

sub dbh { shift->{dbh} }

1;
