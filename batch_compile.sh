#!/usr/bin/env bash
mkdir -p compiled_plugins
COMPILER="./.sourcepawn/addons/sourcemod/scripting/spcomp64"
INCLUDES="-i./.sourcepawn/addons/sourcemod/scripting/include -i./src -i./src/include"

for spfile in src/*.sp; do
    [ -e "$spfile" ] || continue
    smxname=$(basename "${spfile%.sp}.smx")
    echo "Compiling $spfile..."
    $COMPILER $INCLUDES "$spfile" -o"compiled_plugins/$smxname"
done
echo "Done!"
