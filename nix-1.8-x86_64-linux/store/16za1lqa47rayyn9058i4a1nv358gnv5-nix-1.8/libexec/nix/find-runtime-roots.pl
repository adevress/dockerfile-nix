#! /nix/store/g9ybksy400pfn7fncw8dqfnz6m7fdyrk-perl-5.20.1/bin/perl -w -I/nix/store/16za1lqa47rayyn9058i4a1nv358gnv5-nix-1.8/lib/perl5/site_perl/5.20.1/x86_64-linux-thread-multi -I/nix/store/d4b4avbsbcz4hbf35r1270rdkfk7gf7y-perl-DBI-1.631/lib/perl5/site_perl -I/nix/store/jhdnwklzq2pakz7sp631pf48vfbrgfcv-perl-DBD-SQLite-1.44/lib/perl5/site_perl -I/nix/store/wg4dxpl9c9xfr1zg4j80j4c4n5s626sy-perl-WWW-Curl-4.17/lib/perl5/site_perl

use strict;
use Nix::Utils;
use Nix::Config;


sub readProc {
    return unless -d "/proc";

    opendir DIR, "/proc" or return;

    foreach my $name (readdir DIR) {
        next unless $name =~ /^\d+$/;

        my $process = "/proc/$name";

        #print STDERR "=== $process\n";

        my $target;
        print "$target\n" if $target = readlink "$process/exe";
        print "$target\n" if $target = readlink "$process/cwd";

        if (opendir FDS, "$process/fd") {
            foreach my $name (readdir FDS) {
                $target = readlink "$process/fd/$name";
                print "$target\n" if $target && substr($target, 0, 1) eq "/";
            }
            closedir FDS;
        }

        if (open MAP, "<$process/maps") {
            while (<MAP>) {
                next unless /^ \s* \S+ \s+ \S+ \s+ \S+ \s+ \S+ \s+ \S+ \s+ (\/\S+) \s* $/x;
                print "$1\n";
            }
            close MAP;
        }

        # Get all store paths that appear in the environment of this process.
        eval {
            my $env = Nix::Utils::readFile "$process/environ";
            my @matches = $env =~ /\Q$Nix::Config::storeDir\E\/[0-9a-z]+[0-9a-zA-Z\+\-\._\?=]*/g;
            print "$_\n" foreach @matches;
        }
    }

    closedir DIR;
}


sub lsof {
    return unless open LSOF, "lsof -n -w -F n 2> /dev/null |";

    while (<LSOF>) {
        next unless /^n (\/ .*)$/x;
        print $1, "\n";
    }

    close LSOF;
}


readProc;
lsof;


sub printFile {
    my ($fn) = @_;
    if (-e $fn) {
        print Nix::Utils::readFile($fn), "\n";
    }
}


# This is rather NixOS-specific, so it probably shouldn't be here.
printFile "/proc/sys/kernel/modprobe";
printFile "/proc/sys/kernel/fbsplash";
printFile "/proc/sys/kernel/poweroff_cmd";
