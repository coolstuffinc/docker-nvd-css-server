{ pkgs ? import <nixpkgs> {} }:

(pkgs.buildFHSEnv {
  name = "sourcepawn-env";
  targetPkgs = pkgs: with pkgs; [
    bashInteractive
    coreutils
    wget
    curl
    unzip
    git
    git-lfs
    # 32-bit libs for SourceMod/spcomp
    pkgsi686Linux.glibc
    pkgsi686Linux.gcc-unwrapped
    pkgsi686Linux.ncurses
  ];
  runScript = "bash";
}).env
