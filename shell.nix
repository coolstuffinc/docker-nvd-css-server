{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # 32-bit library provider
    pkgsi686Linux.glibc
    pkgsi686Linux.stdenv.cc.cc.lib
    pkgsi686Linux.ncurses
    
    # Standard tools
    gcc
    pkg-config
    openjdk17
    unzip
    git
    git-lfs
    bash
    binutils
    file
  ];

  shellHook = ''
    # Export the loader path explicitly
    export SP_LOADER="${pkgs.pkgsi686Linux.glibc}/lib/ld-linux.so.2"
    # Set library paths
    export LD_LIBRARY_PATH="${pkgs.pkgsi686Linux.glibc}/lib:${pkgs.pkgsi686Linux.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
    export PATH="$PATH:$(pwd)/scripts"
  '';
}
