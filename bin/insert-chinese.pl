#!/usr/bin/env -S perl -CA -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);
use lib 'lib';

binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN,  ':encoding(UTF-8)';

use Data::Dumper;
use Getopt::Long qw(GetOptionsFromArray);
use Term::ANSIColor qw(colored);

use Teochew;
use Teochew::Edit;
use Teochew::Utils qw(split_out_parens);
use Input qw(confirm input_from_prompt);

# bin/insert-chinese.pl "失 ()" "sek8" "sik8"

my ($chinese, $pengim, $standard_pengim) = @ARGV;

# Require both Chinese and pengim
die "Must include chinese and pengim!" unless $chinese and $pengim;

# See if we have both simplified AND traditional given
my ($simplified, $traditional) = split_out_parens($chinese);

my $db = Teochew::Edit->new;
$db->confirm_and_insert_chinese(
    simplified      => $simplified,
    traditional     => $traditional,
    pengim          => $pengim,
    standard_pengim => $standard_pengim,
);
