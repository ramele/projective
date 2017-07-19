#!/usr/bin/perl

# fast fuzzy-file-engine for Vim's projective plugin.
# Author: Ramel Eshed

$|++;

open $handle, '<', $ARGV[0];
chomp(@files = <$handle>);
close $handle;
@files = map { do { s/.*\///; $_ } } @files;

@cur_idxs = (0..(@files - 1));

while (<STDIN>) {
    chomp;
    if ($_ ne "<") {
        $in_pattern .= $_;
        push @stack, [@cur_idxs];
        ($pattern = $in_pattern) =~ s/./$&.*?/g;
#        $pattern =~ s/\./\\./g; # TODO
        $len = length($in_pattern);
        @_cur_idxs = ();
        foreach $i (@cur_idxs) {
            if ($files[$i] =~ /$pattern/i) {
                $files[$i] =~ /.*\K$pattern/i;
                if ($len == 1) {
                    push @_cur_idxs, [length($files[$i]), $i];
                }
                else {
                    push @_cur_idxs, [($len / ($+[0] - $-[0])) * 500 - $-[0] - (length($files[$i]) - $+[0]), $i];
                }
            }
        }
        @sorted = sort {$b->[0] <=> $a->[0]} @_cur_idxs;
        @cur_idxs = map { $_->[1] } @sorted;
    }
    elsif ($in_pattern) {
        chop($in_pattern);
        @cur_idxs = @{pop @stack};
    }

#    foreach $i (@sorted) {
#        print $files[$i->[1]] . "  " . $i->[0] . "\n";
#    }
    foreach $i (@cur_idxs) {
        print "$i\n";
    }
    print "--\n";
}

