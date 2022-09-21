package Teochew;

use strict;
use warnings;

use utf8;
use DBI qw(:sql_types);
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);
use POSIX;
use List::Util qw(shuffle);
use Data::Dumper;
use Set::CrossProduct;

use Teochew::Utils qw(
    add_tone_marks
    change_tone
    link_teochew_words
    split_out_parens
);

=head1 NAME

Teochew

=cut

=head1 DESCRIPTION

Class for accessing the Teochew database

=cut

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

# Get a cache of the alternates pronunciations because it's small and we don't
# want to keep hitting the database over and over
my %alt_pengim = map { $_->[0] => $_->[1] } @{
    $dbh->selectall_arrayref(qq{
        select
            Pengim.full pengim,
            PengimAlt.full alt
        from Pengim join PengimAlt on Pengim.id = pengim_id
    })
};

# XXX Make this configurable eventually
my $preferred_accent = 'alt';

=head1 DATA

=head2 English Words

There are many English words in the database that can be translated into
Teochew. Some English words have an additional note to signify that there are
multiple ways to translate the word, but they all have different meanings in
Chinese.

=head2 Categories

Each English word is grouped into one of several different categories, such as
Numbers, Family, and Food/Drink. Each category has a name and a display name.

    { name => 'food', display_name => 'Food/Drink' }

=head2 Flashcard Sets

There are a number of default "flashcard sets" in the database, each of which
contains one or more categories.

=head2 Translations

Each English word is also linked to a Teochew translation. Each translation
consists of Peng'im (the transliteration), the chinese characters, and an
audio file if one was recorded. Below is the translation for the word 'hello'.

    { pengim => 'leu2 ho2', chinese => '汝好', audio => 'leu2ho2' }

=head1 FLASHCARD/CATEGORY FUNCTIONS

=head2 flashcard_set_name

    $display = Teochew::flashcard_set_name;               # 'All'
    $display = Teochew::flashcard_set_name('food');       # 'Food/Drink'
    $display = Teochew::flashcard_set_name('number', 20); # 'Numbers (up to 20)'

Given a category name, this returns its display name. If the category name is
'number', you can optionally provide a second argument C<$num> to tack on
" (up to $num)". If no arguments are provided, then this will return 'All'.
This returns C<undef> if the category is not recognized.

=cut

sub flashcard_set_name {
    my ($type, $subtype) = @_;
    $type ||= '';

    # Numbers are special
    if ($type eq 'number') {
        my $name = 'Numbers';
        $name .= " (up to $subtype)" if $subtype;
        return $name;
    }

    # Everything else is a simple lookup in the database
    my @rows = $dbh->selectall_array(qq{
        select display_name from FlashcardSet where name = ? collate nocase
    }, {}, $type);

    return scalar @rows ? $rows[0]->[0] : ucfirst $type;
}

=head2 flashcard_sets

    @categories = Teochew::flashcard_sets();

Returns the list of "word" L</Categories> that are available in the database.

=cut

sub flashcard_sets {
    my @rows = $dbh->selectall_array(qq{
        select lower(name) as name, display_name from FlashcardSet
        where hidden = 0
        order by sort
    }, { Slice => {} });

    return @rows;
}

=head2 flashcard_set_categories

Given a flashcard set name, this will return a list of all the categories
within that set, in this form:

    { name => 'datetime', display_name => 'Date/Time' },
    { name => 'months',   display_name => 'Months' },
    { name => 'weekdays', display_name => 'Days of the Week' }

=cut

sub flashcard_set_categories {
    my ($flashcard_set, $subcategory) = @_;

    # XXX Number is a special case for some reason
    return { name => $flashcard_set, display_name => flashcard_set_name(@_) }
        if $flashcard_set eq 'number';

    my @rows = $dbh->selectall_array(qq{
        select
            lower(categories.name) as name,
            coalesce(categories.display_name, categories.name) as display_name
        from Categories
        join FlashcardSet on FlashcardSet.id = flashcardset_id
        where FlashcardSet.name = ? collate nocase
    }, { Slice => {} }, $flashcard_set);

    return @rows;
}

