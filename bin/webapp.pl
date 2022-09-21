#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use FindBin;
BEGIN { unshift @INC, "$FindBin::Bin/../lib" }

use Mojolicious::Commands;

Mojolicious::Commands->start_app('App');
