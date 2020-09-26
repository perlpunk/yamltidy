# ABSTRACT: Tidy YAML files
use strict;
use warnings;
use v5.20;
use experimental qw/ signatures /;
package YAML::Tidy;

our $VERSION = '0.000'; # VERSION

use YAML::Tidy::Node;
use YAML::Tidy::Config;
use YAML::LibYAML::API::XS;
use YAML::PP::Common qw/
    YAML_PLAIN_SCALAR_STYLE YAML_SINGLE_QUOTED_SCALAR_STYLE
    YAML_DOUBLE_QUOTED_SCALAR_STYLE YAML_LITERAL_SCALAR_STYLE
    YAML_FOLDED_SCALAR_STYLE
    YAML_FLOW_SEQUENCE_STYLE YAML_FLOW_MAPPING_STYLE
/;
use YAML::PP::Parser;
use YAML::PP::Highlight;
use Data::Dumper;

use constant DEBUG => $ENV{YAML_TIDY_DEBUG} ? 1 : 0;

sub new($class, %args) {
    my $cfg = delete $args{cfg} || YAML::Tidy::Config->new();
    my $self = bless {
        partial => delete $args{partial},
        cfg => $cfg,
    }, $class;
    return $self;
}

sub cfg($self) { $self->{cfg} }

sub tidy($self, $yaml) {
    local $Data::Dumper::Sortkeys = 1;
    my @lines = split /\n/, $yaml, -1;
    my $tree = $self->_tree($yaml, \@lines);
    $self->{lines} = \@lines;
    $self->_process(undef, $tree);
    $yaml = join "\n", @{ $self->{lines} };
    return $yaml;
}

