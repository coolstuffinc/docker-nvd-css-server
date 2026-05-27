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
# Automatically find the 32-bit loader in the Nix environment
LOADER=\$(nix-shell shell.nix --run "find /nix/store -name ld-linux.so.2 -path '*/lib/*' | head -n 1")
nix-shell shell.nix --run "\$LOADER $SPCOMP \\\$@"
EOF
chmod +x spcomp-nix

echo "SourcePawn environment ready. Use ./spcomp-nix to compile."
