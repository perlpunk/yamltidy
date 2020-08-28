#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use autodie qw/ open opendir mkdir /;
use FindBin '$Bin';
use YAML::PP::Highlight;
use YAML::PP::Parser;
use YAML::Tidy;

$|++;
my $datadir = "$Bin/generated";
opendir(my $dh, $datadir);
my @ids = sort grep { m/^[A-Z0-9]{4}$/ } readdir $dh;
closedir $dh;

my $table = qq{<table class="highlight">};
for my $id (@ids) {
    print "\r======== $id";
    my @names = qw/ in c0 c1 c2 c3 /;
    $table .= qq{<tr><td>$id</td>};
    for my $i (0 .. $#names) {
        my $name = $names[ $i ];
        my $file = "$datadir/$id/$name.yaml";
        open my $fh, '<:encoding(UTF-8)', $file;
        my $yaml = do { local $/; <$fh> };
        close $fh;
        my $html = YAML::Tidy->highlight($yaml, 'html');
        $table .= qq{<td class="yaml"><pre>$html</pre></td>\n};
    }
    $table .= qq{</tr>\n};
}
say "\ndone";
$table .= qq{</table>};

my $html = <<"EOM";
<html>
<head>
<title>YAML Tidy Highlighted</title>
<link rel="stylesheet" type="text/css" href="css/main.css">
<link rel="stylesheet" type="text/css" href="css/yaml.css">
<body>
$table
</body>
</html>
EOM
open my $fh, '>:encoding(UTF-8)', "html/index.html";
print $fh $html;
close $fh;
