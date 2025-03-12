use utf8;
use Mojo::Base -strict;

use Test::Mojo;
use Test::More;
use URI::Escape;

use lib 'lib';
my $t = Test::Mojo->new('App');

# Hide the extra debug messages because they're kind of noisy
$t->app->log->level('info');

# Index page hits /flashcards
$t->get_ok('/')->status_is(302)->header_is(location => '/flashcards');

my $get = sub {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $t->get_ok(shift)->status_is(200);
};

# Check that flashcard pages load fine
$get->('/flashcards/colors');
$get->('/flashcards/number/20');
$get->('/flashcards/time');
$get->('/flashcards/phrase');

# Unknown category redirects to index
$t->get_ok('/flashcards/fake')
  ->status_is(302)->header_is(location => '/flashcards');

# Check that category pages load
$get->('/category/colors');
$get->('/category/numbers/100');

# Check that you can translate
# XXX: Should probably make sure something actually shows up on the page...
$t->get_ok('/translate?search=hello')
  ->status_is(302)->header_is(location => '/english/hello');
$t->get_ok('/translate?search=' . uri_escape_utf8('汝'))
  ->status_is(302)->header_is(location => '/chinese/' . uri_escape_utf8('汝'));
$t->get_ok('/english/hel')
  ->status_is(302)->header_is(location => '/search?search=hel');

# Check other miscellaneous pages
$get->('/lesson/numbers');
$get->('/updates');
$get->('/updates/2');
$get->('/about');
$get->('/links');

done_testing;
