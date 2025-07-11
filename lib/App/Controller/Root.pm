package App::Controller::Root;
use Mojo::Base 'Mojolicious::Controller';

use Teochew;
use Updates;

use JSON;
use String::Util qw(trim);
use Text::MultiMarkdown qw(markdown);
use Lingua::EN::FindNumber qw(numify);
use List::MoreUtils qw(all uniq);

use Data::Dumper;

sub index {
    shift->redirect_to('/flashcards');
}

=head2 flashcards

The Flashcards action, which is the default if you don't provide a path in
the URL

=cut

sub flashcards {
    my $c = shift;

    my $type    = $c->stash('type');
    my $subtype = $c->stash('subtype');

    my $flashcards = Teochew::generate_flashcards($type, $subtype);

    unless (@$flashcards) {
        $c->redirect_to('/flashcards');
        return;
    }

    for my $flashcard (@$flashcards) {
        my $extra_notes = Teochew::extra_information_by_id($flashcard->{english_id})
            if $flashcard->{english_id};
        $flashcard->{extra_notes} = $extra_notes ? markdown($extra_notes) : '';
    }

    $c->stash(flashcard_set_name => Teochew::flashcard_set_name($type, $subtype));
    $c->stash(flashcard          => $flashcards->[0]);
    $c->stash(flashcard_list     => to_json($flashcards));

    $c->render(template => 'flashcard');
}

=head2 translate

When you click on 'Translate' from the search bar. This is also what happens
when you press Enter from the search bar. This will attempt to translate the
word that's being searched, but if that word can't be found, then it will do
a search for similar words.

=cut

sub translate {
    my $c = shift;
    my $search = trim $c->param('search');

    if ($search eq '') {
        $c->redirect_to("/flashcards");
        return;
    }

    # Replace any . with _
    $search =~ s/\./_/g;

    # Not very smart right now, this just checks if there are non-ascii
    # characters for switching to chinese
    if ($search =~ /^[[:ascii:]]+$/) {
        $c->redirect_to("/english/$search");
    }
    else {
        $c->redirect_to("/chinese/$search");
    }
}

=head2 search

This is what happens when you click on Search. The list of words will be
searched against the English words, Teochew pengim, and Chinese characters.

=cut

sub search {
    my $c = shift;
    my $search = trim $c->param('search');

    unless ($search =~ /^[[:ascii:]]+$/) {
        $c->redirect_to("/chinese/$search");
        return;
    }

    $c->stash(results => Teochew::search($search));
    $c->stash(search  => $search);
    $c->render(template => 'search');
}

=head2 category

The Category page, which is accessed with a path like C</category/colors>. This
displays a table of all of the words within a "flashcard set", which actually
can contain subcategories within it.

=cut

sub category {
    my $c = shift;
    my $flashcard_set = $c->stash('category');
    my $subcategory   = $c->stash('subcategory');

    my @categories  = Teochew::flashcard_set_categories(
        $flashcard_set, $subcategory);

    my %category_translations = map { $_->{name} => {
        category_name => $_->{display_name},
        translations  => [
            Teochew::generate_translation_word_list(
                flashcard_set => $flashcard_set,
                category      => $_->{name},
                subcategory   => $subcategory
            )
        ],
    } } @categories;

    $c->stash(flashcard_set => $flashcard_set);
    $c->stash(flashcard_set_display =>
        Teochew::flashcard_set_name($flashcard_set));

    $c->stash(categories            => \@categories);
    $c->stash(category_translations => \%category_translations);

    $c->stash(hide_links => $flashcard_set eq 'phrase');

    $c->render(template => 'category');
}

=head2 english

The English page, which is accessed using a url like C</english/hello>

C<english> must be stashed

=cut

