{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    gcc
    pkg-config
    wget
    curl
    unzip
    git
    bash
    binutils
    file
    # This provides the magic 32-bit environment
    steam-run
  ];
  
  shellHook = ''
    echo "Environment ready (using steam-run)."
  '';
}
