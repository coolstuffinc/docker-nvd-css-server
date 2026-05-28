#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

echo "Bootstrapping spcomp..."

# Install build tools if missing (CI env)
if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y libc6-i386 patchelf
fi

# Find the 32-bit loader
LOADER=$(find /lib /lib32 /usr/lib32 -name "ld-linux.so.2" | head -n 1)

if [ -z "$LOADER" ]; then
    echo "Error: Could not find 32-bit loader (ld-linux.so.2)"
    exit 1
fi

echo "Patching spcomp with loader: $LOADER"
patchelf --set-interpreter "$LOADER" "$SPCOMP"

chmod +x "$SPCOMP"
echo "spcomp patched and ready."
