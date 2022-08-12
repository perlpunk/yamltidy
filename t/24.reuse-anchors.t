use strict;
use warnings;
use 5.010;
use Test::More;
use Test::Warnings qw/ :report_warnings /;

use FindBin '$Bin';
use YAML::Tidy;

my $cfg = YAML::Tidy::Config->new( configfile => "$Bin/data/configs/config21.yaml" );
my $yt = YAML::Tidy->new( cfg => $cfg );

my ($yaml, $tidied, $exp);

$yaml = do { open my $fh, '<', "$Bin/data/reused-anchors-1.yaml" or die $!; local $/; <$fh> };
$exp = do { open my $fh, '<', "$Bin/data/reused-anchors-1.tdy.yaml" or die $!; local $/; <$fh> };

$tidied = $yt->tidy($yaml);

is $tidied, $exp, "Serialize reused anchors";


$yaml = do { open my $fh, '<', "$Bin/data/reused-anchors-2.yaml" or die $!; local $/; <$fh> };
$exp = do { open my $fh, '<', "$Bin/data/reused-anchors-2.tdy.yaml" or die $!; local $/; <$fh> };

$tidied = $yt->tidy($yaml);

is $tidied, $exp, "Serialize additional reused anchors";

done_testing;
