#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
INCLUDE_DIR="$(pwd)/src/include"
COMPILED_DIR="$(pwd)/compiled_plugins"
CACHE_FILE=".sp_loader_cache"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

mkdir -p "$COMPILED_DIR"

# Resolve loader: use env var, or cached file, or find it once
if [ -n "$SP_LOADER" ]; then
    LOADER="$SP_LOADER"
elif [ -f "$CACHE_FILE" ]; then
    LOADER=$(cat "$CACHE_FILE")
else
    echo "Loader not found in env or cache, searching (this is slow, but only once)..."
    LOADER=$(find /nix/store -name ld-linux.so.2 -path '*/lib/*' | head -n 1)
    echo "$LOADER" > "$CACHE_FILE"
fi

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
        
        "$LOADER" "$SPCOMP" "$spfile" \
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

echo "----------------------------------------"
echo "All plugins compiled successfully!"
