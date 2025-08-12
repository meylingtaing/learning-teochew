package Teochew;

use strict;
use warnings;

use utf8;
use DBI qw(:sql_types);
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);
use POSIX;
use List::Util qw(shuffle);
use List::MoreUtils qw(uniq);
use Set::CrossProduct;

use Carp;
use Data::Dumper;

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

# XXX Make this configurable eventually
my $preferred_accent = 'gekion';

my %month_numbers = (
    January   => 1,
    February  => 2,
    March     => 3,
    April     => 4,
    May       => 5,
    June      => 6,
    July      => 7,
    August    => 8,
    September => 9,
    October   => 10,
    November  => 11,
    December  => 12,
);

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

    # Everything else is a lookup in the database
    my @flashcardset_rows = $dbh->selectall_array(qq{
        select id, display_name
        from FlashcardSet where name = ?
        collate nocase
    }, { Slice => {} }, $type);

    # Uhhh, I guess if we didn't find anything, just return the type that we
    # were given (because this is how Clock Time works I think?)
    return ucfirst $type if !@flashcardset_rows;

    # If we're given a "subtype" here, that should be a category,
    # so look that up
    if ($subtype) {
        my $display_name = $dbh->selectrow_array(qq{
            select coalesce(display_name, name) from Categories
            where flashcardset_id = ? and name = ?
            collate nocase
        }, undef, $flashcardset_rows[0]{id}, $subtype);

        # If we found the category, great, use that, if not, we'll just default
        # to the full flashcard set
        return $display_name if $display_name;
    }

    return $flashcardset_rows[0]{display_name};
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

=head2 categories

Returns a list of all the categories in this form:

    { id => 1, name => 'Basics' },
    { id => 2, name => 'Colors' }, ...

=cut

sub categories {
    my @rows = $dbh->selectall_array(
        "select id, name from Categories", { Slice => {} }
    );
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
        teochew_id => 1,
        translation_id => 1,
        chinese => {
            traditional  => '银',
            simplified => undef,
        },
        pronunciations => [
            { pengim => 'ngeng5', audio => 'ngeng5.mp3' },
            { pengim => 'nging5', audio => 'nging5.mp3' },
        ],
    }, {
        teochew_id => 1,
        translation_id => 1,
        chinese => {
            traditional  => '钱',
            simplified => undef,
        },
        pronunciations => [{ pengim => 'jin5', audio => 'jin5.mp3' }],
    }, {
        teochew_id => 1,
        translation_id => 1,
        chinese => {
            traditional  => '镭',
            simplified => undef,
        },
        pronunciations => [{ pengim => 'lui1', audio => 'lui1.mp3' }],
    }]

If C<show_all_accents> is not given, each element's C<pronunciation> will only
have one value.

This is used for the English page, and also for the Flashcards and multi
translation tables.

=cut

sub translate {
    my ($english, %params) = @_;

    my $show_all_accents = $params{show_all_accents};
    my $for_flashcards   = $params{for_flashcards};

    my @translations;

    # If the data was passed as a hash, either a "sentence" or "id" should
    # be stored
    if (ref $english eq 'HASH') {
        if ($english->{sentence}) {
            @translations = translate_phrase($english);
        }
        elsif ($english->{id}) {
            @translations = get_all_translations_by_id(
                $english->{id}, for_flashcards => $for_flashcards);
        }
        elsif (defined $english->{word}) {
            my $word = $english->{word};
            if ($word =~ /^\d+$/) {
                @translations = ( translate_number($word) );
            }
            elsif ($word =~ /^\d+:\d+$/) {
                @translations = ( translate_time($word) );
            }
            elsif (_is_date($word)) {
                @translations = ( translate_date($word) );
            }
            else {
                $word = lc $word;

                # If there's stuff in parens, split that out and pass it along
                # as "notes"
                my ($main_word, $notes) = split_out_parens($word);

                ($english) = get_english_from_database(
                    word => $main_word, notes => $notes
                );

                return translate($english) if $english;
            }
        }
        else {
            warn Dumper($english);
            croak "Called `translate` without a valid hash!";
        }
    }
    else {
        return translate({ word => $english }, %params);
    }

    my @ret;
    for (@translations) {
        my $alt = _standard_pronunciation(
            chinese => $_->{traditional},
            pengim  => $_->{pengim}
        );

        $_->{pengim} =~ s/\d(\d)/($1)/g;
        $alt =~ s/\d(\d)/($1)/g if $alt;

        my $pronunciation = [{
            pengim => $_->{pengim}, audio => find_audio($_->{pengim})
        }];

        # It's possible that I recorded multiple versions of this word, with
        # different accents. If I have multiple accents recorded, include them
        if ($alt) {
            my $audio = find_audio($alt);
            my $new_pronunciation = { pengim => $alt, audio => $audio };
            if ($preferred_accent eq 'gekion') {
                push @$pronunciation, $new_pronunciation;
            }
            else {
                unshift @$pronunciation, $new_pronunciation;
            }
        }

        $pronunciation = [$pronunciation->[0]] unless $show_all_accents;

        push @ret, {
            translation_id => $_->{translation_id},
            teochew_id     => $_->{teochew_id},
            chinese        => {
                traditional  => $_->{traditional} =~ s/\?/[?]/gr,
                $_->{simplified} ?
                    (simplified => $_->{simplified} =~ s/\?/[?]/gr) : (),
            },
            pronunciations => $pronunciation,
        }
    }

    return \@ret;
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
        return _lookup($number);
    }

    # Hundreds digit
    if ($hundreds_digit >= 1) {
        push @components, _lookup($hundreds_digit);
        push @components, _lookup(100);

        # 100, 200, 300, etc
        if ($tens_digit == 0 and $ones_digit == 0) {
            return link_teochew_words(\@components);
        }

        # Can ignore ones digit if it's 0
        if ($ones_digit == 0) {
            if ($tens_digit == 1 or $tens_digit == 2) {
                push @components, _lookup("$tens_digit (alt)");
                return link_teochew_words(\@components);
            }
            else {
                push @components, _lookup($tens_digit);
                return link_teochew_words(\@components);
            }
        }

        # Need to say "zero" if it's in the middle
        if ($tens_digit == 0) {
            push @components, _lookup(0);
        }
    }

    # Tens Digit
    if ($tens_digit >= 1) {
        if ($tens_digit == 2) {
            push @components, _lookup("2 (alt)");
        }
        elsif ($tens_digit > 2) {
            push @components, _lookup($tens_digit);
        }

        # "Ten"
        push @components, _lookup(10);
        if ($ones_digit == 0) {
            return link_teochew_words(\@components);
        }
    }

    # Ones Digit
    $ones_digit .= " (alt)" if $ones_digit == 1 || $ones_digit == 2;
    push @components, _lookup($ones_digit);

    return link_teochew_words(\@components);
}

