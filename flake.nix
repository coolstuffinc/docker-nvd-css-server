{
  description = "SourcePawn Compilation Environment";
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; };
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config = { allowUnfree = true; }; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # 32-bit libs
          pkgsi686Linux.glibc
          pkgsi686Linux.stdenv.cc.cc.lib
          pkgsi686Linux.ncurses
          
          # Tools
          bash
          curl
          wget
          unzip
          git
          git-lfs
          binutils
          file
          patchelf
          openjdk17
          python3
        ];

        
        shellHook = ''
          # Directly construct the loader path from the 32-bit glibc store path
          export SP_LOADER="${pkgs.pkgsi686Linux.glibc}/lib/ld-linux.so.2"
          
          # Construct library paths reliably
          export LD_LIBRARY_PATH="${pkgs.pkgsi686Linux.glibc}/lib:${pkgs.pkgsi686Linux.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
          export PATH="$PATH:$(pwd)/scripts"
          
          echo "Nix Environment Loaded (Loader: $SP_LOADER)."
        '';
      };
    };
}
