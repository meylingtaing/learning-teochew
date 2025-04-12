use strict;
use warnings;

use open ':std', ':encoding(utf8)';
use Test::More;

require_ok 'Teochew::Utils';

use Teochew::Utils qw(change_tone split_out_parens);

sub check_tone_change {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($original, $changed) = @_;
    is change_tone($original), $changed,
        "change_tone: $original -> $changed";
}

check_tone_change("jap8", "jap(4)");
check_tone_change("hung6 ang5", "hung6 ang(7)");
check_tone_change("san1", "san1");
check_tone_change("boih4", "boih(8)");
check_tone_change("no6", "no(7)");

is change_tone("no6", parens => 1), "no(7)",
    "change_tone works with parens => 1";
is change_tone("no6", parens => 0), "no67",
    "change_tone works with parens => 0";

my ($main, $in_parens) = split_out_parens("foo");
is $main, "foo", "split_out_parens: No parens has no effect on main word";
is $in_parens, "", "split_out_parens: No parens has no in_parens word";

($main, $in_parens) = split_out_parens("we (inclusive)");
is $main, "we", "split_out_parens: Can pull out main word";
is $in_parens, "inclusive", "split_out_parens: Can pull out word in parens";

done_testing;
