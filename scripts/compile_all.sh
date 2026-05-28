#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
INCLUDE_DIR="$(pwd)/src/include"
COMPILED_DIR="$(pwd)/compiled_plugins"
CACHE_FILE=".sp_loader_cache"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

mkdir -p "$COMPILED_DIR"

if [ -n "$SP_LOADER" ]; then
    LOADER="$SP_LOADER"
elif [ -f "$CACHE_FILE" ]; then
    LOADER=$(cat "$CACHE_FILE")
else
    LOADER=$(find /nix/store -name ld-linux.so.2 -path '*/lib/*' | head -n 1)
    echo "$LOADER" > "$CACHE_FILE"
fi

for spfile in src/*.sp; do
    if [ -s "$spfile" ]; then
        smxname=$(basename "${spfile%.sp}.smx")
        echo "Compiling $spfile..."
        
        "$LOADER" "$SPCOMP" "$spfile" \
            -i"$TOOLS_DIR/addons/sourcemod/scripting/include" \
            -i"src" \
            -i"$INCLUDE_DIR" \
            -o"$COMPILED_DIR/$smxname" \
            -v1 -W0
            
        if [ $? -ne 0 ]; then
            echo "FAILED: $spfile"
            exit 1
        fi
    fi
done