=head2 translate_date

Given a date in the form of "May 23", returns the translation

=cut

sub translate_date {
    my $date = shift;

    my ($month, $day) = split / /, $date;
    my @components;

    # I need to actually split up the month into number + 'month' rather than
    # calling _lookup on the month name directly because months in isolation
    # don't have the number portion sandhi'ed but month in a date does

    my $month_number = $month_numbers{$month};
    die "Invalid month in translate_date!" unless $month_number;

    ## 1. Translate the month portion
    # I also need to make sure we're using the alternate pronunciations of
    # 1 and 2, both in the month and the day portion
    if ($month_number eq '1' || $month_number eq '2') {
        push @components, _lookup("$month_number (alt)");
    }
    else {
        push @components, translate_number($month_number);
    }

    push @components, _lookup('month');

    ## 2. Translate the day portion
    if ($day eq '1' || $day eq '2') {
        push @components, _lookup("$day (alt)");
    }
    else {
        push @components, translate_number($day);
    }

    push @components, _lookup('number');

    return link_teochew_words(\@components);
}

=head2 translate_time

Given a time, returns the translation

=cut

sub translate_time {
    my $time = shift;
    my ($hour, $minute) = split /:/, $time;

    my @components;

    push @components, _lookup($hour);
    push @components, _lookup('time (hour)');

    if ($minute eq '00') {
        return link_teochew_words(\@components);
    }

    if ($minute eq '30') {
        push @components, _lookup('half');
    }
    elsif ($minute % 5 == 0) {
        my $minute_hand = $minute / 5;
        $minute_hand .= " (alt)" if $minute_hand == 1 || $minute_hand == 2;

        push @components, _lookup('time (5 min)');
        push @components, _lookup($minute_hand);
    }
    else {
        # XXX: implement this part
    }

    return link_teochew_words(\@components);
}

=head2 translate_phrase

Translates a phrase. Expects a hashref in the form of

    {
        sentence => 'I'm going to the store',
        words    => ['I| to_go store']
    }

C<words> is an arrayref because we can have multiple translations per sentence

In each of the C<words>, a C<|> character after a word indicates that it should
not undergo tone change (sandhi). It is assumed that all other words (except
the last one in a sentence) will have tone change

This also will never apply sandhi the words 'I' or 'you'

Returns a list of translations, each in the form of

    { pengim => 'ua2 keu32 chi6', chinese => '我去市' }

=cut

sub translate_phrase {
    my ($english) = @_;
    my @return;

    for my $translation_words (@{ $english->{words} }) {

        # Split up each word into components
        my @words = split / /, $translation_words;
        my @components;

        for my $word (@words) {

            my $no_tone_change = $word =~ s/\|$//g ? 1 : 0;

            my $pengim = undef;
            if ($word =~ /\-(.*)$/) {
                $pengim = $1;
                $pengim =~ s/(\d)([a-z])/$1 $2/g;
                $word =~ s/\-(.*)$//;
            }

            $word =~ s/_/ /g;

            my $translation;
            if ($word =~ /\d+/) {
                ($translation) = translate_number($word);
            }
            else {
                $translation = _lookup($word, $pengim);
            }

            $translation->{pengim} =~ s/\d(\d)/($1)/;

            # As far as I know, 'I' and 'you' never undergo tone change, so I'm
            # just hardcoding that rule here
            $translation->{no_tone_change} =
                ($word eq 'I' || $word eq 'you') ? 1 : $no_tone_change;

            push @components, $translation;
        }

        # "..." indicates that it's an incomplete sentence so we need
        # to make sure all the words go through tone change
        my $incomplete = $english->{sentence} =~ /\.\.\.$/;

        push @return, link_teochew_words(
            \@components, { tone_change_last_word => $incomplete }
        );
    }

    return @return;
}

