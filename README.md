Teochew Flashcards
==================

This is just a little side project that I'm working on to help me learn
Teochew. It's a web app with flashcards, and it's live at
[https://learningteochew.com](https://learningteochew.com)!

## Development setup

This is written in perl, so you should have that installed. I don't know what
version of perl this requires, but I currently have v5.34.0

You should also install [Carton](https://github.com/perl-carton/carton), and
then install all the perl dependencies using `carton install`.

In order to connect to the database, you will also need to install `sqlite3`.

## How to start up the web app in development mode

    make sandbox

## How to start up the server in production

    sudo service start nginx
    make prod