sub _process($self, $parent, $node) {
    my $type = $node->{type} || '';
    if ($node->{flow}) {
        return;
    }
    my $level = $node->{level};
    my $indent = $self->cfg->indent;
    my $lines = $self->{lines};
    return unless @$lines;
    my $indenttoplevelscalar = 1;
    my $trimtrailing = $self->cfg->trimtrailing;

    my $col = $node->indent;
    my $lastcol = $parent ? $parent->indent : -99;
    my $realindent = $col - $lastcol;
    my $startline = $node->line;
    my $line = $lines->[ $startline ];
    unless (defined $line) {
        die "Line $startline not found";
    }
    my $before = substr($line, 0, $col);

    my $pre = $parent ? $parent->pre($node) : undef;
    my $start = $node->start;
    if ($pre and $trimtrailing) {
        if (defined $pre->{line} and $pre->{line} <= $start->{line}) {
            my ($from, $to) = ($pre->{line}, $start->{line});
            $self->_trim($from, $to);
        }
        if ($type eq 'DOC') {
        }
    }

    if ($node->is_collection) {
        my $ignore_firstlevel = ($self->{partial} and $level == 0);
        if ($level < 0 or $ignore_firstlevel) {
            for my $c (@{ $node->{children} }) {
                $self->_process($node, $c);
            }
            return;
        }

        if ($level == 0) {
            $indent = 0;
        }
        if ($type eq 'MAP') {
            if ($before =~ tr/ //c) {
                if ($indent == 1) {
                    $indent = 2;
                }
            }
        }
        elsif ($type eq 'SEQ') {
            if ($before =~ tr/ //c) {
                if ($indent == 1) {
                    $indent = 2;
                }
            }
            else {
                if ($parent->{type} eq 'MAP' and not $node->{index} % 2) {
                    # zero indented sequence
                    if ($indent == 1) {
                        $indent = 2;
                    }
                    $indent -= 2;
                }
            }

        }
        my $diff = $indent - $realindent;
#        warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$diff], ['diff']);
        if ($diff) {
            $self->_fix_indent($node, $diff, $col);
            $node->fix_node_indent($diff);
        }
        for my $c (@{ $node->{children} }) {
            $self->_process($node, $c);
        }
        return;
    }
    else {
        my $multiline = $node->multiline;
        if ($parent->{type} eq 'MAP' and ($node->{index} % 2 and not $multiline)) {
            return;
        }
        if ($node->empty_scalar) {
            return;
        }
        my $endline = $node->{end}->{line} - 1;
        my $nextline = $node->{nextline};
        my $new_indent = $parent->indent + $indent;

        my $new_spaces = ' ' x $new_indent;
        if ($node->{name} eq 'alias_event') {
            return;
        }
        my $block = ($node->{style} eq YAML_LITERAL_SCALAR_STYLE
            or $node->{style} eq YAML_FOLDED_SCALAR_STYLE);
        my $explicit_indent = 0;
        if ($node->{style} != YAML_PLAIN_SCALAR_STYLE) {
            while ($startline < $endline) {
                if ($trimtrailing) {
                    $self->_trim($startline, $startline);
                }
                if ($node->{style} != YAML_PLAIN_SCALAR_STYLE and $lines->[ $startline ] =~ m/(?:^|\t| )([>|"'])/g) {
                    my $pos = pos $lines->[ $startline ];
                    $col = $pos - 1;
                    last;
                }
                $startline++;
            }
        }
        my $line = $lines->[ $startline ];
        my $before = substr($line, 0, $col);
        if ($block) {
            my ($ind) = substr($line, $col) =~ m/^[|>][+-]?([0-9]*)/;
            # leave alone explicitly indented block scalars
            return if $ind;

            if ($before =~ tr/ \t//c) {
                # same line as key
                $before =~ s/[\t ]+$/ /;
                $line = $before . substr($line, $col);
                $lines->[ $startline ] = $line;
                $startline++;
            }
            else {
                $lines->[ $startline ] =~ s/^ +/$new_spaces/;
                $startline++;
            }
            while ($startline < $endline and $lines->[ $startline ] !~ tr/ //c) {
                if ($trimtrailing) {
                    $self->_trim($startline, $startline);
                }
                $startline++;
            }
            if ($nextline > $endline + 1) {
                $endline = $nextline - 1;
            }
            my @slice = @$lines[$startline .. $endline ];
            my ($sp) = $lines->[ $startline ] =~ m/^( *)/;
            if (length($sp) != $new_indent) {
                for my $line (@slice) {
                    unless (length $line) {
                        next;
                    }
                    if ($line !~ tr/ //c and length($line) <= length($sp)) {
                        if ($trimtrailing) {
                            $line = '';
                        }
                        next;
                    }
                    if ($line =~ m/^( *)\#/) {
                        my $cindent = length $1;
                        my $diff = $new_indent - length $sp;
                        $cindent += $diff;
                        if ($diff > 0) {
                            $line = (' ' x $diff) . $line;
                        }
                        elsif ($diff < 0) {
                            if ($cindent < 0) {
                                $cindent = 0;
                            }
                            $new_spaces = ' ' x $cindent;
                            $line =~ s/^ */$new_spaces/;
                        }
                    }
                    else {
                        $line =~ s/^$sp/$new_spaces/;
                    }
                }
                @$lines[$startline .. $endline ] = @slice;
            }
            elsif ($trimtrailing) {
                for my $line (@slice) {
                    if ($line !~ tr/ //c and length($line) <= length($sp)) {
                        $line = '';
                    }
                }
                @$lines[$startline .. $endline ] = @slice;
            }
        }
        elsif ($node->{style} == YAML_PLAIN_SCALAR_STYLE or
                $node->{style} == YAML_SINGLE_QUOTED_SCALAR_STYLE or
                $node->{style} == YAML_DOUBLE_QUOTED_SCALAR_STYLE) {
            $endline = $node->{end}->{line};
            if ($before =~ tr/ //c) {
                # same line as key
                if ($trimtrailing) {
                    $lines->[ $startline ] =~ s/[\t ]+$//;
                }
                $startline++;
            }
            return if $startline >= @$lines;
            my @slice = @$lines[$startline .. $endline ];
            if ($level == 0 and not $indenttoplevelscalar) {
                $new_spaces = ' ' x ($new_indent - $indent);
            }
            for my $line (@slice) {
                if ($line !~ tr/ //c) {
                    if ($trimtrailing) {
                        $line = '';
                    }
                }
                else {
                    $line =~ s/^[\t ]*/$new_spaces/;
                }
                if ($trimtrailing) {
                    $line =~ s/[\t ]+$//;
                }
            }
            @$lines[$startline .. $endline ] = @slice;
        }
    }
}

sub _trim($self, $from, $to) {
    my $lines = $self->{lines};
    for my $line (@$lines[ $from .. $to ]) {
        $line =~ s/[\t ]+$//;
    }
}

sub _fix_indent($self, $node, $fix, $offset) {
#    warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$fix], ['fix']);
#    warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$offset], ['offset']);
    $offset ||= 0;
    my $startline = $node->line;
    my $lines = $self->{lines};
    my $endline = $node->{endline};
    $endline--; # if $endline >= @$lines;
    my @slice = @$lines[$startline .. $endline];
    for my $line (@slice) {
        next unless length $line;
        if ($fix < 0) {
            my $offset = $offset;
            my $fix = -$fix;
            if ($offset > length $line) {
                $offset = -1 + length $line;
            }
            if ($line =~ tr/ //c) {
                if ($line =~ m/^ *\#/) {
                    $line =~ s/ {1,$fix}//;
                    next;
                }
            }
            else {
                $line =~ s/ {1,$fix}//;
                next;
            }
            my $before = substr($line, 0, $offset);
            $before =~ s/ {$fix,$fix}$//;
            $line = $before . substr($line, $offset);
        }
        else {
            unless ($line =~ tr/ //c) {
                next;
            }
            substr($line, $offset, 0, ' ' x $fix);
        }
    }
    @$lines[$startline .. $endline] = @slice;
}

sub _tree($self, $yaml, $lines) {
    my $events = $self->_parse($yaml);
    $self->{events} = $events;
    my $first = shift @$events;
    my $end = pop @$events;
    my @stack;

    my $level = -1;
    my $docs = YAML::Tidy::Node::Collection->new(
        type => 'STR',
        children => [],
        indent => -1,
        line => 0,
        level => $level,
        start => YAML::Tidy::Node::Collection->new(%$first),
        end => YAML::Tidy::Node::Collection->new(%$end),
    );
    my $ref = $docs;
    my $id = 0;
    my $flow = 0;
    for my $i (0 .. $#$events) {
        my $event = $events->[ $i ];
        my $name = $event->{name};
        $id++;

        my $type;
        if ($name =~ m/document_start/) {
            $type = 'DOC';
        }
        elsif ($name =~ m/sequence_start/) {
            $type = 'SEQ';
        }
        elsif ($name =~ m/mapping_start/) {
            $type = 'MAP';
        }

        $event->{id} = $id;
        if ($name =~ m/_start_event/) {
            $event->{level} = $level;
            if ($name eq 'sequence_start_event') {
                # inconsistency in libyaml events?
                my $col = $event->{end}->{column};
                if ($col > 0) {
                    my $line = $lines->[ $event->{end}->{line} ];
                    my $chr = substr($line, $col - 1, 1);
                    if ($chr eq '-') {
                        $event->{end}->{column}--;
                    }
                }
            }
            if ($flow or ($event->{style} // -1) == YAML_FLOW_SEQUENCE_STYLE
                or ($event->{style} // -1) == YAML_FLOW_MAPPING_STYLE) {
                $flow++;
            }
            my $node = YAML::Tidy::Node::Collection->new(
                children => [],
                type => $type,
                level => $level,
                start => $event,
                flow => $flow,
            );
            push @{ $ref->{children} }, $node;
            $ref->{elements}++;
            $node->{index} = $ref->{elements};
            push @stack, $ref;
            $ref = $node;
            $level++;
        }
        elsif ($name =~ m/_end_event/) {
            my $last = pop @stack;

            $ref->{endline} = $event->{end}->{line};
            $ref->{end} = $event;

            $ref = $last;

            $level--;
            $event->{level} = $level;
            $flow-- if $flow;
        }
        else {
            $event = YAML::Tidy::Node::Scalar->new(%$event);
            $ref->{elements}++;
            $event->{index} = $ref->{elements};
            $event->{level} = $level;
            push @{ $ref->{children} }, $event;
        }
        $event->{nextline} = -1;
        if ($i < $#$events) {
            my $next = $events->[ $i + 1 ];
            my $nextline = $next->{start}->{line};
            $event->{nextline} = $nextline;
        }
        _pp($event) if DEBUG;
    }
    $self->{tree} = $docs;
    return $docs;
}

sub _parse($self, $yaml) {
    my @events;
    YAML::LibYAML::API::XS::parse_string_events($yaml, \@events);
    return \@events;
}

sub _pp($event) {
    my $name = $event->{name};
    my $level = $event->{level};
    $name =~ s/_event$//;
    my $fmt = '%2d %-10s) <L %2d C %2d> <L %2d C %2d> %-14s';
    my $indent = $level*2+2;
    my $lstr = (' ' x $indent) . $level;
    my @args = (
        $event->{id}, $lstr,
        $event->{start}->{line}, $event->{start}->{column},
        $event->{end}->{line}, $event->{end}->{column},
        $name,
    );
    if ($name =~ m/scalar|alias/) {
        local $Data::Dumper::Useqq = 1;
        my $str = Data::Dumper->Dump([$event->{value}], ['value']);
        chomp $str;
        $str =~ s/^\$value = //;
        $fmt .= " %s";
        push @args, $str;
    }
    elsif ($name =~ m/end/) {
    }
    else {
    }
    $fmt .= "\n";
    printf $fmt, @args;
}

sub highlight($self, $yaml, $type = 'ansi') {
    my ($error, $tokens) = YAML::PP::Parser->yaml_to_tokens(string => $yaml);
    if ($error) {
        $tokens = [];
        my @lines = split m/(?<=\n)/, $yaml;
        for my $line (@lines) {
            if ($line =~ s/( +\n)//) {
                push @$tokens, { value => $line, name => 'PLAIN' };
                push @$tokens, { value => $1, name => 'TRAILING_SPACE' };
                next;
            }
            push @$tokens, { value => $line, name => 'PLAIN' };
        }
    }
    if ($type eq 'html') {
        return YAML::PP::Highlight->htmlcolored($tokens);
    }
    return YAML::PP::Highlight->ansicolored($tokens);
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

YAML::Tidy - Clean YAML files

=head1 SYNOPSIS

    % cat in.yaml
    a:
        b:
         c: d
    % yamltidy in.yaml
    a:
      b:
        c: d

For documentation see L<https://github.com/perlpunk/yamltidy>

=head1 DESCRIPTION

yamltidy can automatically fix indentation in your YAML files.

For more information, see L<https://github.com/perlpunk/yamltidy>.

=head1 METHODS

=over

=item C<new>

    my $yt = YAML::Tidy->new;

=item C<tidy>

    my $outyaml = $yt->tidy($inyaml);

=item C<highlight>

    my $ansicolored = $yt->highlight($yaml, 'ansi');
    my $html = $yt->highlight($yaml, 'html');

=item C<cfg>

    my $cfg = $yt->cfg;

Return L<YAML::Tidy::Config>

=back

=head1 SEE ALSO

=over

=item yamllint L<https://yamllint.readthedocs.io/en/stable/>

=item perltidy L<Perl::Tidy>

=item L<YAML::LibYAML::API>

=item L<https://github.com/yaml/libyaml>

=item L<https://www.yaml.info/>

=back

=head1 COPYRIGHT AND LICENSE

Copyright 2020 by Tina Müller

This library is free software and may be distributed under the same terms
as perl itself.

=cut
