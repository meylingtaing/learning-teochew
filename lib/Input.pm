package Input;

=head1 NAME

Teochew::Edit

=head1 DESCRIPTION

Provides functions for getting input from the user

    use Input qw(confirm input_via_editor input_from_prompt);
    my $input = input_from_prompt("Enter a word:");

=cut

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(confirm input_via_editor input_from_prompt);

use Carp;
use File::Temp qw(tempfile);
use open ':encoding(UTF-8)';

=head2 input_via_editor

This opens up vim to edit the text

=cut

sub input_via_editor {
    my ($content) = @_;

    # Create a tmp directory if it doesn't exist
    my $folder = 'tmp';
    mkdir $folder unless -d $folder;

    # Make a temporary file
    my ($fh, $filename) = tempfile("update-XXXX",
        DIR    => $folder,
        SUFFIX => '.txt',
    );

    binmode($fh, ":utf8");
    print $fh $content;
    close $fh;

    # Open up vim on that file
    system('vim', $filename);

    # Once vim is closed, read the contents of the file
    open($fh, "<", $filename) or die "Cannot read $filename: $!";
    $content = do { local $/; <$fh> };

    unlink $filename;

    return $content;
}

=head2 input_from_prompt

This prompts the user with the given prompt, and reads and returns input
from STDIN

=cut

sub input_from_prompt {
    my ($prompt) = @_;

    croak "Must provide prompt to input_from_prompt!\n" unless defined $prompt;

    print "$prompt ";
    my $input = <STDIN>;
    chomp $input;
    return $input;
}

=head2 confirm

Prompts the user with "Is this okay?" and returns true if the user typed in
something that starts with 'y'

=cut

sub confirm {
    my $yesno = input_from_prompt("Is this okay?");
    return 1 if substr($yesno, 0, 1) eq 'y';
    return 0;
}

1;