sub english {
    my $c = shift;
    my $input = trim $c->stash('english');

    # Replace _ with .
    $input =~ s/_/./g;

    my @all_tags;

    # All of the verbs in the database are stored like "to eat", but we should
    # allow someone to see the translation without typing the "to" part of it.
    # And we should also check if the user typed a number
    for my $english ("$input", "$input...", "to $input", numify($input)) {

        # First, look for english words in the database that match. There might
        # be multiple
        my @english_rows = Teochew::get_english_from_database(
            word                       => $english,
            include_category_in_output => 1,
            check_synonyms             => 1,
        );

        # This also could be a number or a clock time, and we don't have
        # entries for those, but we have special translate functions for them
        unless (@english_rows) {
            if ($english =~ /^\d+$/) {
                push @english_rows, {
                    word => $english,
                    category_display   => 'Numbers',
                    flashcard_set_name => 'number',
                };
            }
            elsif ($english =~ /^\d+:\d+$/) {
                push @english_rows, {
                    word => $english,
                    category_display   => 'Clock Time',
                    flashcard_set_name => 'time',
                };
            }
        }

        next unless scalar @english_rows;

        my $english_display = $english;
        my $is_synonym = 0;

        # It's possible a synonym was used to get to this page, so explicitly
        # set the English word to the non-synonym for synonym lookups later
        if (all { lc($_->{word}) ne lc($english) } @english_rows) {
            $english = $english_rows[0]{word};
            $is_synonym = 1;
        }

        # Organize this by category. Also keep track of translation ids
        my %categories;
        my @translation_ids;

        for my $english_row (@english_rows) {

            # This is kinda weird, but if we're searching a word like "hard",
            # which has its own entry, but is also a synonym for "difficult",
            # then let's actually display "difficult" in the grayed out note
            # above the translation
            if (scalar(@english_rows) > 1 &&
                !$is_synonym &&
                lc($english_row->{word}) ne lc($english))
            {
                $english_row->{notes} //= $english_row->{word};
            }

            if (scalar @english_rows == 1 && $english_row->{notes}) {
                $english_display .= " ($english_row->{notes})";
                $english_row->{notes} = undef;
            }

            my $category = $english_row->{category_name} // '';
            $categories{$category} //= {
                display       => $english_row->{category_display},
                flashcard_set => $english_row->{flashcard_set_name},
            };

            # Get the translation
            my $translation_rows = Teochew::translate(
                $english_row,
                show_all_accents => 1
            );

            for my $translation_row (@$translation_rows) {
                my $teochew_id = $translation_row->{teochew_id};

                my $alternates = Teochew::check_alternate_chinese(
                    teochew_id => $teochew_id);
                if (my $alts = $alternates->{has_alts}) {
                    $translation_row->{alt_chinese} = $alts;
                }

                # Get the compound word breakdown, but let's only display it
                # if we have all the components filled in
                my @components = Teochew::compound_word_components($teochew_id);
                if (@components && (all { $_->{word} ne '' } @components)) {
                    $translation_row->{compound} = \@components;
                }

                my $extra_translation_notes =
                    Teochew::extra_translation_information_by_id(
                        $translation_row->{translation_id}
                    );
                $translation_row->{extra_notes} = $extra_translation_notes ?
                    markdown($extra_translation_notes) : undef;

                push @translation_ids, $translation_row->{translation_id};
                push @{ $categories{$category}{teochew} }, {
                    %$translation_row,
                    notes => $english_row->{notes},
                };
            }

            # Get any tags for this word
            my @tags = Teochew::get_tags($english_row->{id});
            push @all_tags, @tags;

        } # end @english_rows loop

        $c->stash(teochew_by_category => \%categories);

        if ($english_rows[0]{is_definition}) {
            $english_display = "<i>$english_display</i>";
        }
        $c->stash(english  => $english_display);

        my @synonyms = Teochew::get_synonyms($english);
        if ($is_synonym) {
            @synonyms = grep { $_ ne $input && $_ ne "to $input" } @synonyms;
            unshift @synonyms, $english;
        }
        $c->stash(synonyms => \@synonyms);

        $c->stash(tags => join ', ', uniq(@all_tags));

        # Add any extra notes
        my $extra_notes =  Teochew::extra_information_by_id(
                                map { $_->{id} } @english_rows) // '';
        $c->stash(extra_info => $extra_notes ? markdown($extra_notes) : undef);

        $c->stash(words_containing => Teochew::find_words_using_translation(
            \@translation_ids,
        ));

        $c->render(template => 'translate');
        return;
    }

    # Redirect to the search page if we have no translations available
    $c->redirect_to("/search?search=$input");
}

=head2 chinese

The page for seeing details for a Chinese character

=cut

sub chinese {
    my $c = shift;

    my $character  = $c->stash('character');
    my $chinese    = Teochew::chinese_character_details($character);

    # Look up extra details about this character if it exists in our database
    my ($words, $alternates);
    if ($chinese) {

        # It's possible that the traditional character was searched. Use the
        # simplified character for finding other words using this character
        my $simplified = $chinese->[0]{simplified};

        $words      = Teochew::find_words_using_character($simplified);
        $alternates = Teochew::check_alternate_chinese(chinese => $character);
    }

    $c->stash(chinese => $chinese);
    $c->stash(words => $words);
    $c->stash(alternates => $alternates);
    $c->render(template => 'chinese');
};

=head2 updates

The Updates page, which can be accessed via C</updates>

=cut

sub updates {
    my $c = shift;

    my $page = $c->stash('page');
    $page = 0 unless $page =~ /^\d+$/;

    # Need to convert the markdown to html
    my $updates = Updates->new->get_updates($page);
    $_->{content} = markdown($_->{content}) for @$updates;

    # See if we should add More Recent and Older
    $c->stash(prev => ($page > 0) ? ($page - 1) : undef);
    $c->stash(next => undef);

    if (scalar @$updates > 5) {
        $c->stash(next => ($page + 1));
        pop @$updates;
    }

    $c->stash(updates => $updates);
    $c->render(template => 'updates');
};

sub lesson {
    my $c = shift;

    my $lesson = $c->stash('lesson');
    $c->render_maybe(template => "lessons/$lesson") or
        $c->redirect_to("/flashcards");
}

=head2 about

The 'About' page

=cut

sub about {
    my $c = shift;

    $c->stash(num_translations => Teochew::get_approx_num_translations);
    $c->render(template => 'about');
}

1;
