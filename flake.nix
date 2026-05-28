{
  description = "SourcePawn Compilation Environment";
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; };
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config = { allowUnfree = true; }; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        name = "sourcepawn-env";
        
        buildInputs = with pkgs; [
          # Native tools
          gcc
          gnumake
          pkg-config
          bash
          wget
          curl
          unzip
          git
          git-lfs
          binutils
          file
          patchelf
          
          # 32-bit provider
          pkgsi686Linux.glibc
          pkgsi686Linux.stdenv.cc.cc.lib
          pkgsi686Linux.ncurses
        ];
        
        # Nix handles the setup and patching within the derivation
        # so everything is ready as soon as you enter 'nix develop'
        shellHook = ''
          export SP_LOADER="/lib/ld-linux.so.2"
          export LD_LIBRARY_PATH="${pkgs.pkgsi686Linux.glibc}/lib:${pkgs.pkgsi686Linux.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
          export PATH="$PATH:$(pwd)/scripts"
          
          # Run setup automatically if not done
          if [ ! -f .sourcepawn/addons/sourcemod/scripting/spcomp ]; then
            echo "Bootstrapping SourcePawn..."
            bash setup_sourcepawn.sh
          fi
          
          echo "Nix SourcePawn Environment Ready."
        '';
      };
    };
}
