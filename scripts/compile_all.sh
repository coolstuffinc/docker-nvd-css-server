#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"
INCLUDE_DIR="$TOOLS_DIR/addons/sourcemod/scripting/include"
COMPILED_DIR="$(pwd)/compiled_plugins"

mkdir -p "$COMPILED_DIR"

# Find 32-bit loader
LOADER=$(find /nix/store -name ld-linux.so.2 -path '*/lib/*' | head -n 1)

if [ -z "$LOADER" ]; then
    echo "Error: 32-bit loader not found in Nix store!"
    exit 1
fi

echo "Using loader: $LOADER"

for spfile in src/*.sp; do
    if [ -s "$spfile" ]; then
        smxname=$(basename "${spfile%.sp}.smx")
        echo "----------------------------------------"
        echo "Compiling $spfile..."
        
        # We MUST pass the include directory and ensure paths are correct
        "$LOADER" "$SPCOMP" "$spfile" \
            -i"$INCLUDE_DIR" \
            -o"$COMPILED_DIR/$smxname" \
            -v1
            
        if [ $? -ne 0 ]; then
            echo "FAILED: $spfile"
            exit 1
        fi
    fi
done

echo "----------------------------------------"
echo "All plugins compiled successfully!"
