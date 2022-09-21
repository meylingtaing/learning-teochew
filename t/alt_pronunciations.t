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

# A full example using the 'translate' function. This is copy pasted directly
# from the documentation for that method.
my %category = (
    category => {
        name => 'shopping',
        display => 'Shopping',
        flashcard_set => 'misc',
    },
);

my $translated_money = 
    [{
        chinese => '银',
        notes   => 'silver, coins',
        %category,
        pronunciations => [
            { pengim => 'ngeng5', audio => 'ng/ngeng5.mp3' },
            #{ pengim => 'nging5', audio => 'ng/nging5.mp3' },
        ]
    }, {
        chinese => '钱',
        notes   => undef,
        %category,
        pronunciations => [{ pengim => 'jin5', audio => 'j/jin5.mp3' }],
    }, {
        chinese => '镭',
        notes   => undef,
        %category,
        pronunciations => [{ pengim => 'lui1', audio => 'l/lui1.mp3' }],
    }];

cmp_bag Teochew::translate('money'), $translated_money,
    "translation for 'money' is correct";

push @{ $translated_money->[0]{pronunciations} },
    { pengim => 'nging5', audio => 'ng/nging5.mp3' };

cmp_bag Teochew::translate('money', show_all_accents => 1), $translated_money,
    "translation for 'money' with all accents is correct";

done_testing;