=head1 TRANSLATE FUNCTIONS

=cut

=head2 translate

    translate('money')
    translate('money', show_all_accents => 1)

Given any english word, returns the translations. Here is the output for the
example given, using C<show_all_accents>:

    [{
        chinese => '银',
        notes   => 'silver, coins',
        pronunciations => [
            { pengim => 'ngeng5', audio => 'ngeng5.mp3' },
            { pengim => 'nging5', audio => 'nging5.mp3' },
        ],
        category => {
            name => 'shopping',
            display => 'Shopping',
            flashcard_set => 'misc',
        },
    }, {
        chinese => '钱',
        notes   => undef,
        pronunciations => [{ pengim => 'jin5', audio => 'jin5.mp3' }],
        category => { name => 'shopping', display => 'Shopping' },
    }, {
        chinese => '镭',
        notes   => undef,
        pronunciations => [{ pengim => 'lui1', audio => 'lui1.mp3' }],
        category => { name => 'shopping', display => 'Shopping' },
    }]

If C<show_all_accents> is not given, each element's C<pronunciation> will only
have one value.

This is used for the English page, and also for the Flashcards and multi
translation tables.

=cut

sub translate {
    my ($english, %params) = @_;
    my $show_all_accents = $params{show_all_accents};

    my @translations;

    # Hash reference means we get the id and the word passed in
    # XXX When is this used?
    if (ref $english eq 'HASH') {
        if ($english->{sentence}) {
            @translations = (_translate_phrase($english));
        }
        else {
            @translations = get_all_translations_by_id($english->{id});
        }
    }
    # If not, then we're getting a string to translate
    # This is what gets used when we're on an English page
    else {
        $english = lc $english;

        if ($english =~ /^\d+$/) {
            @translations = ( translate_number($english) );
        }
        elsif ($english =~ /^\d+:\d+$/) {
            @translations = ( translate_time($english) );
        }
        else {
            @translations = get_all_translations($english,
                not_hidden => 1, include_alternates => 1);
        }
    }

    my @ret;
    for (@translations) {
        $_->{pengim} =~ s/\d(\d)/($1)/g;
        my $pronunciation = [{
            pengim => $_->{pengim}, audio => find_audio($_->{pengim})
        }];

        # It's possible that I recorded multiple versions of this word, with
        # different accents. If I have multiple accents recorded, include them
        my $alt = _alternate_pronunciation($_->{pengim});
        if ($alt) {
            my $audio = find_audio($alt);

            # Whooooo this is hacky
            my $new_pronunciation = { pengim => $alt, audio => $audio };
            if ($preferred_accent eq 'alt') {
                unshift @$pronunciation, $new_pronunciation;
            }
            else {
                push @$pronunciation, $new_pronunciation;
            }
        }

        $pronunciation = [$pronunciation->[0]] unless $show_all_accents;

        push @ret, {
            chinese        => $_->{chinese} =~ s/\?/[?]/gr,
            pronunciations => $pronunciation,
            notes          => $_->{notes},
            category       => {
                name    => $_->{category_name},
                display => $_->{category_display},
                flashcard_set => $_->{flashcard_set_name},
            },
        }
    }

    return \@ret;
}

=head2 generate_full_translations

Given some parameters, this will return a list of english words with
translations, each as a hashref of this form:

    {
        english => 'hello',
        notes   => 'extra things that matter in chinese but not english',
        teochew => [
            [{ pengim => 'leu2 ho2', chinese => $characters, audio => leu2ho2 }],
            [{ pengim => 'alter', chinese => $character2 }]
        ]
    }

Parameters:

    category    => Str,  the name of the category
    subcategory => Str,  the name of the subcategory
    shuffle     => Bool, set to true if you want random order
    count       => Int,  number of translations to return, default all

