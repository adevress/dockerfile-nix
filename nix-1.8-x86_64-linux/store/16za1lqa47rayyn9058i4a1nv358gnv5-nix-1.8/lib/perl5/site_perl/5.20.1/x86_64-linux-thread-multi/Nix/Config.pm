package Nix::Config;

$version = "1.8";

$binDir = $ENV{"NIX_BIN_DIR"} || "/nix/store/16za1lqa47rayyn9058i4a1nv358gnv5-nix-1.8/bin";
$libexecDir = $ENV{"NIX_LIBEXEC_DIR"} || "/nix/store/16za1lqa47rayyn9058i4a1nv358gnv5-nix-1.8/libexec";
$stateDir = $ENV{"NIX_STATE_DIR"} || "/nix/var/nix";
$manifestDir = $ENV{"NIX_MANIFESTS_DIR"} || "/nix/var/nix/manifests";
$logDir = $ENV{"NIX_LOG_DIR"} || "/nix/var/log/nix";
$confDir = $ENV{"NIX_CONF_DIR"} || "/etc/nix";
$storeDir = $ENV{"NIX_STORE_DIR"} || "/nix/store";

$bzip2 = "/nix/store/dqmh55k38i24h9xnb4qb5pqggfl4dvxm-bzip2-1.0.6/bin/bzip2";
$xz = "/nix/store/7rlvlgy875zs98y3rz06mmnaaa66vbr7-xz-5.0.7/bin/xz";
$curl = "/nix/store/msy4kfrb732qyf5zs2f42vc2hwsdg4jc-curl-7.39.0/bin/curl";
$openssl = "/nix/store/79r6ys4r2nfv1d5h6ryc1gwc8j25r86w-openssl-1.0.1j/bin/openssl";

$useBindings = "yes" eq "yes";

%config = ();

sub readConfig {
    if (defined $ENV{'_NIX_OPTIONS'}) {
        foreach my $s (split '\n', $ENV{'_NIX_OPTIONS'}) {
            my ($n, $v) = split '=', $s, 2;
            $config{$n} = $v;
        }
        return;
    }

    my $config = "$confDir/nix.conf";
    return unless -f $config;

    open CONFIG, "<$config" or die "cannot open ‘$config’";
    while (<CONFIG>) {
        /^\s*([\w\-\.]+)\s*=\s*(.*)$/ or next;
        $config{$1} = $2;
    }
    close CONFIG;
}

return 1;
