use Test::Mojo;
use Test::More;

my $t = Test::Mojo->new('App');

# Hide the extra debug messages because they're kind of noisy
$t->app->log->level('info');

# Each of these tests checks:
#   * status 200
#   * main word that is displayed
#   * synonyms
#   * categories
#   * number of translations

sub check_english_page {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($input, $expected) = @_;

    $t->get_ok("/english/$input")->status_is(200);

    $t->text_is('h1#english-word', $expected->{english_word},
        "We have a translation for '$input'");

    $t->text_is('p#synonyms', $expected->{synonyms},
        "'$expected->{synonyms}' is listed as the synonyms");

    my $num_expected_categories = scalar @{ $expected->{categories} };
    $t->element_count_is('li.category-header',
        $num_expected_categories,
        "Got $num_expected_categories categorie(s)");

    # Have to use 'like' instead of 'is' because of extra whitespace
    for (@{ $expected->{categories} }) {
        $t->text_like('li.category-header a', qr/$_/, "Category is '$_'");
    }

    $t->element_count_is('div.translation', $expected->{num_translations},
        "Got $expected->{num_translations} translation(s)");
}

# Let's check the page for 'hello'
check_english_page('hello', {
    english_word     => 'hello',
    synonyms         => 'hi',
    categories       => ['Common Phrases'],
    num_translations => 1,
});

# 'hi' should be the same, but english word and synonyms are flipped
check_english_page('hi', {
    english_word     => 'hi',
    synonyms         => 'hello',
    categories       => ['Common Phrases'],
    num_translations => 1,
});

# 'bring' should end up pulling up 'to bring'
check_english_page('bring', {
    english_word     => 'to bring',
    synonyms         => 'to take, to get',
    categories       => ['Linking/Transitive Verbs'],
    num_translations => 1,
});

# Now check the page for 0...because it's falsy
check_english_page('0', {
    english_word     => '0',
    synonyms         => '',
    categories       => ['Numbers'],
    num_translations => 1,
});

done_testing;
