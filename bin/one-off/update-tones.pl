#!/usr/bin/env perl

use strict;
use warnings;

use feature qw(say);

use DBI qw(:sql_types);
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode);

use List::Util qw(any);
use Data::Dumper;

use open ':std', ':encoding(utf8)';

my $dbh = DBI->connect("DBI:SQLite:dbname=Teochew.sqlite");
$dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;

# Get all of the teochew in the database
my @rows = $dbh->selectall_array(qq{
    select
        Teochew.id teochew_id,
        word as english,
        coalesce(notes, '') notes,
        pengim,
        chinese
    from Teochew
    join English on English.id = english_id
    where tone_updated = 0
    limit 10
}, { Slice => {} });

for my $row (@rows) {
    say "Looking at $row->{english} ($row->{notes}): " .
        "$row->{pengim} $row->{chinese}";

    # If there are any double numbers in the pengim, we should assume we've
    # already fixed the tone
    if ($row->{pengim} =~ /\d\d/) {
        mark_done($row->{teochew_id});
        next;
    }

    # Split the chinese and pengim into parts
    my @pengim_parts  = split / /, $row->{pengim};
    my @chinese_parts = split //, $row->{chinese};

    # Nothing to do if there's only one syllable
    if (scalar @pengim_parts == 1) {
        mark_done($row->{teochew_id});
        next;
    }

    my @new_pengim;
    for (my $i = 0; $i < scalar @pengim_parts; $i++) {
        my $pengim  = $pengim_parts[$i];
        my $chinese = $chinese_parts[$i];

        # Tone 1 just changes to tone 1, so keep it the same
        if ($pengim =~ /1$/) {
            push @new_pengim, $pengim;
            next;
        }

        # Anything else _might_ have gone through tone change, so let's
        # look up what we have listed in the pengim for the chinese
        my $pengim_without_tone = substr $pengim, 0, -1;
        my $tone                = substr $pengim, -1, 1;

        my @chinese_rows = $dbh->selectall_array(qq{
            select pengim from chinese
            where traditional = ? and pengim like ?
        }, { Slice => {} }, $chinese, "$pengim_without_tone%");

        if (scalar @chinese_rows == 0) {
            warn "\tCan't find Chinese character details for $chinese!\n";
            push @new_pengim, $pengim;
            next;
        }

        my @tones =
            map  { substr $_->{pengim}, -1 }
            grep { $_->{pengim} =~ /^$pengim_without_tone\d$/ } @chinese_rows;

        if ($tone eq '2') {
            # Two possibilities:
            # - tone 2, no sandhi
            # - tone 3, sandhi'ed to tone 2
            @tones = sort grep { $_ eq '2' || $_ eq '3' } @tones;
            if (scalar(@tones) == 1) {
                if ($tones[0] eq '3') {
                    push @new_pengim, "${pengim_without_tone}32";
                }
                else {
                    push @new_pengim, $pengim;
                }
            }
            else {
                warn "\tUnclear what the base tone is for $chinese $pengim\n";
                push @new_pengim, $pengim;
            }
        }
        elsif ($tone eq '4') {
            # Two possibilities:
            # - tone 4, no sandhi
            # - tone 8, sandhi'ed to tone 4
            @tones = sort grep { $_ eq '4' || $_ eq '8' } @tones;
            if (scalar(@tones) == 1) {
                if ($tones[0] eq '8') {
                    push @new_pengim, "${pengim_without_tone}84";
                }
                else {
                    push @new_pengim, $pengim;
                }
            }
            else {
                warn "\tUnclear what the base tone is for $chinese $pengim\n";
                push @new_pengim, $pengim;
            }
        }
        elsif ($tone eq '6') {
            # Two possibilities:
            # - tone 6, no sandhi
            # - tone 2, sandhi'ed to tone 6
            @tones = sort grep { $_ eq '2' || $_ eq '6' } @tones;
            if (scalar(@tones) == 1) {
                if ($tones[0] eq '2') {
                    push @new_pengim, "${pengim_without_tone}26";
                }
                else {
                    push @new_pengim, $pengim;
                }
            }
            else {
                warn "\tUnclear what the base tone is for $chinese $pengim\n";
                push @new_pengim, $pengim;
            }
        }
        elsif ($tone eq '8') {
            # Two possibilities:
            # - tone 8, no sandhi
            # - tone 4, sandhi'ed to tone 8
            @tones = sort grep { $_ eq '4' || $_ eq '8' } @tones;
            if (scalar(@tones) == 1) {
                if ($tones[0] eq '4') {
                    push @new_pengim, "${pengim_without_tone}48";
                }
                else {
                    push @new_pengim, $pengim;
                }
            }
            else {
                warn "\tUnclear what the base tone is for $chinese $pengim\n";
                push @new_pengim, $pengim;
            }
        }
        elsif ($tone eq '7') {
            # Three possibilities:
            # - tone 7, no sandhi
            # - tone 6, sandhi'ed to tone 7
            # - tone 5, sandhi'ed to tone 7
            @tones = sort grep { $_ eq '5' || $_ eq '6' || $_ eq '7' } @tones;
            if (scalar(@tones) == 1) {
                if ($tones[0] eq '5' || $tones[0] eq '6') {
                    push @new_pengim, "${pengim_without_tone}$tones[0]7";
                }
                else {
                    push @new_pengim, $pengim;
                }
            }
            else {
                warn "\tUnclear what the base tone is for $chinese $pengim\n";
                push @new_pengim, $pengim;
            }
        }
        elsif ($tone eq '3' || $tone eq '5') {
            push @new_pengim, $pengim;
        }
        else {
            die "Huh? $pengim doesn't make sense\n";
        }
    }

    my $new_pengim_string = join ' ', @new_pengim;
    if ($new_pengim_string ne $row->{pengim}) {
        warn "\tNew pengim: $new_pengim_string\n";
        $dbh->do(qq{
            update Teochew set pengim = ?, tone_updated = 1
            where id = ?
        }, undef, $new_pengim_string, $row->{teochew_id});
    }
    else {
        mark_done($row->{teochew_id});
    }
}

sub mark_done {
    my ($teochew_id) = @_;
    $dbh->do('update Teochew set tone_updated = 1 where id = ?',
        undef, $teochew_id);
}
