{ pkgs ? import <nixpkgs> {} }:

let
  # Access the 32-bit x86 package set explicitly
  pkgs32 = pkgs.pkgsi686Linux;
in
pkgs.mkShell {
  name = "spcomp-32bit-env";

  # Provide the runtime tools and native build dependencies
  buildInputs = with pkgs; [
    # Basic tools
    bash
    wget
    curl
    unzip
    git
    git-lfs
    binutils
    file
    patchelf
  ];

  shellHook = ''
    # 32-bit libraries required by the compiler
    export NIX_32_LINKER="$(cat ${pkgs32.glibc}/nix-support/dynamic-linker)"
    export NIX_32_LDPATH="${pkgs.lib.makeLibraryPath [ pkgs32.glibc pkgs32.stdenv.cc.cc.lib ]}"
    
    # Path to the compiler
    export SPCOMP="$(pwd)/.sourcepawn/addons/sourcemod/scripting/spcomp"

    if [ -f "$SPCOMP" ]; then
      echo "⚡ Found spcomp. Patching interpreter to use 32-bit Nix store loader..."
      chmod +x "$SPCOMP"
      
      # Permanently update the interpreter path inside the binary
      patchelf --set-interpreter "$NIX_32_LINKER" "$SPCOMP"
      patchelf --set-rpath "$NIX_32_LDPATH" "$SPCOMP"
      
      echo "✅ spcomp successfully patched!"
    else
      echo "⚠️  spcomp not found at $SPCOMP. Run setup_sourcepawn.sh first."
    fi
    
    export PATH="$PATH:$(pwd)/scripts"
  '';
}