=head2 generate_translation_word_list

Given some parameters, this will return a list of english words with
translations, each as a hashref of this form:

    {
        english_link => 'hello', # in the url
        english      => 'hello', # the display on the page
        notes        => 'extra things that matter in chinese but not english',
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
    for_flashcards => Bool, to filter out hidden_from_flashcards

This is used by the Flashcards and the Category pages.

=cut

sub generate_translation_word_list {
    my %params = @_;

    my $type     = $params{flashcard_set} || '';
    my $subtype  = $params{subcategory};  # only used for numbers right now
    my $category = $params{category};
    my $count    = $params{count};

    my $for_flashcards = $params{for_flashcards};

    my $all_phrases = $for_flashcards ? '' : 'all';

    my @english_list;

    ## 1. Get a list of english words to use in the flashcards

    # If we don't specify a type, just assume we want to pick from the english
    # words in the database
    push @english_list,
        $type eq 'number' ? (0..($subtype||20)) :
        $type eq 'time'   ? _generate_english_times() :
        $type eq 'phrase' ? _generate_english_phrases($all_phrases) :
                            get_english_from_database(
                                flashcard_set  => $type,
                                category       => $category,
                                for_flashcards => $for_flashcards);

    @english_list = shuffle @english_list
        if $params{shuffle};

    @english_list = @english_list[0 .. $count-1]
        if $count and scalar @english_list > $count;

    ## 2. Translate all the english words and put the flashcards together
    my @flashcards;
    for my $english (@english_list) {

        my %flashcard = (
            ref $english eq 'HASH' ? (english_id => $english->{id}) : (),
            teochew => translate($english, for_flashcards => $for_flashcards)
        );

        # why...why is this a HASH sometimes and a string other times
        if (ref $english eq 'HASH') {
            my $base_word = $english->{word};

            # Also check if there are any synonyms we want to show on the
            # flashcard
            if ($for_flashcards && !$english->{notes}) {
                my @synonyms =
                    get_synonyms($base_word, show_on_flashcard => 1);
                if (@synonyms) {
                    # Randomly pick one of the words (between the main word and
                    # the synonyms) to show on the flashcard. Also show the
                    # other synonyms
                    @synonyms = shuffle(@synonyms, $base_word);
                    $english->{word}  = $base_word = shift @synonyms;
                    $english->{notes} = join ", ", @synonyms;
                }
            }

            $flashcard{english_link} = $base_word;
            $flashcard{is_definition} = $english->{is_definition};

            if ($base_word && ($english->{notes} // '') =~ /\b$base_word\b/) {
                $flashcard{english} = $english->{notes};
                $flashcard{notes} = undef;
            }
            else {
                $flashcard{english} = $english->{word} || $english->{sentence};
                $flashcard{notes}   = $english->{notes};
            }
        }
        else {
            $flashcard{english} = $flashcard{english_link} = $english;
            $flashcard{notes}   = undef;
        }

        if ($flashcard{english_link}) {
            $flashcard{english_link} =~ s/\./_/g;
        }

        push @flashcards, \%flashcard;
    }

    return @flashcards;
}


=head2 generate_flashcards

Returns a random english word and teochew translation in a hashref. You can
optionally provide a category name to limit the bank of words chosen to a
single category.

This is just a helper to call L</generate_translation_word_list> with random
words selected.

=cut

sub generate_flashcards {
    my ($type, $subtype) = @_;
    my @flashcards;

    my %params = (shuffle => 1, count => 20, for_flashcards => 1);
    if ($type) {
        $params{flashcard_set} = $type;
        $params{category}      = $subtype;
        $params{subcategory}   = $subtype;
    }

    # If we have a specific type of flashcard that we want, just get those
    # Else just grab a random set of words from the database
    return [generate_translation_word_list(%params)];
}

=head1 MISC DATA RETRIEVAL FUNCTIONS

=head2 get_english_from_database

Returns a list of english words as a hashref like so:

    # These are always included:
    word  => 'hello',
    id    => 1,
    notes => undef,
    is_definition => 0, # for grammar-y things that are more of a description

    # These are included if you provide 'include_category_in_output'
    category_name      => 'basics',
    category_display   => 'Basics',
    category_id        => 1,
    flashcard_set_name => 'Basics',

You can optionally provide a category to limit the types of words that can be
generated.

Params:

    flashcard_set
    category
    for_flashcards
    word
    notes
    include_category_in_output
    check_synonyms
    allow_hidden

=cut

sub get_english_from_database {
    my (%params) = @_;

    my $flashcard_set  = $params{flashcard_set};
    my $category       = $params{category};
    my $word           = $params{word};
    my $notes          = $params{notes};
    my $for_flashcards = $params{for_flashcards};
    my $check_synonyms = $params{check_synonyms};
    my $allow_hidden   = $params{allow_hidden};

    my @synonym_words;

    # First check and see if this is a synonym. If it is, we'll have to adjust
    # our search to use the base English word instead
    if ($check_synonyms) {
        my @rows = $dbh->selectall_array(qq{
            select English.word from English
            join Synonyms on English.id = Synonyms.english_id
            where Synonyms.word = ?
        }, { Slice => {} }, $word);
        @synonym_words = uniq(map { $_->{word} } @rows);
    }

    my @binds;

    my $extra_where = '';

    if ($flashcard_set) {
        $extra_where .= "and FlashcardSet.name = ? ";
        push @binds, ucfirst $flashcard_set;
    }
    if ($category) {
        $extra_where .= "and Categories.name = ? ";
        push @binds, ucfirst $category;
    }
    if (defined $word || @synonym_words) {
        my @placeholders;
        if ($word) {
            push @placeholders, '?';
            push @binds, $word;
        }
        for my $synonym_word (@synonym_words) {
            push @placeholders, '?';
            push @binds, $synonym_word;
        }
        my $placeholder_string = join ',', @placeholders;
        $extra_where .= "and English.word in ($placeholder_string) ";
    }

    if (exists $params{notes}) {
        if (defined $notes && $notes ne '') {
            $extra_where .= "and notes = ? ";
            push @binds, $notes;
        }
        else {
            $extra_where .= "and notes is null ";
        }
    }

    $extra_where .= "and hidden_from_flashcards = 0 " if $for_flashcards;

    my $category_columns = $params{include_category_in_output} ? qq{
        ,
        lower(Categories.name) as category_name,
        coalesce(Categories.display_name, Categories.name)
            as category_display,
        Categories.id as category_id,
        lower(FlashcardSet.name) as flashcard_set_name
    } : '';

    my $hidden_clause = $allow_hidden ? '1=1' : 'English.hidden = 0';

    my $sql = qq{
        select
            English.id, English.word, notes$category_columns,
            case when GrammarDefinitions.id is not null
                then 1
                else 0
            end as is_definition
        from English
        join Categories on Categories.id = category_id
        join FlashcardSet on FlashcardSet.id = flashcardset_id
        join Translation on English.id = Translation.english_id
        left join Synonyms on English.id = Synonyms.english_id
        left join GrammarDefinitions
            on English.id = GrammarDefinitions.english_id
        where
            $hidden_clause
            $extra_where
        group by English.id
        order by
            English.sort,
            English.word,
            case when notes is null or notes = '' then 1 else 2 end
    };

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);
    return @rows;
}

=head2 category_words_by_sort_order

Given a category id, this will return a hashref of words by sort order

=cut

sub category_words_by_sort_order {
    my ($category_id) = @_;

    die "Must pass in a category id to category_words_by_sort_order!\n"
        unless $category_id;

    my $sql = qq{
        select sort, group_concat(distinct word) words from English
        where category_id = ? and hidden = 0
        group by sort order by sort
    };

    return $dbh->selectall_array($sql, { Slice => {} }, $category_id);
}

=head2 get_synonyms

Given an English word, returns the synonyms for that word

=cut

sub get_synonyms {
    my ($word, %params) = @_;

    my $show_on_flashcard = $params{show_on_flashcard};

    my $sql =
        'select Synonyms.word as word ' .
        'from Synonyms join English on English.id = english_id ' .
        'where English.word = ?';

    if ($show_on_flashcard) {
        $sql .= ' and show_on_flashcard = 1';
    }

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, $word);
    return map { $_->{word} } @rows;
}

