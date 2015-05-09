#! /nix/store/g9ybksy400pfn7fncw8dqfnz6m7fdyrk-perl-5.20.1/bin/perl -w -I/nix/store/16za1lqa47rayyn9058i4a1nv358gnv5-nix-1.8/lib/perl5/site_perl/5.20.1/x86_64-linux-thread-multi -I/nix/store/d4b4avbsbcz4hbf35r1270rdkfk7gf7y-perl-DBI-1.631/lib/perl5/site_perl -I/nix/store/jhdnwklzq2pakz7sp631pf48vfbrgfcv-perl-DBD-SQLite-1.44/lib/perl5/site_perl -I/nix/store/wg4dxpl9c9xfr1zg4j80j4c4n5s626sy-perl-WWW-Curl-4.17/lib/perl5/site_perl

use utf8;
use strict;
use File::Basename;
use IO::Handle;

my $binDir = $ENV{"NIX_BIN_DIR"} || "/nix/store/16za1lqa47rayyn9058i4a1nv358gnv5-nix-1.8/bin";


STDOUT->autoflush(1);

my @remoteStoresAll = split ':', ($ENV{"NIX_OTHER_STORES"} or "");

my @remoteStores;
foreach my $dir (@remoteStoresAll) {
    push @remoteStores, glob($dir);
}

exit if scalar @remoteStores == 0;
print "\n";


$ENV{"NIX_REMOTE"} = "";


sub findStorePath {
    my $storePath = shift;
    foreach my $store (@remoteStores) {
        my $sourcePath = "$store/store/" . basename $storePath;
        next unless -e $sourcePath || -l $sourcePath;
        $ENV{"NIX_DB_DIR"} = "$store/var/nix/db";
        return ($store, $sourcePath) if
            system("$binDir/nix-store --check-validity $storePath") == 0;
    }
    return undef;
}


if ($ARGV[0] eq "--query") {

    while (<STDIN>) {
        chomp;
        my ($cmd, @args) = split " ", $_;

        if ($cmd eq "have") {
            foreach my $storePath (@args) {
                print "$storePath\n" if defined findStorePath($storePath);
            }
            print "\n";
        }

        elsif ($cmd eq "info") {
            foreach my $storePath (@args) {
                my ($store, $sourcePath) = findStorePath($storePath);
                next unless defined $store;

                $ENV{"NIX_DB_DIR"} = "$store/var/nix/db";

                my $deriver = `$binDir/nix-store --query --deriver $storePath`;
                die "cannot query deriver of ‘$storePath’" if $? != 0;
                chomp $deriver;
                $deriver = "" if $deriver eq "unknown-deriver";

                my @references = split "\n",
                    `$binDir/nix-store --query --references $storePath`;
                die "cannot query references of ‘$storePath’" if $? != 0;

                my $narSize = `$binDir/nix-store --query --size $storePath`;
                die "cannot query size of ‘$storePath’" if $? != 0;
                chomp $narSize;

                print "$storePath\n";
                print "$deriver\n";
                print scalar @references, "\n";
                print "$_\n" foreach @references;
                print "0\n";
                print "$narSize\n";
            }

            print "\n";
        }

        else { die "unknown command ‘$cmd’"; }
    }
}


elsif ($ARGV[0] eq "--substitute") {
    die unless scalar @ARGV == 3;
    my $storePath = $ARGV[1];
    my $destPath = $ARGV[2];
    my ($store, $sourcePath) = findStorePath $storePath;
    die unless $store;
    print STDERR "\n*** Copying ‘$storePath’ from ‘$sourcePath’\n\n";
    system("$binDir/nix-store --dump $sourcePath | $binDir/nix-store --restore $destPath") == 0
        or die "cannot copy ‘$sourcePath’ to ‘$storePath’";
    print "\n"; # no hash to verify
}


else { die; }
