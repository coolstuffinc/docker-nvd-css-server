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
    # Use the 32-bit glibc specifically
    export SP_LOADER="${pkgs.pkgsi686Linux.glibc}/lib/ld-linux.so.2"
    export LD_LIBRARY_PATH="${pkgs.pkgsi686Linux.stdenv.cc.cc.lib}/lib:${pkgs.glibc_multi}/lib:${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
    export PATH="$PATH:$(pwd)/scripts"
  '';


}
