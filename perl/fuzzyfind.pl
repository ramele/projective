#!/usr/bin/perl

# Fast fuzzy-match engine for Vim's projective plugin.
# Author: Ramel Eshed

$|++;

open $handle, '<', $ARGV[0];
chomp(@files = <$handle>);
close $handle;
if ($ARGV[1] eq "--no-path") {
    @files = map { do { s/.*\///; $_ } } @files;
}

@cur_idxs = (0..(@files - 1));

while (<STDIN>) {
    chomp;
    if ($_ ne "<") {
        $in_pattern .= $_;
        push @stack, [@cur_idxs];
        ($pattern = $in_pattern) =~ s/./$&.*?/g;
        $pattern =~ s/\.\./\\../g;
        $plen = length($in_pattern);
        @_cur_idxs = ();
        foreach $i (@cur_idxs) {
            if ($files[$i] =~ /.*\K$pattern/i) {
                $mstart = $-[0];
                $mend   = $+[0];
                $fstart = ($` =~ /\/[^\/]*$/) ? $-[0] + 1 : 0;
                $fend   = length($files[$i]);
                $rank = 30 * $plen / ($mend - $mstart) - 20 * ($mstart - $fstart + $fend - $mend) / ($fend - $fstart);
                push @_cur_idxs, [$rank, $i];
            }
        }
        @sorted = sort {$b->[0] <=> $a->[0]} @_cur_idxs;
        @cur_idxs = map { $_->[1] } @sorted;
    }
    elsif ($in_pattern) {
        chop($in_pattern);
        @cur_idxs = @{pop @stack};
    }

    #$index = 0;
    #foreach $i (@sorted) {
        #print $files[$i->[1]] . "  " . $i->[0] . "\n";
        #last if $index++ == 10;
    #}
    foreach $i (@cur_idxs) {
        print "$i\n";
    }
    print "--\n";
}