=cut

sub generate_full_translations {
    my %params = @_;

    my $type     = $params{flashcard_set} || '';
    my $subtype  = $params{subcategory};  # only used for numbers right now
    my $category = $params{category};
    my $count    = $params{count};

    my @english_list;

    ## 1. Get a list of english words to use in the flashcards

    # If we don't specify a type, just assume we want to pick from the english
    # words in the database
    push @english_list,
        $type eq 'number' ? (0..$subtype) :
        $type eq 'time'   ? _generate_english_times() :
        $type eq 'phrase' ? _generate_english_phrases($subtype) :
                            generate_english_from_database(
                                flashcard_set => $type,
                                category      => $category);

    @english_list = shuffle @english_list
        if $params{shuffle};

    @english_list = @english_list[0 .. $count-1]
        if $count and scalar @english_list > $count;

    ## 2. Translate all the english words and put the flashcards together
    my @flashcards;
    for my $english (@english_list) {

        my %flashcard = ( teochew => translate($english) );

        if (ref $english eq 'HASH') {
            $flashcard{english} = $english->{word} || $english->{sentence};
            $flashcard{notes}   = $english->{notes};
        }
        else {
            $flashcard{english} = $english;
            $flashcard{notes}   = undef;
        }

        push @flashcards, \%flashcard;
    }

    return @flashcards;
}


=head2 generate_flashcard

Returns a random english word and teochew translation in a hashref. You can
optionally provide a category name to limit the bank of words chosen to a
single category.

This is just a helper to call L</generate_full_translations> with random
words selected.

=cut

sub generate_flashcards {
    my ($type, $subtype) = @_;
    my @flashcards;

    # If we have a specific type of flashcard that we want, just get those
    if ($type) {
        @flashcards = generate_full_translations(
            flashcard_set => $type,
            subcategory   => $subtype,
            shuffle       => 1,
            count         => 20,
        );
    }

    # Else just grab a random set of words from the database
    else {
        my @other = generate_full_translations(
            shuffle => 1,
            count   => 20,
        );

        @flashcards = shuffle(@other);
    }

    return \@flashcards;
}

=head1 MISC DATA RETRIEVAL FUNCTIONS

=head2 generate_english_from_database

Returns a list of english words and their ids from the database in the
form of

    { word => 'hello', id => 1 }

You can optionally provide a category to limit the types of words that can be
generated.

=cut

sub generate_english_from_database {
    my (%params) = @_;

    my $flashcard_set = $params{flashcard_set};
    my $category      = $params{category};

    my @binds;
    my $category_condition = '';

    if ($flashcard_set) {
        $category_condition .= "and FlashcardSet.name = ? ";
        push @binds, ucfirst $flashcard_set;
    }
    if ($category) {
        $category_condition .= "and Categories.name = ? ";
        push @binds, ucfirst $category;
    }

    my $sql = qq{
        select English.id, word, notes from English
        join Categories on Categories.id = category_id
        join FlashcardSet on FlashcardSet.id = flashcardset_id
        where English.hidden = 0 and hidden_from_flashcards = 0
        $category_condition
        order by english.sort, word collate nocase
    };

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);
    return @rows;
}

=head1 INTERNALS

These functions are not typically meant to be called outside of this file, but
they're documented if you want to.

=head2 _dialect_characters

Given the romanization of a dialect, this will return the Chinese characters
for it. The list of dialects it understands is

    diojiu
    gekion

=cut

sub _dialect_characters {
    my ($given_dialect) = @_;

    return undef unless $given_dialect;

    my %characters = ( diojiu => '潮州', gekion => '揭阳' );
    return $characters{$given_dialect};
}

=head2 _generate_english_in_subcategory

Returns a random English word in a given SubCategory.

=cut

