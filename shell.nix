{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    glibc_multi
    stdenv.cc.cc.lib
    pkgsi686Linux.stdenv.cc.cc.lib
    pkg-config
    ncurses
    openjdk17
    unzip
    git
    git-lfs
    bash
    binutils
    file
  ];

  shellHook = ''
    export LD_LIBRARY_PATH="${pkgs.pkgsi686Linux.glibc}/lib:${pkgs.pkgsi686Linux.stdenv.cc.cc.lib}/lib:${pkgs.glibc_multi}/lib:${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
    export PATH="$PATH:$(pwd)/scripts"
    alias rcon='python3 $(pwd)/scripts/rcon.py'
  '';



}
