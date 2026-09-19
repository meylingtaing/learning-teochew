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

        # Check if the user wants traditional characters. This is used all over
        # the place which is why I'm adding it here at the beginning
        my $traditional = ($c->cookie('simptrad') // '') eq 'traditional';
        $c->stash(traditional => $traditional);
    });

    $app->plugin('Mojolicious::Plugin::Blog');

    # Should really rename this to be more blog-specific because this actually
    # has two database files
    $app->defaults(db => 'Updates.sqlite');

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
    $r->get('/chinese/:characters')->to('root#chinese');

    $r->get('/lesson/:lesson')->to('root#lesson');
    $r->get('/updates/:page')->to('blog#blog', page => 0, template => 'updates');
    $r->get('/rss')->to('blog#rss',
        title => 'Learning Teochew - updates',
        url_base => 'https://learningteochew.com/updates');

    # Static pages
    $r->get('/about')->to('root#about');
    $r->get('/links');
}

1;
