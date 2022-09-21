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
when you press Enter from the search bar.

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

sub search {
    my $c = shift;
    my $search = trim $c->param('search');

    unless ($search =~ /^[[:ascii:]]+$/) {
        $c->redirect_to("/chinese/$search");
        return;
    }

    my @results = Teochew::search_english_words($search);

    $c->stash(results => \@results);
    $c->stash(search  => $search);
    $c->render(template => 'search');
};

=head2 category

The Category page, which is accessed with a path like C</category/colors>

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
            Teochew::generate_full_translations(
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
        my $teochew = Teochew::translate($_, show_all_accents => 1);
        next unless scalar @$teochew;

        # Organize this by category
        my %categories;
        for my $translation (@$teochew) {
            my $name = $translation->{category}{name} // '';
            $categories{$name} //= {
                display       => $translation->{category}{display},
                flashcard_set => $translation->{category}{flashcard_set},
            };
            push @{ $categories{$name}{teochew} }, $translation;
        }

        $c->stash(teochew_by_category => \%categories);

        $c->stash(english    => $_);
        $c->stash(extra_info => markdown(
            Teochew::extra_information($english) // ''
        ));

        my @chinese = map { $_->{chinese} } @$teochew;
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
    my $updates = Updates::get_updates($page);
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