sub _generate_english_in_subcategory {
    my ($subcategory, $setting) = @_;
    my $sql = qq{
        select English.word from SubCategories
        join CategoryLinks on subcategory_id = SubCategories.id
        join English on english_id = English.id
        where name = ?
    };

    my @rows = $dbh->selectall_array($sql, {}, $subcategory);
    @rows = shuffle @rows;

    if (($setting || '') eq 'all') {
        return map { $_->[0] } @rows;
    }
    else {
        return $rows[0]->[0];
    }
}

=head2 _generate_english_phrases

Returns a list of random english sentences in the form of

    { sentence => 'I know', words => 'I to_know' }

=cut

sub _generate_english_phrases {
    my $setting = shift;

    my $sql  = "select sentence, words from Phrases where hidden = 0";
    my @rows = $dbh->selectall_array($sql, { Slice => {} });

    if (($setting || '') eq 'all') {
        my @ret;
        for (@rows) {
            push @ret, replace_variables_all($_);
        }
        return @ret;
    }
    else {
        # Replace variables
        replace_variables($_) for @rows;
        return @rows;
    }

}

=head2 _generate_english_times

Returns the possible list of times

=cut

sub _generate_english_times {

    my @possibilities = (0..143);
    my @times;
    for (@possibilities) {
        my $hour = floor($_ / 12) + 1;
        my $min  = ($_ % 12) * 5;
        my $english = sprintf "%d:%02d", $hour, $min;

        push @times, $english;
    }

    return @times;
}

=head2 get_synonyms

Given an English word, returns the synonyms for that word

=cut

sub get_synonyms {
    my ($word) = @_;
    my $sql =
        'select Synonyms.word as word ' .
        'from Synonyms join English on English.id = english_id ' .
        'where English.word = ?';

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, $word);
    return map { $_->{word} } @rows;
}

=head2 get_tags

Given an English word, returns the tags for that word

=cut

sub get_tags {
    my ($word) = @_;
    my $sql =
        "select Tags.name from Tags " .
        "join TagLinks on Tags.id = TagLinks.tag_id " .
        "join English on English.id = TagLinks.english_id " .
        "where English.word = ?";

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, $word);
    return map { $_->{name} } @rows;
}

=head2 _translate_phrase

