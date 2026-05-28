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

# Ensure permissions
chmod +x "$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

echo "SourcePawn environment ready."
