#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

my $command = "carton exec -- mojo-blog";
$command .= " '$ARGV[0]'" if $ARGV[0];

open(my $blog_file, '|-', $command);
close $blog_file;