Translates a phrase. Expects a hashref in the form of

    { sentence => 'I'm going to the store', words => 'I to_go store' }

=cut

sub _translate_phrase {
    my ($english) = @_;
    # Split up each word into components
    my @words = split / /, $english->{words};
    my @components;

    for my $word (@words) {

        my $no_tone_change = $word =~ s/\|$//g ? 1 : 0;

        my $pengim = undef;
        if ($word =~ /\-(.*)$/) {
            $pengim = $1;
            $word =~ s/\-(.*)$//;
        }

        $word =~ s/_/ /g;

        my $translation;
        if ($word =~ /\d+/) {
            ($translation) = translate_number($word);
        }
        else {
            $translation = lookup($word, pengim => $pengim);
        }
        $translation->{no_tone_change} ||= $no_tone_change;
        push @components, $translation;
    }

    # "..." indicates that it's an incomplete sentence so we need
    # to make sure all the words go through tone change
    my $incomplete = $english->{sentence} =~ /\.\.\.$/;

    # No tone change for words that come before tag questions
    if ($english->{sentence} =~ /\?$/ and
        $components[-1]->{tag_question})
    {
        $components[-2]->{no_tone_change} = 1;
    }

    return link_teochew_words(
        \@components, { tone_change_last_word => $incomplete }
    );
}

sub _order_by_gekion_first {
    "order by case " .
    "   when dialect is null then 1 " .
    "   when dialect = 'gekion' then 2 else 3 end";
}

# XXX Change this to not use cross product...just have one alternate, it's
# a lot easier that way
sub _alternate_pronunciation {
    my ($pengim) = @_;
    my $has_alt = 0;

    # Break apart the string into multiple words, and then keep a list of the
    # tone numbers--they aren't relevant for this, but we need to tack them
    # back on at the end
    my @words = split /\s+/, $pengim;
    my @tones;

    my %variations;

    my @new_words;

    for (my $i = 0; $i <= $#words; $i++) {
        $words[$i] =~ /([a-z]+)(\(?\d\)?)/;
        my $base_word = $words[$i] = $1;
        push @tones, $2;
        my $tone = $2;
        if (my $alt = $alt_pengim{$base_word}) {
            #$variations{$i} = [$base_word, $alt];
            push @new_words, $alt . $tone;
            $has_alt = 1;
        }
        else {
            push @new_words, $base_word . $tone;
        }
    }

    return undef unless $has_alt;
    return join ' ', @new_words;

    ## If there's only one word with alternates, we need this fake key in
    ## order for CrossProduct to work
    #my $combinations = Set::CrossProduct->new({
    #    fake_key => ['1'],
    #    %variations
    #});

    ## Form the list of strings
    #my @ret;
    #while (my $combo = $combinations->get) {
    #    my @alt_words;
    #    for (my $i = 0; $i <= $#words; $i++) {
    #        my $new_word = $combo->{$i} // $words[$i];
    #        push @alt_words, $new_word . $tones[$i];
    #    }
    #    my $alt_pronunciation = join(' ', @alt_words);
    #    next if $alt_pronunciation eq $pengim;
    #    push @ret, $alt_pronunciation;
    #}

    #return @ret;
}

=head1 MISCELLANEOUS FUNCTIONS

=head2 replace_variables

    Teochew::replace_variables({
        sentence => 'I am going to the $place',
        words    => 'I to_go $place'
    });

Given a hashref with C<sentence> and C<word>, this replaces any variables with
words in the SubCategories.

=cut

sub replace_variables {
    my ($row) = @_;
    my $sentence = $row->{sentence};
    my $words    = $row->{words};

    my @variables = grep { substr($_, 0, 1) eq '$' }
                    split / /, $sentence;

    return $row unless scalar @variables;

    for my $var (@variables) {
        my $variable_str = substr($var, 1);
        my $word = _generate_english_in_subcategory($variable_str);

        $sentence =~ s/\$$variable_str/$word/;
        $words    =~ s/\$$variable_str/$word/;
    }

    $row->{sentence} = $sentence;
    $row->{words}    = $words;

    return $row;
}

=head2 replace_variables_all

Similar to L</replace_variables>, but this returns all of the possible
combinations instead of just picking words at random for each sentence.

=cut

sub replace_variables_all {
    my ($row, $setting) = @_;

    my $sentence = $row->{sentence};
    my $words    = $row->{words};

    my @variables = grep { substr($_, 0, 1) eq '$' }
                    split / /, $sentence;

    return $row unless scalar @variables;

    my %var_sets;
    for my $var (@variables) {
        my $variable_str = substr($var, 1);
        my @words = _generate_english_in_subcategory($variable_str, 'all');
        $var_sets{$variable_str} = \@words;
    }

    my $combinations = Set::CrossProduct->new({
        # XXX: Maybe notify of an issue?
        # this is dumb, but Set::CrossProduct requires multiple keys
        fake_key => ['1'],

        %var_sets
    });
    my @new_rows;
    while (my $combo = $combinations->get) {
        my %new_row = %$row;
        while (my ($var, $word) = each %$combo) {
            $new_row{sentence} =~ s/\$$var/$word/;
            $new_row{words}    =~ s/\$$var/$word/;
        }
        push @new_rows, \%new_row;
    }

    return @new_rows;
}

=head2 translate_number

Given a number from 0-999, returns the translation

=cut

sub translate_number {
    my $number = shift;
    return if $number > 1000;

    my $hundreds_digit = floor($number / 100);
    my $tens_digit     = ($number / 10) % 10;
    my $ones_digit     = $number % 10;

    my @components;

    # Simple lookup for numbers less than 10
    if ($number <= 10 || $number == 1000) {
        return get_all_translations($number);
    }

    # Hundreds digit
    if ($hundreds_digit >= 1) {
        push @components, lookup($hundreds_digit);
        push @components, lookup(100);

        # 100, 200, 300, etc
        if ($tens_digit == 0 and $ones_digit == 0) {
            return link_teochew_words(\@components);
        }

        # Can ignore ones digit if it's 0
        if ($ones_digit == 0) {
            if ($tens_digit == 1 or $tens_digit == 2) {
                push @components, lookup("$tens_digit (alt)");
                return link_teochew_words(\@components);
            }
            else {
                push @components, lookup($tens_digit);
                return link_teochew_words(\@components);
            }
        }

        # Need to say "zero" if it's in the middle
        if ($tens_digit == 0) {
            push @components, lookup(0);
        }
    }

    # Tens Digit
    if ($tens_digit >= 1) {
        if ($tens_digit == 2) {
            push @components, lookup("2 (alt)");
        }
        elsif ($tens_digit > 2) {
            push @components, lookup($tens_digit);
        }

        # "Ten"
        push @components, lookup(10);
        if ($ones_digit == 0) {
            return link_teochew_words(\@components);
        }
    }

    # Ones Digit
    $ones_digit .= " (alt)" if $ones_digit == 1 || $ones_digit == 2;
    push @components, lookup($ones_digit);

    return link_teochew_words(\@components);
}

=head2 translate_time

Given a time, returns the translation

=cut

sub translate_time {
    my $time = shift;
    my ($hour, $minute) = split /:/, $time;

    my @components;

    push @components, lookup($hour);
    push @components, lookup('time (hour)');

    if ($minute eq '00') {
        return link_teochew_words(\@components);
    }

    if ($minute eq '30') {
        push @components, lookup('time (30 min)');
    }
    elsif ($minute % 5 == 0) {
        my $minute_hand = $minute / 5;
        $minute_hand .= " (alt)" if $minute_hand == 1 || $minute_hand == 2;

        push @components, lookup('time (5 min)');
        push @components, lookup($minute_hand);
    }
    else {
        # XXX: implement this part
    }

    return link_teochew_words(\@components);
}

=head1 DATABASE/FILESYSTEM FUNCTIONS

=head2 lookup

Returns the first translation found for the english word given.

=cut

sub lookup {
    my ($english, %params) = @_;

    my ($row) = get_all_translations($english, %params);
    die "Translation for \"$english\" doesn't exist!\n" unless $row;
    return $row;
}

=head2 get_all_translations

This takes these parameters:

    include_alternates => Bool, enable if we can include partial matches
    not_hidden         => Bool, enable if we should ignore hidden words
    pengim             => Str, set if we want a certain pengim first

Returns all the translations in an arrayref for the english word given. Each
arrayref contains a hashref with these fields:

    pengim
    chinese
    word (English)
    notes
    no_tone_change
    tag_question
    info
    dialect
    category
    category_display
    flashcard_set_name

=cut

sub get_all_translations {
    my ($english, %params) = @_;

    my ($word, $notes) = split_out_parens($english);
    my @binds = ($word);
    $params{notes} = $notes if $notes;

    my $cond;
    if ($params{include_alternates}) {
        $cond =
            "(English.word = ? collate nocase or " .
            "English.word like ? collate nocase)";
        push @binds, "$word (%";
    }
    else {
        $cond = "English.word = ? collate nocase"
    }

    $cond .= " and English.hidden = 0" if $params{not_hidden};

    if ($params{notes}) {
        $cond .= " and notes like ?";
        push @binds, "%$params{notes}%";
    }

    my $sql = qq{
        select
            English.word as english, notes,
            pengim, chinese,
            no_tone_change, tag_question, info, dialect,
            lower(Categories.name) as category_name,
            coalesce(Categories.display_name, Categories.name)
                as category_display,
            lower(FlashcardSet.name) as flashcard_set_name
        from Teochew join English on English.id = Teochew.english_id
        join Categories on English.category_id = Categories.id
        left join FlashcardSet on Categories.flashcardset_id = FlashcardSet.id
        left join Extra on English.id = Extra.english_id
        where $cond
    } . _order_by_gekion_first();

    if ($params{pengim}) {
        $sql .= ", pengim = ? desc";
        push @binds, $params{pengim};
    }
    elsif (!$params{notes}) {
        $sql .= ", notes";
    }

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);

    return @rows;
}

