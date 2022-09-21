#!/usr/bin/env -S perl -Ilocal/lib/perl5

use strict;
use warnings;

use feature qw(say);

use File::Basename;
use File::Copy;

# Get all of the audio clips
my @files = <public/audio/*>;

for my $file (@files) {
    my $base = basename($file);

    # Figure out the beginning sound
    my $beginning;

    if ($base =~ /.mp3$/) {
        if ($base =~ /^([aeiou])/) {
            $beginning = $1;
        }
        elsif ($base =~ /^([^aeiou]+)/) {
            $beginning = $1;
        }

        # Create folder if it doesn't exist
        my $folder = "public/audio/$beginning";
        unless (-d $folder) {
            say "Creating folder $folder";
            mkdir $folder;
        }

        # Set the permissions so it's not executable
        chmod 0664, $file;

        # Move file to the folder
        move $file, $folder;
    }
}
