#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
mkdir -p "$TOOLS_DIR"

echo "Setting up SourcePawn environment..."

# Download SourceMod 1.12.0
if [ ! -f "$TOOLS_DIR/addons/sourcemod/scripting/spcomp" ]; then
    echo "Downloading SourceMod 1.12.0..."
    wget -q -O "$TOOLS_DIR/sourcemod.tar.gz" https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz
    tar -C "$TOOLS_DIR" -zxf "$TOOLS_DIR/sourcemod.tar.gz"
    rm "$TOOLS_DIR/sourcemod.tar.gz"
fi

# Locate the compiler
SPCOMP=$(find "$TOOLS_DIR" -name "spcomp" | head -n 1)
DEST="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"
mkdir -p "$(dirname "$DEST")"

if [ -f "$SPCOMP" ]; then
    echo "Found spcomp at $SPCOMP"
    # Only move if the source and destination are different files
    if [ "$SPCOMP" != "$DEST" ]; then
        mv "$SPCOMP" "$DEST"
    fi
    chmod +x "$DEST"
else
    echo "Error: spcomp not found after extraction!"
    exit 1
fi

echo "SourcePawn environment ready."