=head2 extra_information

Gets extra information about an english word if it exists

=cut

sub extra_information {
    my $english = shift;
    my ($word, $notes) = split_out_parens($english);

    my $sql = qq{
        select Extra.info from English
        join Extra on English.id = Extra.english_id
        where word = ?
    };

    my @binds = ($word);
    if ($notes) {
        $sql .= " and notes = ?";
        push @binds, $notes;
    }

    my @rows = $dbh->selectall_array($sql, {}, @binds);
    return undef unless scalar @rows;
    return $rows[0]->[0];
}

=head2 search_english_words

Given an string, this checks the database to see if we have any English words
that are similar to it. This returns a list of words with their row ids like
so:

    { word => 'brother' },
    { word => 'sister' },
    { word => 'mother' }

=cut

sub search_english_words {
    my $input = shift;
    my $sql = "select distinct(English.word) from English " .
              "left join Synonyms on English.id = Synonyms.english_id " .
              "where (English.word like ? or notes like ? " .
              "or Synonyms.word like ?) " .
              "and hidden = 0";
    my @rows = $dbh->selectall_array(
        $sql, { Slice => {} }, "%$input%", "%$input%", "%$input%");
    return @rows;
}

=head2 get_all_translations_by_id

Similar to L</get_all_translations>, but you pass in an id instead

