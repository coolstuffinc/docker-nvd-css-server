#!/usr/bin/env bash
set -e

TOOLS_DIR="$(pwd)/.sourcepawn"
INCLUDE_DIR="$(pwd)/src/include"
COMPILED_DIR="$(pwd)/compiled_plugins"
SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"

mkdir -p "$COMPILED_DIR"

compile_plugin() {
    local spfile=$1
    local smxname=$2
    echo "Compiling $spfile -> $smxname..."
    "$SPCOMP" "$spfile" \
        -i"$TOOLS_DIR/addons/sourcemod/scripting/include" \
        -i"src" \
        -i"$INCLUDE_DIR" \
        -o"$COMPILED_DIR/$smxname" \
        -v1
}

# Explicitly map new source names to old .smx output names
compile_plugin "src/bot2player.sp" "bot2player_public.smx"
compile_plugin "src/botdropbomb.sp" "dropbomb1.1.smx"
compile_plugin "src/givecash.sp" "Cash.smx"
compile_plugin "src/enemies_left.sp" "enemies_left.smx"
compile_plugin "src/forceroundend.sp" "forceroundend.smx"
compile_plugin "src/playerstacker.sp" "playerstacker.smx"
compile_plugin "src/rankme.sp" "rankme.smx"
compile_plugin "src/llama_admin.sp" "llama_admin.smx"

echo "All plugins compiled successfully!"
