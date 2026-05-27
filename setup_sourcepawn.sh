#!/bin/bash
set -e

# Directory for SourcePawn tools
TOOLS_DIR="$(pwd)/.sourcepawn/tools"
mkdir -p "$TOOLS_DIR"

# Download Lysis decompiler (using a more reliable source if possible, or common mirror)
# Since I had trouble with direct GitHub URLs, let's try to find a known mirror or use a specific one
# For now, I will try a direct link to a known working version if I can find one.
# Given previous failures, I'll try to use a more generic approach or ask user if they have a preferred decompiler.

echo "Setting up SourcePawn environment..."

# Extract spcomp if not already available in a good path
SPCOMP=".sourcepawn/addons/sourcemod/scripting/spcomp"
if [ -f "$SPCOMP" ]; then
    echo "Found spcomp at $SPCOMP"
    chmod +x "$SPCOMP"
else
    echo "spcomp not found! Please ensure SourceMod is extracted to .sourcepawn"
    exit 1
fi

# Create a small wrapper script to run spcomp in the Nix FHS env
cat > spcomp-nix <<EOF
#!/bin/bash
nix-shell shell.nix --run ".sourcepawn/addons/sourcemod/scripting/spcomp \\\$@"
EOF
chmod +x spcomp-nix

echo "Created spcomp-nix wrapper."