Returns rows with

    teochew_id
    pengim
    chinese
    dialect

=cut

sub get_all_translations_by_id {
    my (@english_ids) = @_;

    # XXX: This doesn't handle 0 args correctly
    if (scalar @english_ids == 1) {
        my $sql = qq{
            select id teochew_id, pengim, chinese, dialect
            from Teochew where english_id = ?
        } . _order_by_gekion_first();
        return $dbh->selectall_array($sql, { Slice => {} }, $english_ids[0]);
    }

    # XXX: This is vulnerable to SQL injection!!!
    else {
        my $id_str = join ", ", @english_ids;
        my $sql = qq{
            select id teochew_id, pengim, chinese, dialect from Teochew
            where english_id in ($id_str)
        } . _order_by_gekion_first();

        return $dbh->selectall_array($sql, { Slice => {} });
    }
}

=head2 find_audio

Searches for the audio file corresponding to the given pengim. Returns the name
of the file if found.

=cut

sub find_audio {
    my $pengim = shift;

    # Remove all spaces and parens
    $pengim =~ s/ //g;
    $pengim =~ s/\(|\)//g;

    $pengim .= ".mp3";

    # Figure out the beginning sound
    my $beginning;
    if ($pengim =~ /^(bh|ch|gh|ng)/) {
        $beginning = $1;
    }
    else {
        $beginning = substr $pengim, 0, 1;
    }

    return "$beginning/$pengim" if -r "public/audio/$beginning/$pengim";

    # Sometimes I turn -io or -ia sounds to -ie, and they basically sound the
    # same. So look for -ie as well
    $pengim =~ s/io(n?)(\d)/ie$1$2/g;
    $pengim =~ s/ia(n?)(\d)/ie$1$2/g;

    return "$beginning/$pengim" if -r "public/audio/$beginning/$pengim";

    return undef;
}

=head2 chinese_character_details

=cut