=head2 get_tags

Given an English id, returns the tags for that word

=cut

sub get_tags {
    my ($id) = @_;
    my $sql =
        "select Tags.name from Tags " .
        "join EnglishTags on Tags.id = EnglishTags.tag_id " .
        "join English on English.id = EnglishTags.english_id " .
        "where English.id = ?";

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, $id);
    return map { $_->{name} } @rows;
}

=head2 check_alternate_chinese

Given a chinese string, this will query the database and see if it either has
alternate forms, or if it is an alternate of another entry. Returns a hashref.

If it has alternates, the hashref will be of this form:

    { has_alts => ['炰', '烳'] }

If it is an alternate of another main entry, the hashref will be of this form:

    { alt_of => '煲' }

=cut

sub check_alternate_chinese {
    my (%params) = @_;

    my $chinese    = $params{chinese} || '';
    my $teochew_id = $params{teochew_id};

    my $where = '';
    my @binds;

    if ($teochew_id) {
        $where = 'Teochew.id = ?';
        @binds = ($teochew_id);
    }
    else {
        $where = 'Teochew.chinese = ? or TeochewAltChinese.chinese = ?';
        @binds = ($chinese, $chinese);
    }

    my $sql = qq{
        select
            Teochew.chinese main, TeochewAltChinese.chinese alt
        from Teochew
        join TeochewAltChinese on Teochew.id = TeochewAltChinese.teochew_id
        where $where
    };

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);
    return {} unless @rows;

    if ($rows[0]{alt} eq $chinese) {
        # XXX: Come back to this...
        return { alt_of => $rows[0]{main} };
    }
    else {
        my @alts;
        for my $row (@rows) {
            my $alt = $row->{alt};
            my $simplified = get_simplified($alt);
            if ($simplified) {
                $alt = "$simplified ($alt)";
            }
            push @alts, $alt;
        }
        return { has_alts => \@alts };
    }
}

