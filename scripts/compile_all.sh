#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
INCLUDE_DIR="$(pwd)/src/include"
COMPILED_DIR="$(pwd)/compiled_plugins"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

mkdir -p "$COMPILED_DIR"

# Patch the binary to use the loader from the Nix store
if [ -n "$SP_LOADER" ]; then
    patchelf --set-interpreter "$SP_LOADER" "$SPCOMP"
else
    echo "SP_LOADER not found!"
    exit 1
fi

chmod +x "$SPCOMP"

for spfile in src/*.sp; do
    if [ -s "$spfile" ]; then
        smxname=$(basename "${spfile%.sp}.smx")
        echo "Compiling $spfile..."
        
        "$SPCOMP" "$spfile" \
            -i"$TOOLS_DIR/addons/sourcemod/scripting/include" \
            -i"src" \
            -i"$INCLUDE_DIR" \
            -o"$COMPILED_DIR/$smxname" \
            -v1
            
        if [ $? -ne 0 ]; then
            echo "FAILED: $spfile"
            exit 1
        fi
    fi
done

echo "All plugins compiled successfully!"
