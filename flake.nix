{
  description = "SourcePawn Compilation Environment";
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; };
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system; 
        config = { allowUnfree = true; };
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Tools
          gcc
          pkg-config
          wget
          curl
          unzip
          git
          git-lfs
          bash
          binutils
          file
          # This provides the magic 32-bit environment
          steam-run
        ];
        
        shellHook = ''
          echo "Environment ready (using steam-run)."
        '';
      };
    };
}
