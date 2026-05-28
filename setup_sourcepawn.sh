#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
mkdir -p "$TOOLS_DIR"

echo "Installing native 32-bit build tools..."
sudo apt-get update
sudo apt-get install -y g++-multilib libc6-dev-i386 lib32stdc++6 patchelf

echo "Setting up SourcePawn environment..."

# Download SourceMod 1.12.0
if [ ! -f "$TOOLS_DIR/addons/sourcemod/scripting/spcomp" ]; then
    echo "Downloading SourceMod 1.12.0..."
    wget -q -O "$TOOLS_DIR/sourcemod.tar.gz" https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz
    tar -C "$TOOLS_DIR" -zxf "$TOOLS_DIR/sourcemod.tar.gz"
    rm "$TOOLS_DIR/sourcemod.tar.gz"
fi

# Robustly find spcomp after potential sub-directory extraction
SPCOMP=$(find "$TOOLS_DIR" -name "spcomp" | head -n 1)

if [ -f "$SPCOMP" ]; then
    echo "Found spcomp at $SPCOMP"
    
    # Use standard 32-bit loader path on Ubuntu
    LOADER="/lib/ld-linux.so.2"

    echo "Patching spcomp with loader: $LOADER"
    patchelf --set-interpreter "$LOADER" "$SPCOMP"
    chmod +x "$SPCOMP"
    
    # Move to the expected location just in case
    mkdir -p "$TOOLS_DIR/addons/sourcemod/scripting"
    mv "$SPCOMP" "$TOOLS_DIR/addons/sourcemod/scripting/spcomp"
else
    echo "Error: spcomp not found after extraction!"
    exit 1
fi

echo "SourcePawn environment ready."
