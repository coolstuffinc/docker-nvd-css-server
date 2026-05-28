#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
# Wipe the corrupted tools directory
rm -rf "$TOOLS_DIR"
mkdir -p "$TOOLS_DIR"

echo "Downloading SourceMod 1.12.0..."
wget -q -O "$TOOLS_DIR/sourcemod.tar.gz" https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz

echo "Extracting..."
tar -C "$TOOLS_DIR" -zxf "$TOOLS_DIR/sourcemod.tar.gz"
rm "$TOOLS_DIR/sourcemod.tar.gz"

SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

if [ -f "$SPCOMP" ]; then
    chmod +x "$SPCOMP"
    echo "Compiler extracted successfully."
    file "$SPCOMP"
else
    echo "Error: spcomp extraction failed!"
    exit 1
fi
