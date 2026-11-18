#!/usr/bin/perl
use strict;
use warnings;
use File::Basename qw(basename);
use File::Path qw(make_path);

sub profile_for_slot {
    my ($home, $slot) = @_;
    my $directory = "$home/Library/Application Support/UsageDock/Profiles/antigravity";
    open(my $table, '<', "$directory/slots.tsv")
        or die "Open UsageDock and register agy-$slot in Settings.\n";
    my @matches;
    while (my $line = <$table>) {
        chomp $line;
        if ($line =~ /\A$slot\t([A-F0-9]{8}(?:-[A-F0-9]{4}){3}-[A-F0-9]{12})\z/) {
            push @matches, $1;
        }
    }
    close $table;
    die "Register agy-$slot in UsageDock Settings.\n" unless @matches == 1;
    return "$directory/$matches[0]";
}

sub open_browser {
    my (@args) = @_;
    my $pid = fork();
    return 0 unless defined $pid;
    if ($pid == 0) {
        open(STDIN, '<', '/dev/null') or exit 1;
        open(STDOUT, '>', '/dev/null') or exit 1;
        open(STDERR, '>&', \*STDOUT) or exit 1;
        exec { '/usr/bin/open' } '/usr/bin/open', @args or exit 1;
    }
    return waitpid($pid, 0) == $pid && $? == 0;
}

sub open_auth_url {
    my ($url, $open) = @_;
    return $open->('-b', 'com.google.Chrome', $url) || $open->($url);
}

sub login {
    my ($open, $agy, $environment, @args) = @_;
    # Keep the terminal stdin attached to agy. Inspect its output in memory.
    pipe(my $reader, my $writer) or die "Cannot open the agy login pipe.\n";
    my $pid = fork();
    die "Cannot start agy login.\n" unless defined $pid;
    if ($pid == 0) {
        @ENV{keys %$environment} = values %$environment;
        close $reader;
        open(STDOUT, '>&', $writer) or exit 1;
        open(STDERR, '>&', $writer) or exit 1;
        close $writer;
        exec { $agy } $agy, @args, '--log-file', '/dev/null' or exit 127;
    }
    close $writer;
    local $| = 1;
    my $pending = '';
    my $opened = 0;
    while (1) {
        my $size = sysread($reader, my $chunk, 4096);
        next if !defined($size) && $!{EINTR};
        last unless $size;
        print STDOUT $chunk;
        next if $opened;
        $pending .= $chunk;
        # Wait for a delimiter so a URL split across reads is passed intact.
        if ($pending =~ m{(https://accounts\.google\.com/(?:o/oauth2/|signin/oauth)[^\s<>"'\x1b]+)(?=[\s<>"'\x1b])}) {
            open_auth_url($1, $open);
            $opened = 1;
            $pending = '';
        } else {
            $pending =~ s/.*[\r\n]//s;
            $pending = substr($pending, -16384) if length($pending) > 16384;
        }
    }
    close $reader;
    return 1 unless waitpid($pid, 0) == $pid;
    return ($? & 127) ? 128 + ($? & 127) : $? >> 8;
}

sub main {
    my ($open, @args) = @_;
    my $user_home = $ENV{HOME} // die "HOME is unavailable.\n";
    my $profile;
    if (basename($0) =~ /\Aagy-([0-5])\z/) {
        $profile = profile_for_slot($user_home, $1);
    } elsif (($args[0] // '') eq '--profile-home') {
        shift @args;
        $profile = shift @args;
        die "Invalid profile HOME.\n" unless defined($profile) && $profile =~ m{\A/.+};
    } elsif (($args[0] // '') eq '--current-session') {
        shift @args;
    } else {
        die "Run this helper as agy-0 through agy-5.\n";
    }
    my ($agy) = grep { -f $_ && -x _ } (
        "$user_home/.local/bin/agy", '/opt/homebrew/bin/agy', '/usr/local/bin/agy',
        map { "$_/agy" } grep { m{\A/} } split(/:/, $ENV{PATH} // '')
    );
    die "Install the Antigravity CLI (agy) and retry.\n" unless defined $agy;

    my %environment;
    if (defined $profile) {
        %environment = (
            HOME => $profile,
            ANTIGRAVITY_GEMINI_DIR => "$profile/.gemini/antigravity-cli",
            ANTIGRAVITY_APP_DATA_DIR => "$profile/.gemini/antigravity-app"
        );
        make_path($environment{ANTIGRAVITY_GEMINI_DIR}, $environment{ANTIGRAVITY_APP_DATA_DIR});
    }
    if (($args[0] // '') eq 'acp') {
        if (defined $profile) {
            splice @args, 1, 0, '--gemini-dir', $environment{ANTIGRAVITY_GEMINI_DIR},
                '--app-data-dir', $environment{ANTIGRAVITY_APP_DATA_DIR};
        }
        if (grep { $_ eq '--login' || $_ eq '--login=true' } @args) {
            return login($open, $agy, \%environment, @args);
        }
    }
    @ENV{keys %environment} = values %environment;
    exec { $agy } $agy, @args or return 127;
}

exit main(\&open_browser, @ARGV) unless caller;
1;
