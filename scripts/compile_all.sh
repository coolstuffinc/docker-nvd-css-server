#!/usr/bin/env bash

TOOLS_DIR="$(pwd)/.sourcepawn"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"
INCLUDE_DIR="$TOOLS_DIR/addons/sourcemod/scripting/include"
COMPILED_DIR="$(pwd)/compiled_plugins"

mkdir -p "$COMPILED_DIR"

# Use loader from environment variable set in shell.nix
if [ -z "$SP_LOADER" ]; then
    echo "Error: SP_LOADER not found in environment. Are you running inside nix-shell?"
    exit 1
fi

LOADER="$SP_LOADER"
echo "Using loader: $LOADER"

FAILED=0
for spfile in src/*.sp; do
    if [ -s "$spfile" ]; then
        spname=$(basename "$spfile")
        smxname="${spname%.sp}.smx"
        echo "----------------------------------------"
        echo "Compiling $spfile..."
        
        # We MUST pass the include directory and ensure paths are correct
        # Running from project root
        "$LOADER" "$SPCOMP" "$spfile" \
            -i"$INCLUDE_DIR" \
            -i"src" \
            -o"$COMPILED_DIR/$smxname" \
            -v1
            
        if [ $? -ne 0 ]; then
            echo "FAILED: $spfile"
            FAILED=1
        fi
    fi
done

echo "----------------------------------------"
if [ $FAILED -eq 1 ]; then
    echo "Some plugins failed to compile!"
    exit 1
else
    echo "All plugins compiled successfully!"
fi
