#!/usr/bin/env bash
set -e

# Directory for SourcePawn tools
TOOLS_DIR="$(pwd)/.sourcepawn"
mkdir -p "$TOOLS_DIR"

echo "Setting up SourcePawn environment..."

# Download SourceMod if missing (upgrading to 1.12 to fix compatibility issues)
if [ ! -f "$TOOLS_DIR/addons/sourcemod/scripting/spcomp" ]; then
    echo "Downloading SourceMod 1.12.0..."
    # Fetching stable 1.12.0 release
    wget -q -O "$TOOLS_DIR/sourcemod.tar.gz" https://sm.alliedmods.net/smdrop/1.12/sourcemod-1.12.0-git7236-linux.tar.gz
    tar -C "$TOOLS_DIR" -zxf "$TOOLS_DIR/sourcemod.tar.gz"
    rm "$TOOLS_DIR/sourcemod.tar.gz"
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
