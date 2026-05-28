{
  description = "SourcePawn Compilation Environment";
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; };
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # Create an FHS environment for 32-bit SourceMod binaries
      fhs = pkgs.buildFHSEnv {
        name = "sp-fhs";
        targetPkgs = pkgs: with pkgs; [
          pkgsi686Linux.glibc
          pkgsi686Linux.stdenv.cc.cc.lib
          pkgsi686Linux.ncurses
          bash
          coreutils
        ];
        runScript = "bash";
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ fhs ];
        shellHook = ''
          echo "Entering SourcePawn FHS environment..."
          exec sp-fhs
        '';
      };
    };
}
