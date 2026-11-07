use strict;
use warnings;

use open ':std', ':encoding(utf8)';
use Test::More;

require_ok 'Teochew';

sub check_translation {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($english, $teochew) = @_;
    my @ret = Teochew::translate_string_of_english_words($english);

    my $sentence = $english->{sentence};
    is $ret[0]{full_translation}{pengim}, $teochew,
        "translation: $sentence -> $teochew";
}

check_translation(
    { sentence => 'What are you doing?', words => ['you to_do what'] },
    "leu2 mueh(4) mih(8) gai5"
);

# We can also include a word in a sentence that would have multiple
# translations
check_translation({
    sentence => "I'll talk to you more tomorrow",
    words    => ['I to_say word_(spoken) with you tomorrow-mua32ki2| more'],
}, "ua2 dan(2) ue7 gah(8) leu2 mua(2) ki2 ge1");

# Make sure we don't tone change when we have the '|'
check_translation({
    sentence => 'Did you eat yet?',
    words    => ['you to_eat done| no_(not_yet)']
}, "leu2 jiah(4) ho2 bhue7");

check_translation({
    sentence => '1, 2, 3',
    words    => ['1| 2| 3']
}, 'jek8 no6 san1');

done_testing;
