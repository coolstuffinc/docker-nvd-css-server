#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
mkdir -p "$TOOLS_DIR"

echo "Installing native 32-bit build tools..."
sudo apt-get update
sudo apt-get install -y g++-multilib libc6-dev-i386 lib32stdc++6 patchelf

echo "Setting up SourcePawn environment..."

# Download SourceMod 1.10.0 (Supports transitional syntax)
if [ ! -f "$TOOLS_DIR/addons/sourcemod/scripting/spcomp" ]; then
    echo "Downloading SourceMod 1.10.0..."
    wget -q -O "$TOOLS_DIR/sourcemod.tar.gz" https://sm.alliedmods.net/smdrop/1.10/sourcemod-1.10.0-git6528-linux.tar.gz
    tar -C "$TOOLS_DIR" -zxf "$TOOLS_DIR/sourcemod.tar.gz"
    rm "$TOOLS_DIR/sourcemod.tar.gz"
fi

# Robustly find spcomp
SPCOMP=$(find "$TOOLS_DIR" -name "spcomp" | head -n 1)
DEST="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

if [ -f "$SPCOMP" ]; then
    echo "Found spcomp at $SPCOMP"
    
    # Use standard 32-bit loader path on Ubuntu
    LOADER="/lib/ld-linux.so.2"

    echo "Patching spcomp with loader: $LOADER"
    patchelf --set-interpreter "$LOADER" "$SPCOMP"
    chmod +x "$SPCOMP"
    
    # Move to the expected location ONLY if not already there
    if [ "$SPCOMP" != "$DEST" ]; then
        mkdir -p "$(dirname "$DEST")"
        mv "$SPCOMP" "$DEST"
    fi
else
    echo "Error: spcomp not found after extraction!"
    exit 1
fi

echo "SourcePawn environment ready."
