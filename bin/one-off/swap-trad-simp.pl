#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

# These are required to print non-ascii characters to STDOUT or
# read them in @ARGV
binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

# We almost certainly want access to these
use lib 'lib';
use Teochew;
use Teochew::Edit;

# need to explicitly include exported functions
use Teochew::Utils qw();
use Input qw(confirm input_from_prompt input_via_editor);

use Data::Dumper;
use Term::ANSIColor qw(colored);

my $db = Teochew::Edit->new;
my @rows = $db->dbh->selectall_array(qq{
    select id, simplified, traditional
    from Chinese
    order by id
}, { Slice => {} });

my $max = undef;
my $i = 0;

for my $row (@rows) {
    $i++;

    my $traditional = $row->{traditional};
    my $simplified  = $row->{simplified};

    # If traditional is empty, swap the simplified value for it
    if (!defined $traditional) {
        $db->dbh->do(qq{
            update Chinese set simplified = NULL, traditional = ?
            where id = ?
        }, undef, $simplified, $row->{id});
        #warn "Row $row->{id}: Swapped traditional and simplified\n";
    }

    # If there's already a traditional value, do a search and replace in the
    # Teochew table to use the traditional value rather than simplified
    else {
        my @teochew_rows = $db->dbh->selectall_array(qq{
            select id, chinese from teochew
            where chinese like ?
        }, { Slice => {} }, "%$simplified%");

        for my $teochew (@teochew_rows) {
            my $chinese = $teochew->{chinese};
            $chinese =~ s/$simplified/$traditional/g;

            $db->dbh->do(qq{
                update Teochew set chinese = ? where id = ?
            }, undef, $chinese, $teochew->{id});
        }
        #warn "Swapped $simplified with $traditional in Teochew rows\n";
    }

    last if $max && $i >= $max;
}
