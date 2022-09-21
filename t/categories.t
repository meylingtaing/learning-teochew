use strict;
use warnings;

use Test::More;
use Test::Deep;
require_ok 'Teochew';

is Teochew::flashcard_set_name(), 'All',
    'flashcard_set_name with no args returns "All"';
is Teochew::flashcard_set_name('food'), 'Food/Drink',
    'flashcard_set_name for food is "Food/Drink"';
is Teochew::flashcard_set_name('number', 20), 'Numbers (up to 20)',
    'flashcard_set_name can take extra arg for number';
is Teochew::flashcard_set_name('nature'), 'Nature',
    'flashcard_set_name is just capitalized word if we did not define it';

done_testing;
