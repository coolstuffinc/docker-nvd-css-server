#!/usr/bin/env bash
mkdir -p compiled_plugins
COMPILER="./.sourcepawn/addons/sourcemod/scripting/spcomp64"
INCLUDES="-i./.sourcepawn/addons/sourcemod/scripting/include -i./src -i./src/include"

for spfile in src/*.sp; do
    [ -e "$spfile" ] || continue
    smxname=$(basename "${spfile%.sp}.smx")
    echo "Compiling $spfile..."
    # Don't fail the entire build just because one broken legacy plugin fails to compile
    $COMPILER $INCLUDES "$spfile" -o"compiled_plugins/$smxname" || echo "Warning: Failed to compile $spfile, skipping..."
done
echo "Done!"
