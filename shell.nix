{ pkgs ? import <nixpkgs> { config = { allowUnfree = true; }; } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    steam-run
    bash
  ];
  
  shellHook = ''
    echo "Environment ready (using steam-run)."
  '';
}
