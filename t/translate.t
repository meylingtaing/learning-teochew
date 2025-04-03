use strict;
use warnings;

use open ':std', ':encoding(utf8)';
use Test::More;

require_ok 'Teochew';

sub check_translation {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($english, $teochew) = @_;
    my $translation = Teochew::translate($english);

    $english = $english->{sentence} if ref $english && $english->{sentence};
    is $translation->[0]{pronunciations}[0]{pengim}, $teochew,
        "translation: $english -> $teochew";
}

check_translation(2,  "no6");
check_translation(12, "jap(4) yi6");
check_translation(10, "jap8");
check_translation(19, "jap(4) gao2");
check_translation(20, "yi(7) jap8");
check_translation(21, "yi(7) jap(4) ek4");

check_translation(100, "jek(4) beh4");
check_translation(101, "jek(4) beh(8) kang(2) ek4");
check_translation(102, "jek(4) beh(8) kang(2) yi6");
check_translation(110, "jek(4) beh(8) ek4");
check_translation(120, "jek(4) beh(8) yi6");
check_translation(135, "jek(4) beh(8) san1 jap(4) ngou6");

check_translation('12:00', "jap(4) yi(7) diam2");
check_translation('1:00',  "jek(4) diam2");
check_translation('2:00',  "no(7) diam2");
check_translation('3:30',  "san1 diam(6) buan3");
check_translation('10:05', "jap(4) diam(6) dah(8) ek4");
check_translation('10:10', "jap(4) diam(6) dah(8) yi6");
check_translation('10:15', "jap(4) diam(6) dah(8) san1");

# Some English words have multiple translations, and we add extra notes to
# differentiate. Make sure our translate method can handle this
check_translation("aunt (dad's oldest sister)", "dua7 gou1");

# Check translation for a word that has multiple translations
my $translations = Teochew::translate('Red');
is scalar @$translations, 2, "Found two translations for 'Red'";
is_deeply [ map { $_->{pronunciations}[0]{pengim} } @$translations ],
    [ 'ang(7) sek4', 'ang5' ],
    'Translations are correct and non-hidden one is shown first';

check_translation(
    { sentence => 'What are you doing?', words => ['you to_do what'] },
    "leu2 mueh(4) mih(8) gai5"
);

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
