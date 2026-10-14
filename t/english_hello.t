use utf8;

use Test::Mojo;
use Test::More;

my $t = Test::Mojo->new('App');

$t->app->log->level('info');

$t->get_ok("/english/hello")->status_is(200);

$t->text_is('h1#english-word', "hello", "We have a translation for 'hello'");
$t->text_is('p#synonyms', '', "No top-level synonyms listed");
$t->element_count_is('div.translation', 2, "Got 2 translation(s)");

$t->text_like('#translate-table li:nth-of-type(2) span.chinese', qr/汝好/,
    "Has leuho translation listed first");
$t->text_is('#translate-table li:nth-of-type(2) div.notes', 'hi',
    "'hi' synonym is listed under translation");

$t->text_like('#translate-table li:nth-of-type(3) span.chinese', qr/大家好/,
    "Has daigeho translation listed second");
$t->text_is('#translate-table li:nth-of-type(3) div.notes', 'hello everyone',
    "'hello everyone' note is listed under translation");

$t->get_ok("/english/hi")->status_is(302)->header_is(location => '/english/hello',
    "Searching for 'hi' redirects to 'hello'");

done_testing();
