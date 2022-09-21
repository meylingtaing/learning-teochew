package Input;

use strict;
use warnings;

use File::Temp qw(tempfile);
use open ':encoding(UTF-8)';

=head2 get_input_via_editor

This opens up vim to edit the text

=cut

sub via_editor {
    my ($content) = @_;

    # Make a temporary file
    my ($fh, $filename) = tempfile("update-XXXX",
        DIR    => 'tmp',
        SUFFIX => '.txt',
    );

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

1;
