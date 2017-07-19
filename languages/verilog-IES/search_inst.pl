#!/usr/bin/perl
# get sub tree of scope tree for Vim's projective plugin.
# Author: Eran Meisner

use strict;
use warnings;

our @scope_tree_lines;

sub main {
   &get_module_scope_tree($ARGV[0], $ARGV[1], $ARGV[2]);
}main;

sub get_module_scope_tree {
   my $file = shift;
   my $top_module = shift;
   my $module_name = shift;

   my @leaves_lines_in_use;
   my @lines_in_use;

   open(FH, $file) || die "can't open $file";
   @scope_tree_lines = <FH>;
   close FH;

   while (@scope_tree_lines && ($scope_tree_lines[0] !~ /\($top_module\)/)) {
      shift @scope_tree_lines;
   }

   #add leaves
   @leaves_lines_in_use = grep { $scope_tree_lines[$_] =~ /\($module_name\)/ } 0..$#scope_tree_lines;

   #add the top level in case there are leaves
   if (@leaves_lines_in_use) {
      push  @lines_in_use, 0;
   }

   #add all parents
   foreach my $line_index (@leaves_lines_in_use) {
      @lines_in_use = &add_parents($line_index, &get_line_indenet_size($scope_tree_lines[$line_index]), @lines_in_use);
   }

   #prepare for output
   @lines_in_use = sort {$a <=> $b} @lines_in_use;

   foreach my $line_index (@lines_in_use) {
      if ($scope_tree_lines[$line_index]  =~ /\($module_name\)/) {
         $scope_tree_lines[$line_index] =~ s/\+/\-/;
      }

      print $scope_tree_lines[$line_index];
   }
}

sub get_line_indenet_size {
   my $line = shift;

   $line =~ /^(\s*)/;
   return length($1);
}

sub add_parents {
   my $line_index = shift;
   my $indent_size = shift;
   my @lines_in_use = @_;

   my $parent_line_index = $line_index - 1;

   if (grep { $line_index eq $_ } @lines_in_use) {
      return @lines_in_use;
   } else {
      push @lines_in_use, $line_index;

      #search for parent while ignoring all brothers
      while (&get_line_indenet_size($scope_tree_lines[$parent_line_index]) >= $indent_size) {
         $parent_line_index--;
      }
      return &add_parents($parent_line_index, &get_line_indenet_size($scope_tree_lines[$parent_line_index]), @lines_in_use);
   }
}
