use Test::Mojo;
use Test::More;

my $t = Test::Mojo->new('App');

# Let's check the page for 'hello'
$t->get_ok('/english/hello')->status_is(200);

$t->text_is('h1#english-word', 'hello', "We have a translation for 'hello'");
$t->text_is('p#synonyms', 'hi', "'hi' is listed as a synonym");
$t->element_count_is('li.category-header', 1, "There is a single category");

# Have to use 'like' instead of 'is' because of extra whitespace
$t->text_like('li.category-header a', qr/Common Phrases/,
    "Category is 'Common Phrases'");

$t->element_count_is('div.translation', 1, "There is a single translation");

###########

# Now check the page for 0
$t->get_ok('/english/0')->status_is(200);

$t->text_is('h1#english-word', '0', "We have a translation for '0'");
$t->text_is('p#synonyms', '', 'There are no synonyms');
$t->element_count_is('li.category-header', 1, "There is a single category");
$t->text_like('li.category-header a', qr/Numbers/, "Category is 'Numbers'");

$t->element_count_is('div.translation', 1, "There is a single translation");

done_testing;
