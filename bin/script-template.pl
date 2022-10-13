#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

# These are required to print non-ascii characters to STDOUT or
# read them in @ARGV
binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

# We almost certainly want access to these
use lib 'lib';
use Teochew;
use Teochew::Edit;

# need to explicitly include exported functions
use Teochew::Utils qw(); 
use Input qw(confirm input_from_prompt input_via_editor);

use Data::Dumper;
use Term::ANSIColor qw(colored);

my $db = Teochew::Edit->new;
