package App;
use Mojo::Base 'Mojolicious';

sub startup {
    my $app = shift;

    # Hides any 'trace' level log messages, including all the
    # "Rendering template" ones
    $app->log->level('debug');

    $app->hook(before_dispatch => sub {
        my ($c) = @_;

        # Copy pasted from Mojolicious.pm -- I wanted this log message, but
        # it's set at the 'trace' level, and I'm hiding those by default since
        # I don't want to see all the "Rendering template..." messages
        $app->log->debug(sub {
            my $req    = $c->req;
            my $method = $req->method;
            my $path   = $req->url->path->to_abs_string;
            $c->helpers->timing->begin('mojo.timer');
            return qq{$method "$path"};
        });
    });

    my $r = $app->routes;

    # Flashcards
    $r->get('/')->to('root#index');
    $r->get('/flashcards/:type/:subtype')->to('root#flashcards',
        type => '', subtype => '');

    $r->get('/category/:category/:subcategory')->to('root#category',
        subcategory => '');

    $r->get('/translate')->to('root#translate');
    $r->get('/search')->to('root#search');
    $r->get('/english/:english')->to('root#english');
    $r->get('/chinese/:character')->to('root#chinese');

    $r->get('/lesson/:lesson')->to('root#lesson');
    $r->get('/updates/:page')->to('root#updates', page => 0);

    # Static pages
    $r->get('/about')->to('root#about');
    $r->get('/links');
}

1;
