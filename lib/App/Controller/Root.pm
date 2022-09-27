package App::Controller::Root;
use Mojo::Base 'Mojolicious::Controller';

use Teochew;
use Updates;

use JSON;
use String::Util qw(trim);
use Text::MultiMarkdown qw(markdown);
use Lingua::EN::FindNumber qw(numify);

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

    # Turn any english number words in the actual number
    $search = numify($search);

    # Not very smart right now, this just checks if there are non-ascii
    # characters for switching to chinese
    if ($search =~ /^[[:ascii:]]+$/) {
        $c->redirect_to("/english/$search");
    }
    else {
        $c->redirect_to("/chinese/$search");
    }
};

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
};

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

    $c->stash(categories => \@categories);
    $c->stash(category_translations => \%category_translations);

    $c->stash(hide_links => $flashcard_set eq 'phrase');

    $c->render(template => 'category');
};

=head2 english

The English page, which is accessed using a url like C</english/hello>

C<english> must be stashed

=cut

sub english {
    my $c = shift;
    my $english = trim $c->stash('english');

    # All of the verbs in the database are stored like "to eat", but we should
    # allow someone to see the translation without typing the "to" part of it
    for ($english, "to $english") {

        # First, look for english words in the database that match. There might
        # be multiple
        my @english_rows = Teochew::get_english_from_database(
            word => $_, include_category_in_output => 1
        );

        # This also could be a number or a clock time, and we don't have
        # entries for those, but we have special translate functions for them
        unless (@english_rows) {
            if ($_ =~ /^\d+$/) {
                push @english_rows, {
                    word => $_,
                    category_display   => 'Numbers',
                    flashcard_set_name => 'number',
                };
            }
            elsif ($_ =~ /^\d+:\d+$/) {
                push @english_rows, {
                    word => $_,
                    category_display   => 'Clock Time',
                    flashcard_set_name => 'time',
                };
            }
        }

        next unless scalar @english_rows;

        my $english_display = $_;

        # Organize this by category. Also keep track of chinese characters.
        my %categories;
        my @chinese;
        for my $english_row (@english_rows) {

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
                # XXX: I might try this again later, but I find that showing
                # multiple accents makes the page look cluttered
                #show_all_accents => 1
            );

            for my $translation_row (@$translation_rows) {
                push @chinese, $translation_row->{chinese};
                push @{ $categories{$category}{teochew} }, {
                    %$translation_row,
                    notes => $english_row->{notes},
                };
            }
        }

        $c->stash(teochew_by_category => \%categories);
        $c->stash(english  => $english_display);
        $c->stash(synonyms => [Teochew::get_synonyms($_)]);

        $c->stash(extra_info => markdown(
            Teochew::extra_information($english) // ''
        ));

        $c->stash(words_containing =>
            Teochew::find_words_using_character(\@chinese, exclude_itself => 1)
        );

        $c->render(template => 'translate');
        return;
    }

    # Redirect to the search page if we have no translations available
    $c->redirect_to("/search?search=$english");
};

sub chinese {
    my $c = shift;

    my $character = $c->stash('character');
    my $details   = Teochew::chinese_character_details($character);
    my $words     = Teochew::find_words_using_character($character);

    $c->stash(chinese => $details);
    $c->stash(words => $words);
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

1;
