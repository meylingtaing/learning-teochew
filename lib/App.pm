package App;
use Mojo::Base 'Mojolicious';

sub startup {
    my $app = shift;

    # Hides any 'trace' level log messages, including all the
    # "Rendering template" ones
    $app->log->level('debug');

    my $r = $app->routes;

    # Flashcards
    $r->get('/')->to('root#index');
    $r->get('/flashcards/:type/:subtype')->to('root#flashcards',
        type => '', subtype => '');

    $r->get('/category/:category/:subcategory')->to('root#category',
        subcategory => '');

    $r->get('/translate')->to('root#translate');
    $r->get('/search_pengim')->to('root#search_pengim');
    $r->get('/search')->to('root#search');
    $r->get('/english/:english')->to('root#english');
    $r->get('/chinese/:character')->to('root#chinese');

    $r->get('/lesson/:lesson')->to('root#lesson');
    $r->get('/updates/:page')->to('root#updates', page => 0);

    # Static pages
    $r->get('/about');
    $r->get('/links');
}

1;
