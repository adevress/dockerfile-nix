#! /nix/store/g9ybksy400pfn7fncw8dqfnz6m7fdyrk-perl-5.20.1/bin/perl -w -I/nix/store/16za1lqa47rayyn9058i4a1nv358gnv5-nix-1.8/lib/perl5/site_perl/5.20.1/x86_64-linux-thread-multi -I/nix/store/d4b4avbsbcz4hbf35r1270rdkfk7gf7y-perl-DBI-1.631/lib/perl5/site_perl -I/nix/store/jhdnwklzq2pakz7sp631pf48vfbrgfcv-perl-DBD-SQLite-1.44/lib/perl5/site_perl -I/nix/store/wg4dxpl9c9xfr1zg4j80j4c4n5s626sy-perl-WWW-Curl-4.17/lib/perl5/site_perl

use utf8;
use DBI;
use DBD::SQLite;
use File::Basename;
use IO::Select;
use Nix::Config;
use Nix::Store;
use Nix::Utils;
use Nix::Manifest;
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use strict;

STDERR->autoflush(1);
binmode STDERR, ":encoding(utf8)";

Nix::Config::readConfig;

my @caches;
my $gotCaches = 0;

my $maxParallelRequests = int($Nix::Config::config{"binary-caches-parallel-connections"} // 150);
$maxParallelRequests = 1 if $maxParallelRequests < 1;

my $ttlNegative = 24 * 3600; # when to purge negative lookups from the database
my $ttlNegativeUse = 3600; # how long negative lookups are valid for non-"have" lookups
my $didExpiration = 0;

my $showAfter = 5; # show that we're waiting for a request after this many seconds

my $debug = ($Nix::Config::config{"debug-subst"} // "") eq 1 || ($Nix::Config::config{"untrusted-debug-subst"} // "") eq 1;

my $cacheFileURLs = ($ENV{"_NIX_CACHE_FILE_URLS"} // "") eq 1; # for testing

my ($dbh, $queryCache, $insertNAR, $queryNAR, $insertNARExistence, $queryNARExistence, $expireNARExistence);

my $curlm = WWW::Curl::Multi->new;
my $activeRequests = 0;
my $curlIdCount = 1;
my %requests;
my %scheduled;
my $caBundle = $ENV{"SSL_CERT_FILE"} // $ENV{"CURL_CA_BUNDLE"} // $ENV{"OPENSSL_X509_CERT_FILE"};
$caBundle = "/etc/ssl/certs/ca-bundle.crt" if !$caBundle && -f "/etc/ssl/certs/ca-bundle.crt";
$caBundle = "/etc/ssl/certs/ca-certificates.crt" if !$caBundle && -f "/etc/ssl/certs/ca-certificates.crt";

my $userName = getpwuid($<) || $ENV{"USER"} or die "cannot figure out user name";

sub isTrue {
    my ($x) = @_;
    return $x eq "true" || $x eq "1";
}

my $requireSignedBinaryCaches = ($Nix::Config::config{"signed-binary-caches"} // "0") ne "0";

my $curlConnectTimeout = int(
    $Nix::Config::config{"untrusted-connect-timeout"} //
    $Nix::Config::config{"connect-timeout"} //
    $ENV{"NIX_CONNECT_TIMEOUT"} // 0);


sub addRequest {
    my ($storePath, $url, $head) = @_;

    my $curl = WWW::Curl::Easy->new;
    my $curlId = $curlIdCount++;
    $requests{$curlId} = { storePath => $storePath, url => $url, handle => $curl, content => "", type => $head ? "HEAD" : "GET"
                         , shown => 0, started => time() };

    $curl->setopt(CURLOPT_PRIVATE, $curlId);
    $curl->setopt(CURLOPT_URL, $url);
    open (my $fh, ">", \$requests{$curlId}->{content});
    $curl->setopt(CURLOPT_WRITEDATA, $fh);
    $curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
    $curl->setopt(CURLOPT_CAINFO, $caBundle) if defined $caBundle;
    $curl->setopt(CURLOPT_SSL_VERIFYPEER, 0) unless isTrue($Nix::Config::config{"verify-https-binary-caches"} // "1");
    $curl->setopt(CURLOPT_USERAGENT, "Nix/$Nix::Config::version");
    $curl->setopt(CURLOPT_NOBODY, 1) if $head;
    $curl->setopt(CURLOPT_FAILONERROR, 1);
    $curl->setopt(CURLOPT_CONNECTTIMEOUT, $curlConnectTimeout);
    $curl->setopt(CURLOPT_TIMEOUT, 20 * 60);

    if ($activeRequests >= $maxParallelRequests) {
        $scheduled{$curlId} = 1;
    } else {
        $curlm->add_handle($curl);
        $activeRequests++;
    }

    return $requests{$curlId};
}


sub processRequests {
    while ($activeRequests) {
        my ($rfds, $wfds, $efds) = $curlm->fdset();
        #print STDERR "R = @{$rfds}, W = @{$wfds}, E = @{$efds}\n";

        # Sleep until we can read or write some data.
        if (scalar @{$rfds} + scalar @{$wfds} + scalar @{$efds} > 0) {
            IO::Select->select(IO::Select->new(@{$rfds}), IO::Select->new(@{$wfds}), IO::Select->new(@{$efds}), 1.0);
        }

        if ($curlm->perform() != $activeRequests) {
            while (my ($id, $result) = $curlm->info_read) {
                if ($id) {
                    my $request = $requests{$id} or die;
                    my $handle = $request->{handle};
                    $request->{result} = $result;
                    $request->{httpStatus} = $handle->getinfo(CURLINFO_RESPONSE_CODE);

                    print STDERR "$request->{type} on $request->{url} [$request->{result}, $request->{httpStatus}]\n" if $debug;

                    $activeRequests--;
                    delete $request->{handle};

                    if (scalar(keys %scheduled) > 0) {
                        my $id2 = (keys %scheduled)[0];
                        $curlm->add_handle($requests{$id2}->{handle});
                        $activeRequests++;
                        delete $scheduled{$id2};
                    }
                }
            }
        }

        my $time = time();
        while (my ($key, $request) = each %requests) {
            next unless defined $request->{handle};
            next if $request->{shown};
            if ($time > $request->{started} + $showAfter) {
                print STDERR "still waiting for ‘$request->{url}’ after $showAfter seconds...\n";
                $request->{shown} = 1;
            }
        }
    }
}


sub initCache {
    my $dbPath = "$Nix::Config::stateDir/binary-cache-v3.sqlite";

    unlink "$Nix::Config::stateDir/binary-cache-v1.sqlite";
    unlink "$Nix::Config::stateDir/binary-cache-v2.sqlite";

    # Open/create the database.
    $dbh = DBI->connect("dbi:SQLite:dbname=$dbPath", "", "")
        or die "cannot open database ‘$dbPath’";
    $dbh->{RaiseError} = 1;
    $dbh->{PrintError} = 0;

    $dbh->sqlite_busy_timeout(60 * 60 * 1000);

    $dbh->do("pragma synchronous = off"); # we can always reproduce the cache
    $dbh->do("pragma journal_mode = truncate");

    # Initialise the database schema, if necessary.
    $dbh->do(<<EOF);
        create table if not exists BinaryCaches (
            id        integer primary key autoincrement not null,
            url       text unique not null,
            timestamp integer not null,
            storeDir  text not null,
            wantMassQuery integer not null,
            priority  integer not null
        );
EOF

    $dbh->do(<<EOF);
        create table if not exists NARs (
            cache            integer not null,
            storePath        text not null,
            url              text not null,
            compression      text not null,
            fileHash         text,
            fileSize         integer,
            narHash          text,
            narSize          integer,
            refs             text,
            deriver          text,
            signedBy         text,
            timestamp        integer not null,
            primary key (cache, storePath),
            foreign key (cache) references BinaryCaches(id) on delete cascade
        );
EOF

    $dbh->do(<<EOF);
        create table if not exists NARExistence (
            cache            integer not null,
            storePath        text not null,
            exist            integer not null,
            timestamp        integer not null,
            primary key (cache, storePath),
            foreign key (cache) references BinaryCaches(id) on delete cascade
        );
EOF

    $dbh->do("create index if not exists NARExistenceByExistTimestamp on NARExistence (exist, timestamp)");

    $queryCache = $dbh->prepare("select id, storeDir, wantMassQuery, priority from BinaryCaches where url = ?") or die;

    $insertNAR = $dbh->prepare(
        "insert or replace into NARs(cache, storePath, url, compression, fileHash, fileSize, narHash, " .
        "narSize, refs, deriver, signedBy, timestamp) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)") or die;

    $queryNAR = $dbh->prepare("select * from NARs where cache = ? and storePath = ?") or die;

    $insertNARExistence = $dbh->prepare(
        "insert or replace into NARExistence(cache, storePath, exist, timestamp) values (?, ?, ?, ?)") or die;

    $queryNARExistence = $dbh->prepare("select exist, timestamp from NARExistence where cache = ? and storePath = ?") or die;

    $expireNARExistence = $dbh->prepare("delete from NARExistence where exist = ? and timestamp < ?") or die;
}


sub getAvailableCaches {
    return if $gotCaches;
    $gotCaches = 1;

    sub strToList {
        my ($s) = @_;
        return map { s/\/+$//; $_ } split(/ /, $s);
    }

    my @urls = strToList($Nix::Config::config{"binary-caches"} //
        ($Nix::Config::storeDir eq "/nix/store" ? "https://cache.nixos.org" : ""));

    my $urlsFiles = $Nix::Config::config{"binary-cache-files"}
        // "$Nix::Config::stateDir/profiles/per-user/$userName/channels/binary-caches/*";
    foreach my $urlFile (glob $urlsFiles) {
        next unless -f $urlFile;
        open FILE, "<$urlFile" or die "cannot open ‘$urlFile’\n";
        my $url = <FILE>; chomp $url;
        close FILE;
        push @urls, strToList($url);
    }

    push @urls, strToList($Nix::Config::config{"extra-binary-caches"} // "");

    # Allow Nix daemon users to override the binary caches to a subset
    # of those listed in the config file.  Note that ‘untrusted-*’
    # denotes options passed by the client.
    my @trustedUrls = uniq(@urls, strToList($Nix::Config::config{"trusted-binary-caches"} // ""));

    if (defined $Nix::Config::config{"untrusted-binary-caches"}) {
        my @untrustedUrls = strToList $Nix::Config::config{"untrusted-binary-caches"};
        @urls = ();
        foreach my $url (@untrustedUrls) {
            die "binary cache ‘$url’ is not trusted (please add it to ‘trusted-binary-caches’ in $Nix::Config::confDir/nix.conf)\n"
                unless scalar(grep { $url eq $_ } @trustedUrls) > 0;
            push @urls, $url;
        }
    }

    my @untrustedUrls = strToList $Nix::Config::config{"untrusted-extra-binary-caches"} // "";
    foreach my $url (@untrustedUrls) {
        unless (scalar(grep { $url eq $_ } @trustedUrls) > 0) {
            warn "binary cache ‘$url’ is not trusted (please add it to ‘trusted-binary-caches’ in $Nix::Config::confDir/nix.conf)\n";
            next;
        }
        push @urls, $url;
    }

    foreach my $url (uniq @urls) {

        # FIXME: not atomic.
        $queryCache->execute($url);
        my $res = $queryCache->fetchrow_hashref();
        if (defined $res) {
            next if $res->{storeDir} ne $Nix::Config::storeDir;
            push @caches, { id => $res->{id}, url => $url, wantMassQuery => $res->{wantMassQuery}, priority => $res->{priority} };
            next;
        }

        # Get the cache info file.
        my $request = addRequest(undef, $url . "/nix-cache-info");
        processRequests;

        if ($request->{result} != 0) {
            print STDERR "could not download ‘$request->{url}’ (" .
                ($request->{result} != 0 ? "Curl error $request->{result}" : "HTTP status $request->{httpStatus}") . ")\n";
            next;
        }

        my $storeDir = "/nix/store";
        my $wantMassQuery = 0;
        my $priority = 50;
        foreach my $line (split "\n", $request->{content}) {
            unless ($line =~ /^(.*): (.*)$/) {
                print STDERR "bad cache info file ‘$request->{url}’\n";
                return undef;
            }
            if ($1 eq "StoreDir") { $storeDir = $2; }
            elsif ($1 eq "WantMassQuery") { $wantMassQuery = int($2); }
            elsif ($1 eq "Priority") { $priority = int($2); }
        }

        $dbh->do("insert or replace into BinaryCaches(url, timestamp, storeDir, wantMassQuery, priority) values (?, ?, ?, ?, ?)",
                 {}, $url, time(), $storeDir, $wantMassQuery, $priority);
        $queryCache->execute($url);
        $res = $queryCache->fetchrow_hashref() or die;
        next if $storeDir ne $Nix::Config::storeDir;
        push @caches, { id => $res->{id}, url => $url, wantMassQuery => $wantMassQuery, priority => $priority };
    }

    @caches = sort { $a->{priority} <=> $b->{priority} } @caches;

    expireNegative();
}


sub shouldCache {
    my ($url) = @_;
    return $cacheFileURLs || $url !~ /^file:/;
}


sub processNARInfo {
    my ($storePath, $cache, $request) = @_;

    if ($request->{result} != 0) {
        if ($request->{result} != 37 && $request->{httpStatus} != 404 && $request->{httpStatus} != 403) {
            print STDERR "could not download ‘$request->{url}’ (" .
                ($request->{result} != 0 ? "Curl error $request->{result}" : "HTTP status $request->{httpStatus}") . ")\n";
        } else {
            $insertNARExistence->execute($cache->{id}, basename($storePath), 0, time())
                if shouldCache $request->{url};
        }
        return undef;
    }

    my $narInfo = parseNARInfo($storePath, $request->{content}, $requireSignedBinaryCaches, $request->{url});
    return undef unless defined $narInfo;

    die if $requireSignedBinaryCaches && !defined $narInfo->{signedBy};

    # Cache the result.
    $insertNAR->execute(
        $cache->{id}, basename($storePath), $narInfo->{url}, $narInfo->{compression},
        $narInfo->{fileHash}, $narInfo->{fileSize}, $narInfo->{narHash}, $narInfo->{narSize},
        join(" ", @{$narInfo->{refs}}), $narInfo->{deriver}, $narInfo->{signedBy}, time())
        if shouldCache $request->{url};

    return $narInfo;
}


sub getCachedInfoFrom {
    my ($storePath, $cache) = @_;

    $queryNAR->execute($cache->{id}, basename($storePath));
    my $res = $queryNAR->fetchrow_hashref();
    return undef unless defined $res;

    # We may previously have cached this info when signature checking
    # was disabled.  In that case, ignore the cached info.
    return undef if $requireSignedBinaryCaches && !defined $res->{signedBy};

    return
        { url => $res->{url}
        , compression => $res->{compression}
        , fileHash => $res->{fileHash}
        , fileSize => $res->{fileSize}
        , narHash => $res->{narHash}
        , narSize => $res->{narSize}
        , refs => [ split " ", $res->{refs} ]
        , deriver => $res->{deriver}
        , signedBy => $res->{signedBy}
        } if defined $res;
}


sub negativeHit {
    my ($storePath, $cache) = @_;
    $queryNARExistence->execute($cache->{id}, basename($storePath));
    my $res = $queryNARExistence->fetchrow_hashref();
    return defined $res && $res->{exist} == 0 && time() - $res->{timestamp} < $ttlNegativeUse;
}


sub positiveHit {
    my ($storePath, $cache) = @_;
    return 1 if defined getCachedInfoFrom($storePath, $cache);
    $queryNARExistence->execute($cache->{id}, basename($storePath));
    my $res = $queryNARExistence->fetchrow_hashref();
    return defined $res && $res->{exist} == 1;
}


sub expireNegative {
    return if $didExpiration;
    $didExpiration = 1;
    my $time = time();
    # Round up to the next multiple of the TTL to ensure that we do
    # expiration only once per time interval.  E.g. if $ttlNegative ==
    # 3600, we expire entries at most once per hour.  This is
    # presumably faster than expiring a few entries per request (and
    # thus doing a transaction).
    my $limit = (int($time / $ttlNegative) - 1) * $ttlNegative;
    $expireNARExistence->execute($limit, 0);
    print STDERR "expired ", $expireNARExistence->rows, " negative entries\n" if $debug;
}


sub printInfo {
    my ($storePath, $info) = @_;
    print "$storePath\n";
    print $info->{deriver} ? "$Nix::Config::storeDir/$info->{deriver}" : "", "\n";
    print scalar @{$info->{refs}}, "\n";
    print "$Nix::Config::storeDir/$_\n" foreach @{$info->{refs}};
    print $info->{fileSize} || 0, "\n";
    print $info->{narSize} || 0, "\n";
}


sub infoUrl {
    my ($binaryCacheUrl, $storePath) = @_;
    my $pathHash = substr(basename($storePath), 0, 32);
    my $infoUrl = "$binaryCacheUrl/$pathHash.narinfo";
}


sub printInfoParallel {
    my @paths = @_;

    # First print all paths for which we have cached info.
    my @left;
    foreach my $storePath (@paths) {
        my $found = 0;
        foreach my $cache (@caches) {
            my $info = getCachedInfoFrom($storePath, $cache);
            if (defined $info) {
                printInfo($storePath, $info);
                $found = 1;
                last;
            }
        }
        push @left, $storePath if !$found;
    }

    return if scalar @left == 0;

    foreach my $cache (@caches) {

        my @left2;
        %requests = ();
        foreach my $storePath (@left) {
            if (negativeHit($storePath, $cache)) {
                push @left2, $storePath;
                next;
            }
            addRequest($storePath, infoUrl($cache->{url}, $storePath));
        }

        processRequests;

        foreach my $request (values %requests) {
            my $info = processNARInfo($request->{storePath}, $cache, $request);
            if (defined $info) {
                printInfo($request->{storePath}, $info);
            } else {
                push @left2, $request->{storePath};
            }
        }

        @left = @left2;
    }
}


sub printSubstitutablePaths {
    my @paths = @_;

    # First look for paths that have cached info.
    my @left;
    foreach my $storePath (@paths) {
        my $found = 0;
        foreach my $cache (@caches) {
            next unless $cache->{wantMassQuery};
            if (positiveHit($storePath, $cache)) {
                print "$storePath\n";
                $found = 1;
                last;
            }
        }
        push @left, $storePath if !$found;
    }

    return if scalar @left == 0;

    # For remaining paths, do HEAD requests.
    foreach my $cache (@caches) {
        next unless $cache->{wantMassQuery};
        my @left2;
        %requests = ();
        foreach my $storePath (@left) {
            if (negativeHit($storePath, $cache)) {
                push @left2, $storePath;
                next;
            }
            addRequest($storePath, infoUrl($cache->{url}, $storePath), 1);
        }

        processRequests;

        foreach my $request (values %requests) {
            if ($request->{result} != 0) {
                if ($request->{result} != 37 && $request->{httpStatus} != 404 && $request->{httpStatus} != 403) {
                    print STDERR "could not check ‘$request->{url}’ (" .
                        ($request->{result} != 0 ? "Curl error $request->{result}" : "HTTP status $request->{httpStatus}") . ")\n";
                } else {
                    $insertNARExistence->execute($cache->{id}, basename($request->{storePath}), 0, time())
                        if shouldCache $request->{url};
                }
                push @left2, $request->{storePath};
            } else {
                $insertNARExistence->execute($cache->{id}, basename($request->{storePath}), 1, time())
                    if shouldCache $request->{url};
                print "$request->{storePath}\n";
            }
        }

        @left = @left2;
    }
}


sub downloadBinary {
    my ($storePath, $destPath) = @_;

    foreach my $cache (@caches) {
        my $info = getCachedInfoFrom($storePath, $cache);

        unless (defined $info) {
            next if negativeHit($storePath, $cache);
            my $request = addRequest($storePath, infoUrl($cache->{url}, $storePath));
            processRequests;
            $info = processNARInfo($storePath, $cache, $request);
        }

        next unless defined $info;

        my $decompressor;
        if ($info->{compression} eq "bzip2") { $decompressor = "| $Nix::Config::bzip2 -d"; }
        elsif ($info->{compression} eq "xz") { $decompressor = "| $Nix::Config::xz -d"; }
        elsif ($info->{compression} eq "none") { $decompressor = ""; }
        else {
            print STDERR "unknown compression method ‘$info->{compression}’\n";
            next;
        }
        my $url = "$cache->{url}/$info->{url}"; # FIXME: handle non-relative URLs
        die if $requireSignedBinaryCaches && !defined $info->{signedBy};
        print STDERR "\n*** Downloading ‘$url’ ", ($requireSignedBinaryCaches ? "(signed by ‘$info->{signedBy}’) " : ""), "to ‘$storePath’...\n";
        checkURL $url;
        if (system("$Nix::Config::curl --fail --location --insecure --connect-timeout $curlConnectTimeout '$url' $decompressor | $Nix::Config::binDir/nix-store --restore $destPath") != 0) {
            warn "download of ‘$url’ failed" . ($! ? ": $!" : "") . "\n";
            next;
        }

        # Tell Nix about the expected hash so it can verify it.
        die unless defined $info->{narHash} && $info->{narHash} ne "";
        print "$info->{narHash}\n";

        print STDERR "\n";
        return;
    }

    print STDERR "could not download ‘$storePath’ from any binary cache\n";
    exit 1;
}


# Bail out right away if binary caches are disabled.
exit 0 if
    ($Nix::Config::config{"use-binary-caches"} // "true") eq "false" ||
    ($Nix::Config::config{"untrusted-use-binary-caches"} // "true") eq "false";
print "\n";
flush STDOUT;

initCache();


if ($ARGV[0] eq "--query") {

    while (<STDIN>) {
        getAvailableCaches;
        chomp;
        my ($cmd, @args) = split " ", $_;

        if ($cmd eq "have") {
            print STDERR "checking binary caches for existence of @args\n" if $debug;
            printSubstitutablePaths(@args);
            print "\n";
        }

        elsif ($cmd eq "info") {
            print STDERR "checking binary caches for info on @args\n" if $debug;
            printInfoParallel(@args);
            print "\n";
        }

        else { die "unknown command ‘$cmd’"; }

        flush STDOUT;
    }

}

elsif ($ARGV[0] eq "--substitute") {
    my $storePath = $ARGV[1] or die;
    my $destPath = $ARGV[2] or die;
    getAvailableCaches;
    downloadBinary($storePath, $destPath);
}

else {
    die;
}
