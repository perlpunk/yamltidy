#!/usr/bin/perl
use warnings;
use v5.20;
use experimental qw/ signatures /;
use YAML::PP::Parser;
use YAML::PP::Highlight;

my ($file) = @ARGV;

open my $fh, '<:encoding(UTF-8)', $file or die $!;
my $yaml = do { local $/; <$fh> };
close $fh;

my $html = highlight($yaml);
say $html;

sub highlight($yaml) {
    my ($error, $tokens) = YAML::PP::Parser->yaml_to_tokens( string => $yaml );

    my $high = YAML::PP::Highlight->htmlcolored($tokens);
    return qq{<div class="yaml-codebox"><pre>$high</pre></div>};
}

