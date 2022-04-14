#!/usr/bin/env perl
use strict;
use warnings;
use v5.20;
use experimental qw/ signatures /;
use autodie qw/ open opendir mkdir /;
use FindBin '$Bin';
use lib "$Bin/../../lib";

use YAML::PP::Highlight;
use YAML::PP::Parser;
use YAML::Tidy;

my @configs = map {
    open my $fh, '<', "$Bin/../../t/data/configs/config$_.yaml";
    my $yaml = do { local $/; <$fh> };
    close $fh;
    my $html = YAML::Tidy->highlight($yaml, 'html');
    $html;
} (0 .. 17);

$|++;
my $url = 'https://github.com/yaml/yaml-test-suite/blob/main/src';
my %types = (
    indent => {
        configs => [0 .. 3],
    },
    header1 => {
        configs => [5 .. 8],
    },
    header2 => {
        configs => [9 .. 12],
    },
    seqindent => {
        configs => [14 .. 17],
    },
);

taglist();

for my $type (sort keys %types) {
    my $def = $types{ $type };
    my $configs = $def->{configs};
    my $datadir = "$Bin/generated/$type";
    opendir(my $dh, $datadir);
    my @ids = sort grep { m/^[A-Z0-9]{4}$/ } readdir $dh;
    closedir $dh;
    html($type, \@ids, $configs);
}

sub taglist() {
    my $file = "$Bin/generated/tags.yaml";
    open my $fh, '<encoding(UTF-8)', $file or die $!;
    my $yaml = do { local $/; <$fh> };
    close $fh;
    # oops - YAML::PP 0.026 produces a trailing space in flow collections
    $yaml =~ s/ +$//mg;

    my $highlighted = YAML::Tidy->highlight($yaml, 'html');
    $highlighted =~ s{<span class="(?:default|singlequoted)">'?([0-9A-Z]{4})'?</span>}
                     {<a href="$url/$1.yaml">$1</a>}g;

    my $html = <<"EOM";
<html>
<head>
<title>YAML Tidy Examples - Tag List</title>
<link rel="stylesheet" type="text/css" href="css/main.css">
<link rel="stylesheet" type="text/css" href="css/yaml.css">
<body>
<pre class="taglist">$highlighted</pre>
</body>
</html>
EOM
    open $fh, '>:encoding(UTF-8)', "$Bin/../../etc/html/taglist.html";
    print $fh $html;
    close $fh;
}

sub html($type, $ids, $configs) {
    my $table = qq{<table class="highlight">};
    $table .= qq{<tr><th>ID</th><th><span class="ytitle">Input</span> / <span class="xtitle">Config</span></th>};
    $table .= qq{<th align="left"><pre>$configs[ $_ ]</th>\n} for @$configs;
    $table .= qq{</tr>};
    for my $id (@$ids) {
        print "\r======== $id";
        my $datadir = "$Bin/generated/$type";
        my @configs = map { "c$_" } @$configs;
        my @names = ('in', @configs);
        $table .= qq{<tr><td class="id" id="id$id"><pre><b><a href="#id$id">$id</a></b></pre></td>};
        for my $i (0 .. $#names) {
            my $name = $names[ $i ];
            my $file = "$datadir/$id/$name.yaml";
            open my $fh, '<:encoding(UTF-8)', $file;
            my $yaml = do { local $/; <$fh> };
            close $fh;
            my $html = YAML::Tidy->highlight($yaml, 'html');
            my $class = 'yaml';
            $class .= ' input' if $name eq 'in';
            $table .= qq{<td class="$class"><pre>$html</pre></td>\n};
        }
        $table .= qq{</tr>\n};
    }
    say "\ndone";
    $table .= qq{</table>};

    my $html = <<"EOM";
<html>
<head>
<title>YAML Tidy Examples - Group $type</title>
<link rel="stylesheet" type="text/css" href="css/main.css">
<link rel="stylesheet" type="text/css" href="css/yaml.css">
<body>
$table
</body>
</html>
EOM
    open my $fh, '>:encoding(UTF-8)', "$Bin/../../etc/html/$type.html";
    print $fh $html;
    close $fh;
}
