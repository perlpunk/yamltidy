use strict;
use warnings;
use 5.010;
use Test::More;
use Test::Warnings qw/ :report_warnings /;

use FindBin '$Bin';
use YAML::Tidy;

my $cfg = YAML::Tidy::Config->new( configfile => "$Bin/../.yamltidy" );
my $yt = YAML::Tidy->new( cfg => $cfg );
my $yaml = <<'EOM';
block:   
 "seq" :
     - 1   
     - "true"
     - "3"
map:
     a:   &ONE 1   
     b  : *ONE
flow: [
        {
        "x":*ONE
        } ,
     ]  
EOM
my $exp = <<'EOM';
---
block:
  seq :
  - 1
  - "true"
  - "3"
map:
  a: &ONE 1
  b  : *ONE
flow: [
    {
      x: *ONE
    } ,
  ]
EOM

my $tidied = $yt->tidy($yaml);

is $tidied, $exp, "Basic tidy test";

done_testing;
