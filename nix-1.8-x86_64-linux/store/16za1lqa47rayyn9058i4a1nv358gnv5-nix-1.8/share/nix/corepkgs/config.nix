let
  fromEnv = var: def:
    let val = builtins.getEnv var; in
    if val != "" then val else def;
in {
  perl = "/nix/store/g9ybksy400pfn7fncw8dqfnz6m7fdyrk-perl-5.20.1/bin/perl";
  shell = "/nix/store/r5sxfcwq9324xvcd1z312kb9kkddqvld-bash-4.3-p30/bin/bash";
  coreutils = "/nix/store/wc472nw0kyw0iwgl6352ii5czxd97js2-coreutils-8.23/bin";
  bzip2 = "/nix/store/dqmh55k38i24h9xnb4qb5pqggfl4dvxm-bzip2-1.0.6/bin/bzip2";
  gzip = "/nix/store/sr65fbmyvsrzd4vbgvx1pkqm6a04hzas-gzip-1.6/bin/gzip";
  xz = "/nix/store/7rlvlgy875zs98y3rz06mmnaaa66vbr7-xz-5.0.7/bin/xz";
  tar = "/nix/store/rygv74phd82c106qynz7l0rmg4rvrlzd-gnutar-1.27.1/bin/tar";
  tarFlags = "--warning=no-timestamp";
  tr = "/nix/store/wc472nw0kyw0iwgl6352ii5czxd97js2-coreutils-8.23/bin/tr";
  curl = "/nix/store/msy4kfrb732qyf5zs2f42vc2hwsdg4jc-curl-7.39.0/bin/curl";
  nixBinDir = fromEnv "NIX_BIN_DIR" "/nix/store/16za1lqa47rayyn9058i4a1nv358gnv5-nix-1.8/bin";
}
