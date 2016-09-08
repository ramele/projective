#!/usr/bin/perl

# fast fuzzy-file-engine for Vim's projective plugin.
# Author: Ramel Eshed

$|++;

open $handle, '<', $ARGV[0];
chomp(@files = <$handle>);
close $handle;

@cur_idxs = (0..(@files - 1));

while (<STDIN>) {
    chomp;
    if ($_ ne "<") {
        $in_pattern .= $_;
        push @stack, [@cur_idxs];
        ($pattern = $in_pattern) =~ s/./$&\[^\/\]*?/g;
        $pattern =~ s/\./\\./g;
        $pattern .= '(?=[^/]*$)';
        @_cur_idxs = ();
        foreach $i (@cur_idxs) {
            if ($files[$i] =~ /$pattern/) {
                $files[$i] =~ /[^\/]*$pattern/;
                push @_cur_idxs, [$+[0] - $-[0], $i];
            }
        }
        @sorted = sort {$a->[0] <=> $b->[0]} @_cur_idxs;
        @cur_idxs = map { $_->[1] } @sorted;
    }
    elsif ($in_pattern) {
        chop($in_pattern);
        @cur_idxs = @{pop @stack};
    }

    foreach $i (@cur_idxs) {
        print "$i\n";
    }
    print "--\n";
}

