use strict;
use warnings;

use utf8;

use Test::More;
use Test::Deep qw(cmp_bag);
use Data::Dumper;

require_ok 'Teochew';

is Teochew::_standard_pronunciation(chinese => '银', pengim => 'ngeng5'), 'nging5',
    'ngeng5 has nging5 standard pronunciation';

is Teochew::_standard_pronunciation(
    chinese => '礼拜日',
    pengim => 'loi26 bai32 yek8'
), 'loi26 bai32 yik8',
    'loi26 bai32 yek8 has standard pronunciation loi26 bai32 yik8';

is Teochew::_standard_pronunciation(chinese => '妈', pengim => 'ma1'), undef,
    'ma1 is same for both gekion and standard teochew';

done_testing;
