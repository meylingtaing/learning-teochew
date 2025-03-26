use utf8;
use Test::Mojo;
use Test::More;

my $t = Test::Mojo->new('App');

# Hide the extra debug messages because they're kind of noisy
$t->app->log->level('info');

# Load a page for a character that exists - gio5
$t->get_ok("/chinese/茄")->status_is(200);

$t->text_like('h1#main-chinese-character', qr/茄/, "Showing the page for 茄");
$t->text_like('h2#main-pengim-with-audio', qr/gio5\s+\|\s+gia1/,
    "Both gio5 and gia1 pronunciations are shown");

# eggplant, tomato, purple
$t->element_exists('table#words-containing-chinese-character',
    "Table with words containing this character is shown");
$t->element_count_is('table#words-containing-chinese-character > tbody > tr',
    3, "Showing three words that contain this character");

# Now let's load the page for a character we don't have
$t->get_ok("/chinese/你")->status_is(200);

$t->element_exists_not('h1#main-chinese-character',
    "The Chinese character header is not shown");
$t->element_exists_not('h2#main-pengim-with-audio',
    "The pronunciation header is not shown");

$t->content_like(qr/Sorry! I don't have the character 你 in my database!/,
    "Error message is shown when searching a character that doesn't exist");

# XXX Something with Alternates
# XXX Something with traditional and simplified

done_testing;
