#!/usr/bin/env perl
# Analyze test cases from https://github.org/yaml/yaml-test-suite
# What kind of nodes / syntax elements are they using?
use strict;
use warnings;
use v5.20;
use experimental qw/ signatures /;
use autodie qw/ open opendir mkdir /;
use FindBin '$Bin';
use lib "$Bin/../../lib";

use YAML::PP::Common qw/
    YAML_ANY_SCALAR_STYLE YAML_PLAIN_SCALAR_STYLE
    YAML_SINGLE_QUOTED_SCALAR_STYLE YAML_DOUBLE_QUOTED_SCALAR_STYLE
    YAML_LITERAL_SCALAR_STYLE YAML_FOLDED_SCALAR_STYLE

    YAML_BLOCK_MAPPING_STYLE YAML_FLOW_MAPPING_STYLE
    YAML_BLOCK_SEQUENCE_STYLE YAML_FLOW_SEQUENCE_STYLE

    PRESERVE_FLOW_STYLE
/;
use YAML::Tidy;

use constant {
    FLOW             => 'flow',
    BLOCK_MAPPING    => 'block-mapping',
    FLOW_MAPPING     => 'flow-mapping',
    BLOCK_SEQUENCE   => 'block-sequence',
    FLOW_SEQUENCE    => 'flow-sequence',
    ANCHOR           => 'anchor',
    ALIAS            => 'alias',
    TAG              => 'tag',
    MULTI_DOCUMENT   => 'multi-document',
    TOP_LEVEL_SCALAR => 'top-level-scalar',
    EMPTY_PLAIN_KEY  => 'empty-plain-key',
    HEADER           => 'header',
    FOOTER           => 'footer',
    PLAIN            => 'plain',
    SINGLE           => 'single',
    DOUBLE           => 'double',
    LITERAL          => 'literal',
    FOLDED           => 'folded',
};

my $ts = "$Bin/../../yts";
my $datadir = "$Bin/generated";

my @skip;
open my $fh, '<', "$Bin/../../t/libyaml.skip";
chomp(@skip = <$fh>);
close $fh;
@skip = grep {
    length $_ and not m/^ *#/
} @skip;

my %skip;
@skip{ @skip } = (1) x @skip;

opendir(my $dh, $ts);
my @ids = grep { m/^[A-Z0-9]{4}$/ } readdir $dh;
closedir $dh;

my @valid;
for my $id (sort @ids) {
    if (-e "$ts/$id/error") {
        next;
    }
    next if $skip{ $id };
    push @valid, $id;
}
my %scalar_style_to_string = (
    YAML_PLAIN_SCALAR_STYLE() => 'plain',
    YAML_SINGLE_QUOTED_SCALAR_STYLE() => 'single',
    YAML_DOUBLE_QUOTED_SCALAR_STYLE() => 'double',
    YAML_LITERAL_SCALAR_STYLE() => 'literal',
    YAML_FOLDED_SCALAR_STYLE() => 'folded',
);


my $yt = YAML::Tidy->new;

$|++;
#@valid = @valid[0 .. 40];

my %tags;
for my $id (@valid) {
    my $in = "$ts/$id/in.yaml";
    print "=========== $id\r";
    open(my $fh, '<:encoding(UTF-8)', $in);
    my $yaml = do { local $/; <$fh> };
    close $fh;

    my $events = eval { $yt->_parse($yaml) };
    my $tags = analyze_events($events);
#    say "Tags: @$tags";
    push @{ $tags{ $_ } }, $id for @$tags;
}
for my $tag (sort keys %tags) {
    my $ids = $tags{ $tag };
    my $seq = YAML::PP->preserved_sequence($ids, style => YAML_FLOW_SEQUENCE_STYLE);
    $tags{ $tag } = $seq;
}

my $yp = YAML::PP->new(
    preserve => PRESERVE_FLOW_STYLE,
);
$yp->dump_file("$datadir/tags.yaml", \%tags);

say "\ndone";

sub analyze_events($events) {
    my @tags;
    my @stack;
    my $level = -1;
    my $anchors = 0;
    my $alias = 0;
    my $toplevel_scalar = 0;
    my $documents = 0;
    my $block_sequence = 0;
    my $flow_sequence = 0;
    my $block_mapping = 0;
    my $flow_mapping = 0;
    my $tag = 0;
    my $flow_level = 0;
    my $header = 0;
    my $footer = 0;
    my $empty_plain_key = 0;
    my %styles = map { $_ => 0 } qw/ plain single double literal folded /;
    my %levels;
    my %kinds;
    for my $event (@$events) {
        my $name = $event->{name};
        my $type;
        my $flow = 0;
        if ($name =~ m/_start_event/) {
            $kinds{ $level } = $name =~ s/_start_event//r;
            $levels{ $level }++;
        }
        elsif ($name =~ m/_end_event/) {
            $level--;
        }
        if ($name eq 'document_start_event') {
            $documents++;
            $header++ unless $event->{implicit};
        }
        elsif ($name eq 'document_end_event') {
            $footer++ unless $event->{implicit};
        }
        elsif ($name eq 'scalar_event') {
            $type = 'VAL';
            $levels{ $level }++;
            if ($level == 1) {
                $toplevel_scalar++;
            }
            my $style = $event->{style};
            my $val = $event->{value};
            if ($kinds{ $level - 1 } eq 'mapping' and $levels{ $level } % 2 and not length $val) {
                $empty_plain_key++;
            }
            $styles{ $scalar_style_to_string{ $style } }++;
        }
        elsif ($name eq 'alias_event') {
            $levels{ $level }++;
            $type = 'ALI';
            $alias++;
        }
        elsif ($name eq 'sequence_start_event') {
            $type = 'SEQ';
            if ($event->{style} == YAML_FLOW_SEQUENCE_STYLE) {
                $flow = 1;
                $flow_sequence++;
                $flow_level++;
            }
            else {
                $block_sequence++;
            }
        }
        elsif ($name eq 'mapping_start_event') {
            $type = 'MAP';
            if ($event->{style} == YAML_FLOW_MAPPING_STYLE) {
                $flow = 1;
                $flow_mapping++;
                $flow_level++;
            }
            else {
                $block_mapping++;
            }
        }
        if (defined $event->{tag}) {
            $tag++;
        }
        if (defined $event->{anchor}) {
            $anchors++;
        }
        if ($flow) {
            $flow_level--;
        }
        if ($name =~ /start/) {
            $level++;
        }
    }
    if ($header) { push @tags, HEADER }
    if ($footer) { push @tags, FOOTER }
    if ($anchors) { push @tags, ANCHOR }
    if ($alias) { push @tags, ALIAS }
    if ($tag) { push @tags, TAG }
    if ($toplevel_scalar) { push @tags, TOP_LEVEL_SCALAR }
    if ($empty_plain_key) { push @tags, EMPTY_PLAIN_KEY }
    if ($styles{plain}) { push @tags, PLAIN }
    if ($styles{single}) { push @tags, SINGLE }
    if ($styles{double}) { push @tags, DOUBLE }
    if ($styles{literal}) { push @tags, LITERAL }
    if ($styles{folded}) { push @tags, FOLDED }
    if ($documents > 1) { push @tags, MULTI_DOCUMENT }
    if ($block_mapping) { push @tags, BLOCK_MAPPING };
    if ($flow_mapping) { push @tags, FLOW_MAPPING };
    if ($block_sequence) { push @tags, BLOCK_SEQUENCE };
    if ($flow_sequence) { push @tags, FLOW_SEQUENCE };
    if ($flow_sequence or $flow_mapping) { push @tags, FLOW }
    return [ sort @tags ];
}