sub chinese_character_details {
    my ($character, $pengim) = @_;

    my $sql = qq{
        select id chinese_id, simplified, traditional, pengim, meaning
        from Chinese where simplified = ?
    };
    my @binds = ($character);

    if ($pengim) {
        $sql .= " and pengim = ?";
        push @binds, $pengim;
    }

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);

    return unless scalar @rows;

    my $chinese = $rows[0];

    for my $chinese (@rows) {
        $chinese->{audio}  = find_audio($chinese->{pengim});
        $chinese->{pengim} = add_tone_marks($chinese->{pengim});

        # XXX: As of now, there will only be one alt per each standard pengim,
        # though that might change in the future
        my $alt = _alternate_pronunciation($chinese->{pengim});
        if ($alt) {
            my $audio = find_audio($alt);
            push @rows, {
                simplified  => $chinese->{simplified},
                traditional => $chinese->{traditional},
                pengim      => add_tone_marks($alt),
                audio       => $audio,
            };
        }
    }

    # hacky
    @rows = reverse @rows if $preferred_accent eq 'alt';

    return \@rows;
}

=head2 find_words_using_character

    find_words_using_character('姑');
    find_words_using_character(['红', '红色'], exclude_itself => 1);

Takes a string of Chinese characters, and returns an arrayref of english words
that include that string. You can optionally pass in C<exclude_itself> to only
include results that are longer than the given string.

The first argument can either be a string, or an arrayref of strings. If
multiple strings are given, this will find all words that include any of the
given strings.

Each element in the return arrayref is a hashref with these values:

    english
    notes
    teochew => {
        chinese => '',
        pronunciations => [{
            pengim  => '',
            audio   => '',
        }]
    }

=cut

sub find_words_using_character {
    my ($characters, %params) = @_;
    my $exclude_itself = $params{exclude_itself};

    $characters = [$characters] unless ref $characters eq 'ARRAY';

    my $sql =
        "select English.word as english, notes, chinese, pengim from Teochew " .
        "join English on English.id = english_id " .
        "where hidden = 0 and (dialect is null or dialect != 'diojiu')";

    my @binds = map { "%$_%" } @$characters;
    my $chinese_like_sql = join " or ", ("chinese like ?") x scalar @$characters;
    $sql .= " and ($chinese_like_sql)";

    if ($exclude_itself) {
        $sql .= " and chinese != ?" for @$characters;
        push @binds, @$characters;
    }

    # Show the words that contain _just_ the character first
    if (scalar @$characters == 1) {
        $sql .= " order by case when chinese = ? then 1 else 2 end";
        push @binds, $characters->[0];
    }

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);

    my @ret;
    for (@rows) {

        my $pengim = $_->{pengim};
        $pengim =~ s/\d(\d)/($1)/g;
        my $audio;
        if ($preferred_accent eq 'alt') {
            my $alt = _alternate_pronunciation($_->{pengim});
            if ($alt) {
                $audio  = find_audio($alt);
                $pengim = $alt if $audio;
            }
        }
        $audio ||= find_audio($pengim);

        push @ret, {
            english => $_->{english},
            notes   => $_->{notes},
            teochew => [{
                chinese => $_->{chinese},
                pronunciations => [{
                    pengim  => $pengim,
                    audio   => $audio,
                }]
            }]
        }
    }

    return \@ret;
}

# TODO
#sub find_phrases_using_word {
#}

=head1 OTHER HELPERS

=head2 finalize_output

Given a teochew translation, this will add tone marks and look up the audio
if it exists. This is a helper for getting the data to look nice before
displaying it to the user.

=cut

sub finalize_output {
    return map {{
        pengim  => add_tone_marks($_->{pengim}),
        chinese => $_->{chinese} =~ s/\?/[?]/gr,
        audio   => find_audio($_->{pengim}),
        notes   => $_->{notes},
        dialect => _dialect_characters($_->{dialect}),
    }} @_;
}
