use strict;
use warnings;

use utf8;

use Test::More;
use Test::Deep qw(cmp_bag);
use Data::Dumper;

require_ok 'Teochew';

# These are nonsense words/phrases that I'm just using to test
is Teochew::_alternate_pronunciation('nging5'), 'ngeng5',
    'nging5 has ngeng1 alternate';

is Teochew::_alternate_pronunciation('ma1 nging5 yik8'),
    'ma1 ngeng5 yek8', 'ma1 nging5 yik8 has alternate ma1 ngeng5 yek8';

is Teochew::_alternate_pronunciation('ma1'), undef,
    'ma1 has no alternate';

done_testing;
