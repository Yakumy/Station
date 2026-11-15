#!/usr/bin/perl

# Lists Omarchy themes and the still backgrounds each one offers, as JSON on stdout.
# Every directory is a positional argument. Theme and file names are data: they are
# only ever printed as JSON strings, never evaluated or passed to a shell.
#
# Arguments: user themes, Omarchy themes, user backgrounds, remembered backgrounds,
# current theme directory.
#
# Background order and the default choice mirror omarchy-theme-set: the user's
# backgrounds folder for the theme comes first, then the theme's own backgrounds,
# each sorted by path; the remembered choice wins, otherwise the first one does.

use strict;
use warnings;
use JSON::PP;

use constant MAX_THEMES => 256;
use constant MAX_BACKGROUNDS => 128;

my ($user_themes, $omarchy_themes, $user_backgrounds, $remembered, $current) = @ARGV;
die "usage\n" unless defined $current;

my $image = qr/\.(?:jpe?g|png|gif|bmp|webp)\z/i;

sub safe_name {
    my ($name) = @_;
    return defined $name && $name ne '' && $name !~ /\A[.-]/ && $name !~ m{[/<>\s\x00-\x1f\x7f]}
        && $name eq lc($name);
}

sub safe_path {
    my ($path) = @_;
    return defined $path && $path =~ m{\A/} && $path !~ /[\x00-\x1f\x7f]/;
}

sub entries {
    my ($directory) = @_;
    opendir(my $handle, $directory) or return ();
    my @names = grep { $_ ne '.' && $_ ne '..' } readdir($handle);
    closedir($handle);
    return sort @names;
}

# A theme cloned from a git repository is held to the files omarchy-theme-set stages
# from it: no symbolic link inside it is followed.
sub from_repo {
    my ($directory) = @_;
    return -d $directory && !-l $directory && -d "$directory/.git";
}

sub images {
    my ($directory, $no_links) = @_;
    my %found;
    return %found unless -d $directory;
    for my $name (entries($directory)) {
        my $path = "$directory/$name";
        next unless $name =~ $image && safe_path($path) && -f $path;
        next if $no_links && -l $path;
        $found{$name} = $path;
    }
    return %found;
}

sub label {
    my ($name) = @_;
    (my $label = $name) =~ s/(\A|-)([a-z])/$1\u$2/g;
    $label =~ s/-/ /g;
    return $label;
}

sub first_line {
    my ($path) = @_;
    return '' unless -f $path && -s $path < 4096;
    open(my $handle, '<', $path) or return '';
    my $line = <$handle> // '';
    close($handle);
    chomp($line);
    return $line;
}

my %names;
for my $root ($user_themes, $omarchy_themes) {
    for my $name (entries($root)) {
        $names{$name} = 1 if safe_name($name) && -d "$root/$name";
    }
}

my @themes;
for my $name (sort keys %names) {
    last if @themes >= MAX_THEMES;
    my $official = "$omarchy_themes/$name";
    my $user = "$user_themes/$name";
    my $repo = from_repo($user);
    # A folder with no palette is an empty or half-removed theme, not one to offer.
    next unless grep { -f $_ } map { ("$official/$_", "$user/$_") } qw(colors.toml alacritty.toml);
    my %bundled = (images("$official/backgrounds", 0), images("$user/backgrounds", $repo));
    my %own = images("$user_backgrounds/$name", 0);

    my @backgrounds;
    for my $file (sort keys %own) {
        push @backgrounds, { path => $own{$file}, file => $file, omarchy => $own{$file} };
    }
    for my $file (sort keys %bundled) {
        push @backgrounds, { path => $bundled{$file}, file => $file,
            omarchy => "$current/backgrounds/$file" };
    }
    splice(@backgrounds, MAX_BACKGROUNDS) if @backgrounds > MAX_BACKGROUNDS;

    my $preview = '';
    for my $candidate (($repo ? () : ("$user/preview.png")), "$official/preview.png") {
        if (safe_path($candidate) && -f $candidate && !($repo && -l $candidate)) {
            $preview = $candidate;
            last;
        }
    }
    $preview = $backgrounds[0]{path} if $preview eq '' && @backgrounds;

    # Omarchy records the link it made, so a theme's own background is remembered by
    # its name under the current theme directory, and a user background by its path.
    my $chosen = first_line("$remembered/$name");
    my $default = @backgrounds ? $backgrounds[0]{path} : '';
    for my $background (@backgrounds) {
        if ($chosen ne '' && $background->{omarchy} eq $chosen) {
            $default = $background->{path};
            last;
        }
    }

    push @themes, { name => $name, label => label($name), preview => $preview,
        backgrounds => \@backgrounds, default => $default };
}

print JSON::PP->new->canonical->encode(\@themes), "\n";
