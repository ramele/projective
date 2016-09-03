#!/usr/bin/perl

# Returns list of all instances under the given scope
# $get_scope.pl scope_tree.txt top.inst1.inst2
# Author: Ramel Eshed

open(FILE, $ARGV[0]);

@scope = split(/\./, $ARGV[1]);
#@scope = map { quotemeta($_) } @scope;
$l_off = 0;
$r_off = 0;

while (<FILE>) {
    next if not /[+-]-/;
    $off = $-[0];
    last if $off < $l_off;
    next if $off > $r_off;
    if (/\(/) { 
        $r_off = $off;
    }
    else {
        $r_off = $off + 2;
        next;
    }
    if (@scope) {
        if (/^\s*[+-]-$scope[0]/) {
            shift @scope;
            $l_off = $off + 2;
            $r_off = $l_off;
        }
    }
    else {
        /([+-])-(\S*)\s+\((.*)\)/;
        print "$1 $2 $3\n";
    }
}
