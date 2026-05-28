#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
INCLUDE_DIR="$(pwd)/src/include"
COMPILED_DIR="$(pwd)/compiled_plugins"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

mkdir -p "$COMPILED_DIR"

# Ensure permissions
chmod +x "$SPCOMP"

for spfile in src/*.sp; do
    if [ -s "$spfile" ]; then
        smxname=$(basename "${spfile%.sp}.smx")
        echo "Compiling $spfile..."
        
        # Native execution in Ubuntu runner
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
