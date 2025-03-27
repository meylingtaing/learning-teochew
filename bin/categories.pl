#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);
use lib 'lib';

use Teochew;

my @categories = Teochew::categories;
for my $category (@categories) {
    say "$category->{id}: $category->{name}";
}
