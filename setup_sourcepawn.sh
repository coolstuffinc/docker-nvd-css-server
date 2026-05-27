#!/usr/bin/env bash
set -e

# Directory for SourcePawn tools
TOOLS_DIR="$(pwd)/.sourcepawn"
mkdir -p "$TOOLS_DIR"

echo "Setting up SourcePawn environment..."

# Download SourceMod if missing
if [ ! -f "$TOOLS_DIR/addons/sourcemod/scripting/spcomp" ]; then
    echo "Downloading SourceMod 1.7.3..."
    wget -q -O "$TOOLS_DIR/sourcemod.tar.gz" https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/assets/mods/sourcemod-1.7.3-git5275-linux.tar.gz
    tar -C "$TOOLS_DIR" -zxf "$TOOLS_DIR/sourcemod.tar.gz"
    rm "$TOOLS_DIR/sourcemod.tar.gz"
fi

# Install SMLib if missing
if [ ! -d "$TOOLS_DIR/addons/sourcemod/scripting/include/smlib" ]; then
    echo "Installing SMLib..."
    git clone --depth 1 https://github.com/bcserv/smlib.git "$TOOLS_DIR/smlib-source"
    cp -r "$TOOLS_DIR/smlib-source/scripting/include/"* "$TOOLS_DIR/addons/sourcemod/scripting/include/"
    rm -rf "$TOOLS_DIR/smlib-source"
fi

# Install common includes if missing
if [ ! -f "$TOOLS_DIR/addons/sourcemod/scripting/include/colors.inc" ]; then
    echo "Installing Colors include..."
    wget -q -O "$TOOLS_DIR/addons/sourcemod/scripting/include/colors.inc" https://raw.githubusercontent.com/alliedmodders/sourcemod/master/plugins/include/colors.inc || \
    wget -q -O "$TOOLS_DIR/addons/sourcemod/scripting/include/colors.inc" https://raw.githubusercontent.com/exvel/colors/master/colors.inc || true
fi

if [ ! -f "$TOOLS_DIR/addons/sourcemod/scripting/include/autoupdate.inc" ]; then
    echo "Installing AutoUpdate include..."
    wget -q -O "$TOOLS_DIR/addons/sourcemod/scripting/include/autoupdate.inc" https://raw.githubusercontent.com/GoDtm666/Auto-Update/master/autoupdate.inc || true
fi

SPCOMP="$TOOLS_DIR/addons/sourcemod/scripting/spcomp"
if [ -f "$SPCOMP" ]; then
    echo "Found spcomp at $SPCOMP"
    chmod +x "$SPCOMP"
else
    echo "Error: spcomp not found after setup!"
    exit 1
fi

# Create a small wrapper script to run spcomp in the Nix environment
cat > spcomp-nix <<EOF
#!/usr/bin/env bash
nix-shell shell.nix --run "bash scripts/compile_all.sh"
EOF
chmod +x spcomp-nix
chmod +x scripts/compile_all.sh

echo "SourcePawn environment ready. Run ./spcomp-nix to compile all plugins in src/"
