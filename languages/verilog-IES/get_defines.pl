#!/usr/bin/perl

# Extract multi-line defines from a project
# Author: Ramel Eshed

$prev_file = "";

while (<STDIN>) {
    ($file, $lnr, $define) = $_ =~ /([^:]*):(\d*):(.*)/;
    print "// defines from $file:\n" if $file ne $prev_file;
    $prev_file = $file;
    print "$define\n";
    if ($define =~ /\\\s*$/) {
        open $fh, '<', $file;
        chomp(@lines = <$fh>);
        while (@lines[$lnr-1] =~ /\\\s*$/) {
            print "@lines[$lnr]\n";
            $lnr ++;
        }
        close $fh;
    }
}
