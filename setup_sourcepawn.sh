#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
# Wipe the corrupted tools directory
rm -rf "$TOOLS_DIR"
mkdir -p "$TOOLS_DIR"

echo "Downloading SourceMod 1.12.0..."
wget -q -O "$TOOLS_DIR/sourcemod.tar.gz" https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz

echo "Downloading REST in Pawn (ripext)..."
wget -q -O "$TOOLS_DIR/ripext.zip" https://github.com/ErikMinekus/sm-ripext/releases/download/1.3.2/sm-ripext-1.3.2-linux.zip

echo "Extracting..."
tar -C "$TOOLS_DIR" -zxf "$TOOLS_DIR/sourcemod.tar.gz"
unzip -q -o "$TOOLS_DIR/ripext.zip" -d "$TOOLS_DIR"
rm "$TOOLS_DIR/sourcemod.tar.gz" "$TOOLS_DIR/ripext.zip"

SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

if [ -f "$SPCOMP" ]; then
    chmod +x "$SPCOMP"
    echo "Compiler extracted successfully."
    file "$SPCOMP"
else
    echo "Error: spcomp extraction failed!"
    exit 1
fi