=head2 compound_word_components

Given a teochew id, this will return the compound word breakdown (if
applicable), in the form of an array of hashrefs, each containing

    chinese => {
        simplified  => String,
        traditional => String,
    },
    pengim   => String
    word     => String
    notes    => String
    synonyms => String

XXX: I'm not entirely sure if including synonyms in the return is necessary
here, but I don't feel like digging into that now

=cut

sub compound_word_components {
    my ($teochew_id) = @_;

    my $sql = qq{
        select
            Teochew.chinese,
            Teochew.pengim,
            coalesce(English.word, '') word,
            English.notes,
            group_concat(Synonyms.word, ", ") synonyms
        from Compound
        join Translation on Compound.translation_id = Translation.id
        join Teochew on Translation.teochew_id = Teochew.id
        left join English on English.id = Translation.english_id
        left join Synonyms on English.id = Synonyms.english_id
        where parent_teochew_id = ?
        group by Translation.id
        order by Compound.sort
    };

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, $teochew_id);

    for my $row (@rows) {
        # Uhh, this is awkward
        $row->{word} .= ", $row->{synonyms}"
            if $row->{synonyms} &&
               length($row->{word}) + length($row->{synonyms}) < 15;

        # Get the simplified character
        $row->{chinese} = {
            traditional  => $row->{chinese},
            simplified => get_simplified($row->{chinese}),
        };
    }

    return @rows;
}

=head1 INTERNALS

These functions are not typically meant to be called outside of this file, but
they're documented if you want to.

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

    { sentence => 'I know', words => ['I to_know'] }

=cut

