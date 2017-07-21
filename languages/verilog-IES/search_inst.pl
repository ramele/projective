#!/usr/bin/perl

# Generate a sub-tree of a given module and its ancestors
# $search_inst.pl scope_tree.txt my_module
# Author: Ramel Eshed
# Thanks to Eran Meisner!

open($fh, "<", $ARGV[0]);
chomp(@lines = <$fh>);
close($fh);

chomp(@grep_out = `grep -n '($ARGV[1])' $ARGV[0]`);
@inst_lines = map { do { s/:.*//; $_ } } @grep_out;

@out = ();
$prev_inst_ln = 0;
foreach $ln (@inst_lines) {
    @tmp = ();
    $prev_off = 10000;
    $l = $ln - 1;
    while ($prev_off) {
        last if $l <= $prev_inst_ln;
        $lines[$l] =~ /[+-]-/;
        $off = $-[0];
        if ($off < $prev_off) {
            $lines[$l] =~ s/\+-/--/ if !@tmp;
            unshift(@tmp, $lines[$l]);
            $prev_off = $off;
        }
        $l -= 1;
    }
    $prev_inst_ln = $ln;
    push(@out, @tmp);
}

print "# " . @inst_lines . " instances found:\n\n";
foreach $o (@out) {
    print "$o\n";
}
