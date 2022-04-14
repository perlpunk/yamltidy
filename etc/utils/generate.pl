#!/usr/bin/env perl
use strict;
use warnings;
use v5.20;
use experimental qw/ signatures /;
use autodie qw/ open opendir mkdir /;
use FindBin '$Bin';
use lib "$Bin/../../lib";

use File::Copy qw/ copy /;
use YAML::Tidy;
$|++;

my $datadir = "$Bin/generated";
mkdir $datadir unless -d $datadir;
my $ts = "$Bin/../../yts";
opendir(my $dh, $ts);
my @ids = grep { m/^[A-Z0-9]{4}$/ } readdir $dh;
closedir $dh;

my @skip;
open my $fh, '<', "$Bin/../../t/libyaml.skip";
chomp(@skip = <$fh>);
close $fh;
@skip = grep {
    length $_ and not m/^ *#/
} @skip;

my %skip;
@skip{ @skip } = (1) x @skip;
my @valid;
for my $id (sort @ids) {
    next if -e "$ts/$id/error";
    next if $skip{ $id };
    push @valid, $id;
}

my %types = (
    indent => {
        ids => \@valid,
        configs => [0 .. 3],
    },
    header1 => {
        ids => \@valid,
        configs => [5 .. 8],
    },
    header2 => {
        ids => \@valid,
        configs => [9 .. 12],
    },
    seqindent => {
        ids => \@valid,
        configs => [14 .. 17],
    },
);

my @yt = map {
    my $cfg = YAML::Tidy::Config->new( configfile => "$Bin/../../t/data/configs/config$_.yaml" );
    YAML::Tidy->new( cfg => $cfg );
} (0 .. 17);

for my $type (sort keys %types) {
    my $def = $types{ $type };
    my $ids = $def->{ids};
    my $configs = $def->{configs};
    generate($type, $ids, $configs);
}

sub generate($type, $ids, $configs) {
    say "\n==== $type";
    my $dir = "$datadir/$type";
    mkdir $dir unless -d $dir;

    for my $id (@$ids) {
        print "\r=========== $id";
        my $in = "$ts/$id/in.yaml";
        my $dir = "$dir/$id";
        mkdir $dir unless -d $dir;
        copy $in, "$dir/in.yaml";
        open(my $fh, '<:encoding(UTF-8)', $in);
        my $yaml = do { local $/; <$fh> };
        close $fh;
        for my $i (@$configs) {
            my $yt = $yt[ $i ];
            my $out = $yt->tidy($yaml);
            open my $fh, '>:encoding(UTF-8)', "$dir/c$i.yaml";
            print $fh $out;
            close $fh;
        }
    }
}
say "\ndone";