sub _generate_english_phrases {
    my $setting = shift;

    my $sql = qq{
        select sentence, PhraseTranslations.words from Phrases
        join PhraseTranslations on Phrases.id = PhraseTranslations.phrase_id
        where hidden = 0
    };
    my @rows = $dbh->selectall_array($sql, { Slice => {} });

    # Hmm, probably want the 'all' setting for the full translation list page
    if (($setting || '') eq 'all') {
        my @replaced_all_variables;
        for (@rows) {
            push @replaced_all_variables, replace_variables_all($_);
        }
        @rows = @replaced_all_variables;
    }
    else {
        # Replace variables
        replace_variables($_) for @rows;
    }

    # There might be multiple translations for a single word. Rather than that
    # showing up as two separate rows in the return value, let's consolidate
    # those
    my %phrases;
    for my $row (@rows) {
        my $sentence = $row->{sentence};
        if (exists $phrases{$sentence}) {
            push @{ $phrases{$sentence} }, $row->{words};
        }
        else {
            $phrases{$sentence} = [$row->{words}];
        }
    }

    return map +{ sentence => $_, words => $phrases{$_} }, sort keys %phrases;
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

=head2 _standard_pronunciation

This takes two params in a hash, C<chinese> and C<pengim>, and checks to see if
the Gekion pronunciation differs from the Teochew proper pronunciation. If it
does, this returns the pengim for the Teochew accent. If not, this returns
undef.

=cut

sub _standard_pronunciation {
    my (%params) = @_;

    my $chinese = $params{chinese};
    my $pengim  = $params{pengim};

    my $has_alt = 0;

    # Break apart the pengim string into each syllable
    my @words = split /\s+/, $pengim;
    my @characters = split //, $chinese;
    my @new_words;

    for (my $i = 0; $i <= $#words; $i++) {

        my $orig_pengim = $words[$i];

        # Check if there's a tone change -- we just want the base tone for
        # looking it up
        my $changed_tone = $words[$i] =~ /\d\d/;
        $words[$i] =~ s/(\d)\d/$1/g;

        my $alt = $dbh->selectrow_array(qq{
            select standard_pengim
            from Chinese
            where traditional = ? and pengim = ?
        }, { Slice => {} }, $characters[$i], $words[$i]);

        if ($alt) {
            $has_alt = 1;
            if ($changed_tone) {
                $alt = change_tone($alt);
            }
            push @new_words, $alt;
        }
        else {
            push @new_words, $orig_pengim;
        }
    }

    return undef unless $has_alt;

    my $standard_pengim = join ' ', @new_words;
    return $standard_pengim;
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


=head1 DATABASE/FILESYSTEM FUNCTIONS

# XXX Move lookup functions to translate
=head2 _lookup

Returns the first translation found for the english word given.

=cut

sub _lookup {
    my ($english) = @_;

    my ($row) = _lookup_all(@_);
    die "Translation for \"$english\" doesn't exist!\n" unless $row;
    return $row;
}

=head2 _lookup_all

    _lookup_all('hello');
    _lookup_all('hello', 'leu2 ho2');

Returns all the translations in an arrayref for the english word given. Each
arrayref contains a hashref with these fields:

    pengim
    chinese
    simplified
    traditional

=cut

sub _lookup_all {
    my ($english, $pengim) = @_;

    my ($word, $notes) = split_out_parens($english);
    my @binds = ($word);

    my $cond = "English.word = ?";

    if ($notes) {
        $cond .= " and notes = ?";
        push @binds, $notes;
    }
    else {
        $cond .= " and (notes is null or notes = '')";
    }

    if ($pengim) {
        $cond .= " and pengim = ?";
        push @binds, $pengim;
    }

    my $sql = qq{
        select pengim, chinese
        from Teochew
        join Translation on Teochew.id = Translation.teochew_id
        join English on English.id = Translation.english_id
        where $cond
    };

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);
    for my $row (@rows) {
        $row->{traditional}  = $row->{chinese};
        $row->{simplified} = get_simplified($row->{chinese});
    }

    return @rows;
}

=head2 extra_information_by_id

Gets extra information about an english word if it exists. This takes a list of
english ids, and it will return a string with all the extra notes that are
attached to those english words

=cut

sub extra_information_by_id {
    my @english_ids = @_;
    my @placeholders = map { '?' } @english_ids;
    my $placeholder_str = join ",", @placeholders;

    # Doing this in two sql statements so I can get the distinct
    # extra_note_id's first, and then I'll get the actual notes. We need
    # distinct because some notes are connected to multiple english words
    my $sql = qq{
        select distinct extra_note_id from EnglishExtraNotes
        where english_id IN ( $placeholder_str )
    };

    my $extra_ids = $dbh->selectcol_arrayref($sql, {}, @english_ids);

    @placeholders = map { '?' } @$extra_ids;
    $placeholder_str = join ",", @placeholders;
    $sql = qq{
        select info from ExtraNotes where id IN ( $placeholder_str )
        order by id
    };

    my $rows = $dbh->selectcol_arrayref($sql, {}, @$extra_ids);

    return undef unless scalar @$rows;
    return join("\n\n",  @$rows);
}

=head2 extra_translation_information_by_id

Gets extra information about a translation if it exists. You must pass in the
Translation.id

=cut

sub extra_translation_information_by_id {
    my $translation_id = shift;

    my $sql = qq{
        select TranslationExtra.info from Translation
        join TranslationExtra
            on Translation.id = TranslationExtra.translation_id
        where Translation.id = ?
    };

    my @rows = $dbh->selectall_array($sql, {}, $translation_id);
    return undef unless scalar @rows;
    return $rows[0]->[0];
}

=head2 search_english_words

Given a string, this checks the database to see if we have any English words
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

=head2 search

Given a string, this checks the database to see if we have any Teochew words
that contain that string in the pengim, OR if we have English words that are
similar to it. This returns a data structure that can be used directly in the
C<all-translations-table> element.

=cut

sub search {
    my ($input) = @_;

    # If multiple words were provided, try to do a pengim search on each word
    # individually, but require that all of them exist
    my @pengim = map { "%$_%" } split /\s+/, $input;
    my $pengim_where = join ' and ', ("pengim like ?") x scalar @pengim;

    # group concat synonyms?
    my $sql = qq{
        select
            English.word as english,
            English.notes,
            Teochew.pengim,
            Teochew.chinese,
            case when GrammarDefinitions.id is not null
                then 1
                else 0
            end as is_definition
        from Teochew
        join Translation on Teochew.id = Translation.teochew_id
        join English on Translation.english_id = English.id
        left join Synonyms on English.id = Synonyms.english_id
        left join GrammarDefinitions
            on English.id = GrammarDefinitions.english_id
        where hidden = 0 and (
            English.word like ? or notes like ? or
            Synonyms.word like ? or
            ($pengim_where)
        )
        group by Translation.id
        order by case
            when English.word = ? or Synonyms.word = ? then 1
            when Teochew.pengim = ? then 2
            else 3 end
    };
    my @rows = $dbh->selectall_array($sql, { Slice => {} },
        ("%$input%") x 3, @pengim, ($input) x 3);
    return _format_for_translations_table(@rows);
}

=head2 get_all_translations_by_id

Takes an english_id, and optionally a hash of params. In the params, you can
set C<for_flashcards> which will filter out translations that are
"hidden from flashcards"

Returns rows with

    translation_id
    teochew_id
    pengim
    chinese
    simplified
    traditional

=cut

sub get_all_translations_by_id {
    my ($english_id, %params) = @_;
    my $for_flashcards = $params{for_flashcards};

    my $hidden_from_flashcards = $params{for_flashcards} ?
        "and hidden_from_flashcards = 0" : "";

    my $sql = qq{
        select Teochew.id teochew_id, pengim, chinese,
            Translation.id translation_id
        from Teochew
        join Translation on Teochew.id = Translation.teochew_id
        where Translation.english_id = ?
        $hidden_from_flashcards
        order by hidden_from_flashcards
    };
    my @rows = $dbh->selectall_array($sql, { Slice => {} }, $english_id);

    # Check for simplified characters
    for my $row (@rows) {
        my $simplified = get_simplified($row->{chinese});

        $row->{traditional}  = $row->{chinese};
        $row->{simplified} = $simplified if $simplified;
    }

    return @rows;
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

Given a chinese character and optionally some pengim, this will return an
arrayref of details about this character, with each element being a hash of
this form:

    {
        chinese_id      => 1,
        traditional     => '汝'
        simplified      => undef,
        pengim          => 'leu2'
        audio           => 'l/leu2.mp3',
    }

Most Chinese characters only have one entry, but it is possible for there to be
multiple for one character, with different pengim associated with it. If you
supply pengim to this method, it will only look for that specific character
with that specific pengim

XXX: Add more explanation on the "standard pengim" stuff

Returns undef if it can't find a matching entry in the database

=cut

sub chinese_character_details {
    my ($character, $pengim, %params) = @_;

    my $no_alt_pengim = $params{no_alt_pengim};

    my $sql = qq{
        select id, simplified, traditional, pengim, standard_pengim
        from Chinese where (simplified = ? or traditional = ?)
    };
    my @binds = ($character, $character);

    if ($pengim) {
        $sql .= " and pengim = ?";
        push @binds, $pengim;
    }

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds);

    return unless scalar @rows;

    my @return;

    for my $chinese (@rows) {
        push @return, {
            chinese_id  => $chinese->{id},
            simplified  => $chinese->{simplified},
            traditional => $chinese->{traditional},
            pengim      => add_tone_marks($chinese->{pengim}),
            audio       => find_audio($chinese->{pengim}),
        };

        next if $no_alt_pengim;
        if (my $alt = $chinese->{standard_pengim}) {
            my $audio = find_audio($alt);
            push @return, {
                chinese_id  => $chinese->{id},
                simplified  => $chinese->{simplified},
                traditional => $chinese->{traditional},
                pengim      => add_tone_marks($alt),
                audio       => $audio,
            };
        }
    }

    @return = reverse @return if $preferred_accent ne 'gekion';

    return \@return;
}

=head2 parse_chinese

Takes the given string of chinese characters and tries to find words in the
database that represent them. Returns an arrayref, with each element being a
hashref in this form:

    {
        chinese => ''
        pengim => ''
    }

=cut

sub parse_chinese {
    my ($characters) = @_;

    # Each character given could be interpreted as traditional or simplified,
    # but all the words in the database are stored as traditional. Some
    # traditional characters map to the same simplified. So for each
    # character in the string, we need to determine all the possible characters
    # it could represent
    my %char_map;
    for my $char (split //, $characters) {
        next if exists $char_map{$char};

        my @traditional_chars = get_all_possible_traditional_chars($char);
        if (@traditional_chars) {
            $char_map{$char} = \@traditional_chars;
        }
    }

    # Now go through each portion of the string one at a time, and look for
    # words that it could represent
    my $i = 0;
    my @found_words;

    while ($i < length($characters)) {

        # Find the longest word possible--nothing in the database is longer
        # than 5 characters. So we'll start with the first five characters, and
        # then if it doesn't match anything, go down to first four, etc
        my $word_length = 5;
        my $found_word = undef;

        while (!$found_word) {
            my $substring = substr($characters, $i, $word_length);

            # There might not actually be 5 characters left in the word, so
            # shorten the word length to the length of the string
            if (length($substring) < $word_length) {
                $word_length = length($substring);
            }

            # Get all possible strings based on the character map we made above
            my $combinations = Set::CrossProduct->new(\%char_map);

            my @words_to_check;
            my @placeholders;
            while (my $combo = $combinations->get) {
                my $word_to_check = $substring;
                while (my ($orig, $trad) = each %$combo) {
                    $word_to_check =~ s/$orig/$trad/ if $orig ne $trad;
                }
                push @words_to_check, $word_to_check;
                push @placeholders, '?';
            }

            # Search for all the strings in the teochew table
            my $placeholder_str = join(',', @placeholders);
            my $sql = qq{
                select pengim, english.word as english
                from teochew
                left join translation on translation.teochew_id = teochew.id
                left join english on translation.english_id = english.id
                where chinese in ($placeholder_str)
            };
            my @rows = $dbh->selectall_array($sql, { Slice => {} },
                @words_to_check);

            # If we got something, log it into $found_word. If not, lower the
            # word length if possible. If we're at 1 character already, that
            # means this character doesn't exist in our database and we can't
            # provide any sort of translation for it, so exit out of the loop
            if (scalar @rows) {
                $found_word = {
                    chinese => $substring,
                    all_pengim => join(", ", uniq(map { $_->{pengim} } @rows)),
                    english => join(", ", uniq(
                        grep { defined $_ }
                        map  { $_->{english} } @rows
                    )),
                    translations => [map +{
                        english => $_->{english},
                        pengim  => $_->{pengim}
                    }, @rows],
                };
            }
            else {
                if ($word_length == 1) {
                    $found_word = {
                        chinese => $substring,
                        all_pengim => '',
                    };
                }
                else {
                    $word_length--;
                }
            }
        }
        push @found_words, $found_word;
        $i += $word_length;
    }

    return \@found_words;
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

    my $sql = qq{
        select English.word as english, notes, chinese, pengim
        from Teochew
        join Translation on Teochew.id = Translation.teochew_id
        join English on English.id = Translation.english_id
        where hidden = 0
    };

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

    return _format_for_translations_table(@rows);
}

=head2 find_words_using_translation

    find_words_using_translation([1, 2]);

Takes an arrayref of C<$translation_ids>, and returns an arrayref of english
words that include those translations

Returns a data structure formatted similarly to L</find_words_using_character>

=cut

sub find_words_using_translation {
    my ($translations, %params) = @_;

    my $sql = qq{
        select distinct
            English.word as english,
            English.notes,
            Teochew.chinese,
            Teochew.pengim
        from Compound
        join Teochew on Teochew.id = Compound.parent_teochew_id
        join Translation on Translation.teochew_id = Teochew.id
        join English on Translation.english_id = English.id
        where hidden = 0
    };

    my @binds = @$translations;
    my @placeholders = map { '?' } @binds;

    # We need to make sure the words use this translation in the breakdown, but
    # also exclude ones that are already part of the given translation list.
    # (See the "cousin" translation page for an example of why this matters)
    $sql .= " and Compound.translation_id IN (" .
            join(",", @placeholders) . ")";

    $sql .= " and Translation.id NOT IN (" .
            join(",", @placeholders) . ")";

    my @rows = $dbh->selectall_array($sql, { Slice => {} }, @binds, @binds);

    return _format_for_translations_table(@rows);
}

=head2 _format_for_translations_table

Given a set of rows that came directly from the database, returns the format
needed to display in translation tables

Expects a list of hashrefs, each with these fields

    english:       the English column of the table
    english_link:  the path of the url for /english/...
    notes:         stuff in parentheses after the english word
    chinese:       hashref with simplified and traditional
    pengim:        the Peng'Im column of the table
    is_definition: true if this is more of a description than a translation.
                   this will make the word show up italicized

=cut

sub _format_for_translations_table {
    my @rows = @_;

    my @ret;
    for (@rows) {

        my $base_word = $_->{english};
        if (($_->{notes} // '') =~ /$base_word/) {
            $_->{english} = $_->{notes};
            $_->{notes} = undef;
        }

        my $pengim = $_->{pengim};
        $pengim =~ s/\d(\d)/($1)/g;
        my $audio;

        $audio ||= find_audio($pengim);

        $base_word =~ s/\./_/g;

        push @ret, {
            english_link => $base_word,
            english => $_->{english},
            notes   => $_->{notes},
            is_definition => $_->{is_definition},
            teochew => [{
                chinese => {
                    traditional => $_->{chinese},
                    simplified  => get_simplified($_->{chinese}),
                },
                pronunciations => [{
                    pengim  => $pengim,
                    audio   => $audio,
                }]
            }]
        }
    }

    return \@ret;
}

=head2 _is_date

Returns true if the given input looks like a date, which means it has a month
and a number.

=cut

sub _is_date {
    my $input = shift;
    my ($month, $day) = split / /, $input;
    return 0 unless $month && $day;
    return 0 unless $month_numbers{$month};
    return 0 unless $day =~ /\d\d?/;
    return 1;
}

=head2 get_approx_num_translations

Returns the number of non-hidden translations in both the Translation and the
Phrases table. This isn't actually the number of translations because some
sentences get expanded more, and this completely ignores all the number and
clock time stuff. But it's I<at least> this much

=cut

sub get_approx_num_translations {
    my $word_count = $dbh->selectrow_array(qq{
        select count(*) from English
        join Translation on English.id = Translation.english_id
        where English.hidden = 0
            and Translation.hidden_from_flashcards = 0;
    });

    my $sentence_count = $dbh->selectrow_array(qq{
        select count(*) from Phrases where hidden = 0
    });

    return $word_count + $sentence_count;
}

=head2 get_simplified

Given a string with traditional Chinese characters, this checks to see if the
simplified variant is different, and if it is, it will return that. This
returns undef if they are the same

=cut

sub get_simplified {
    my $full_traditional = shift;
    my @traditional = split //, $full_traditional;

    my $full_simplified = '';

    for my $i (0..$#traditional) {
        my $simplified = $dbh->selectrow_array(qq{
            select simplified from Chinese
            where traditional = ?
        }, undef, $traditional[$i]);

        $full_simplified .= ($simplified || $traditional[$i]);
    }

    return $full_simplified if $full_simplified ne $full_traditional;
    return undef;
}

=head2 get_all_possible_traditional_chars

This takes a single Chinese character and searches for it in the database under
BOTH the traditional and simplified field. It will return all the possible
traditional characters that it finds in those rows

=cut

sub get_all_possible_traditional_chars {
    my $character = shift;
    my @rows = $dbh->selectall_array(qq{
        select distinct traditional from Chinese
        where simplified = ? or traditional = ?
    }, undef, $character, $character);

    return map { $_->[0] } @rows;
}

# TODO
#sub find_phrases_using_word {
#}

