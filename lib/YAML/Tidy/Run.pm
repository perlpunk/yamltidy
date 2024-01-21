# ABSTRACT: yamltidy runner
use strict;
use warnings;
use v5.20;
use experimental qw/ signatures /;
package YAML::Tidy::Run;

our $VERSION = '0.000'; # VERSION

use YAML::Tidy;
use YAML::Tidy::Config;
use YAML::LibYAML::API;
use Getopt::Long::Descriptive;
use Encode;
use File::Find qw/ find /;
use File::Glob qw/ bsd_glob /;
use Cwd qw/ cwd /;

my @options = (
    'yamltidy %o file',
    [ 'config-file|c=s' => 'Config file' ],
    [ 'config-data|d=s' => 'Configuration as a string' ],
    [ 'inplace|i' => 'Edit file inplace' ],
    [ 'debug' => 'Debugging output' ],
    [ 'partial' => 'Input is only a part of a YAML file' ],
    [ 'indent=i' => 'Override indentation spaces from config' ],
    [ 'batch|b=s' => 'Tidy all files. Needs a directory name or "-" for filenames passed via STDIN' ],
    [ 'verbose|v' => 'Output information' ],
    [],
    [ 'help|h', "print usage message and exit", { shortcircuit => 1 } ],
    [ 'version', "Print version information", { shortcircuit => 1 } ],
);

sub new($class, %args) {
    my ($opt, $usage) = describe_options(@options);
    my $cfg = YAML::Tidy::Config->new(
        configfile => $opt->config_file,
        configdata => $opt->config_data,
        indentspaces => $opt->indent,
    );
    my $yt = YAML::Tidy->new(
        cfg => $cfg,
        partial => $opt->partial,
    );
    my $self = bless {
        opt => $opt,
        stdin => $args{stdin} || \*STDIN,
        tidy => $yt,
        usage => $usage,
    }, $class;
}

sub _output($self, $str) {
    print $str;
}

sub run($self) {
    my $opt = $self->{opt};
    my $usage = $self->{usage};
    $self->_output($usage->text), return if $opt->help;
    my @versions = (
        YAML::Tidy->VERSION, YAML::PP->VERSION,
        YAML::LibYAML::API->VERSION,
        YAML::LibYAML::API::XS::libyaml_version
    );
    if ($opt->version) {
        $self->_output(sprintf <<'EOM', @versions);
    yamltidy:           %s
    YAML::PP:           %s
    YAML::LibYAML::API: %s
    libyaml:            %s
EOM
        return;
    }

    if (my $path = $opt->batch) {
        unless ($opt->inplace) {
            die "--batch currently requires --inplace\n";
        }
        if ($path eq '-') {
            $self->_process_files_stdin;
            return;
        }
        $self->_process_path($path);
        return;
    }
    my ($file) = @ARGV;
    unless (defined $file) {
        $self->_output($usage->text);
        return;
    }

    if ($file eq '-') {
        $self->_process_stdin;
        return;
    }

    $self->_process_file($file);
}

sub _process_path($self, $path) {
    unless (-d $path) {
        die "Directory '$path' does not exist\n";
    }
    my $match = $self->{tidy}->cfg->{files_match};
    my $ignore_dirs = $self->{tidy}->cfg->{files_ignore};
    my @dirs;
    my @found;
    find(sub { push @dirs, $File::Find::name if -d $_ }, $path);
    my $orig = cwd;
    for my $dir (@dirs) {
        next if grep { $dir =~ m{^\Q$path/\Q$_} } @$ignore_dirs;
        chdir $dir;
        local $" = ',';
        my @files = grep { -e $_ } bsd_glob "{@$match}";
        push @found, map { "$dir/$_" } @files;
        chdir $orig;
    }
    for my $file (sort @found) {
        $self->_process_file($file);
    }
}

sub _process_files_stdin($self) {
    my $opt = $self->{opt};
    my $in = $self->{stdin};
    while (my $file = <$in>) {
        chomp $file;
        $self->_process_file($file);
    }
    return;
}

sub _process_file($self, $file) {
    my $opt = $self->{opt};
    my $yt = $self->{tidy};
    my $changed = 0;
    open my $fh, '<:encoding(UTF-8)', $file or die "Could not open '$file': $!";
    my $yaml = do { local $/; <$fh> };
    close $fh;

    $opt->debug and $self->_before($file, $yaml);

    my $out = eval { $yt->tidy($yaml) };
    if (my $err = $@) {
        $self->_error(sprintf "Processing '%s' failed: %s", $file, $err);
        return 1;
    }

    if ($out ne $yaml) {
        $changed = 1;
    }
    if ($opt->inplace) {
        $changed and $self->_write_file($file, $out);
    }
    else {
        $opt->debug or $self->_output(encode_utf8 $out);
    }
    $opt->debug and $self->_after($file, $out);
    $self->_info(sprintf "Processed '%s' (%s)", $file, $changed ? 'changed' : 'unchanged');
}

sub _info($self, $msg) {
    $self->{opt}->verbose and $self->_output("[info] $msg\n");
}
sub _error($self, $msg) {
    $self->{opt}->verbose and $self->_output("[info] $msg\n");
}

sub _write_file($self, $file, $out) {
    open my $fh, '>:encoding(UTF-8)', $file or die "Could not open '$file' for writing: $!";
    print $fh $out;
    close $fh;
}

sub _process_stdin($self) {
    my $opt = $self->{opt};
    my $yt = $self->{tidy};
    my $in = $self->{stdin};
    my $yaml = decode_utf8 do { local $/; <$in> };

    $opt->debug and $self->_before('-', $yaml);

    my $out = $yt->tidy($yaml);

    if ($opt->debug) {
        $self->_after('-', $out);
    }
    else {
        $self->_output(encode_utf8 $out);
    }
}

sub _before($self, $file, $yaml) {
    my $yt = $self->{tidy};
    $self->_output( "# Before: ($file)\n");
    $self->_output(encode_utf8 $yt->highlight($yaml));
}

sub _after($self, $file, $yaml) {
    my $yt = $self->{tidy};
    $self->_output("# After: ($file)\n");
    $self->_output(encode_utf8 $yt->highlight($yaml));
}
1;
