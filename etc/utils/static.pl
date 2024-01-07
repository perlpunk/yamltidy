#!/usr/bin/perl
use warnings;
use v5.20;
use experimental qw/ signatures /;
use FindBin '$Bin';

my $dir = "$Bin/../html";
my $example_dir = "$Bin/../html-examples";
my $generated = "$Bin/generated";

open my $fh, "$dir/index.html";
my $html = do { local $/; <$fh> };
close $fh;

$html =~ s#\$\{([\w./-]+)\}#example($1)#ge;

mkdir "$generated/static";
open $fh, '>:encoding(UTF-8)', "$generated/static/index.html" or die $!;
print $fh $html;
close $fh;

sub example($path) {
    my $highlighted = qx{perl $Bin/yaml2html.pl $example_dir/$path};
    return $highlighted;
}

