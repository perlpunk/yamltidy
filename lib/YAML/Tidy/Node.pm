use strict;
use warnings;
use 5.010;
package YAML::Tidy::Node;

sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
    };
    return bless $self, $class;
}

sub pre {
    my ($self, $node) = @_;
    my $index = $node->{index} - 1;
    my $end;
    if ($index < 1) {
        $end = $self->{start}->{end};
    }
    else {
        my $previous = $self->{children}->[ $index -1 ];
        $end = $previous->end;
    }
    return $end;
}


package YAML::Tidy::Node::Collection;

use base 'YAML::Tidy::Node';

#sub is_scalar { 0 }

sub is_collection { 1 }

sub indent {
    my ($self) = @_;

    my $firstevent = $self->{start};
    if ($firstevent->{name} eq 'document_start_event') {
        return 0;
    }

    my $startcol = $firstevent->{end}->{column};
    return $startcol;
}

sub end {
    my ($self) = @_;
    return $self->{end}->{end};
}

sub start {
    my ($self) = @_;
    return $self->{start}->{start};
}

sub line {
    my ($self) = @_;

    my $contentstart = $self->contentstart;
    return $contentstart->{line};
}

sub contentstart {
    my ($self) = @_;
    my $firstevent = $self->{start};
    return $firstevent->{end};
}

sub fix_node_indent {
    my ($self, $fix) = @_;
    for my $e (@$self{qw/ start end /}) {
        for my $pos (@$e{qw/ start end /}) {
            $pos->{column} += $fix;
        }
    }
    for my $c (@{ $self->{children} }) {
        $c->fix_node_indent($fix);
    }
}


package YAML::Tidy::Node::Scalar;
use YAML::PP::Common qw/
    YAML_PLAIN_SCALAR_STYLE YAML_SINGLE_QUOTED_SCALAR_STYLE
    YAML_DOUBLE_QUOTED_SCALAR_STYLE YAML_LITERAL_SCALAR_STYLE
    YAML_FOLDED_SCALAR_STYLE
    YAML_FLOW_SEQUENCE_STYLE YAML_FLOW_MAPPING_STYLE
/;

use base 'YAML::Tidy::Node';

#sub is_scalar { 1 }

sub is_collection { 0 }

sub indent {
    my ($self) = @_;

    return $self->{start}->{column};
}

sub start {
    my ($self) = @_;
    return $self->{start};
}

sub end {
    my ($self) = @_;
    return $self->{end};
}


sub line {
    my ($self) = @_;
    my $contentstart = $self->contentstart;
    return $contentstart->{line};
}

sub contentstart {
    my ($self) = @_;
    return $self->{start};
}

sub multiline {
    my ($self) = @_;
    if ($self->{start}->{line} < $self->{end}->{line}) {
        return 1;
    }
    return 0;
}

sub empty_scalar {
    my ($self) = @_;
    my ($start, $end) = @$self{qw/ start end /};
    if ($start->{line} == $end->{line} and $start->{column} == $end->{column}) {
        return 1;
    }
    return 0;
}


sub fix_node_indent {
    my ($self, $fix) = @_;
    for my $pos (@$self{qw/ start end /}) {
        $pos->{column} += $fix;
    }
}


1;
