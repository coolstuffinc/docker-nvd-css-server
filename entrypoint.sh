#!/bin/bash
set -e
trap '' TERM INT HUP

CSS_DIR="/home/steam/css"
CSTRIKE_DIR="$CSS_DIR/cstrike"
MODS_DIR="$CSTRIKE_DIR/addons/sourcemod/plugins"
MAPS_DIR="$CSTRIKE_DIR/maps"
GITHUB_RAW="https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/assets"

# 1. Bootstrapping (If volume is empty)
if [ ! -f "$CSS_DIR/srcds_run" ]; then
    echo "--- Initial CSS Installation ---"
    ./steamcmd.sh +force_install_dir "$CSS_DIR" +login anonymous +app_update 232330 validate +quit
fi

# 2. Base Addons (Metamod/SourceMod)
if [ ! -d "$CSTRIKE_DIR/addons/sourcemod" ]; then
    echo "--- Installing Base Addons ---"
    mkdir -p /tmp/base_mods
    # Using curl -L to follow redirects (essential for LFS)
    curl -L -o /tmp/base_mods/mmsource.tar.gz "$GITHUB_RAW/mods/mmsource-1.10.6-linux.tar.gz"
    curl -L -o /tmp/base_mods/sourcemod.tar.gz "$GITHUB_RAW/mods/sourcemod-1.7.3-git5275-linux.tar.gz"
    tar -C "$CSTRIKE_DIR" -zxf /tmp/base_mods/mmsource.tar.gz
    tar -C "$CSTRIKE_DIR" -zxf /tmp/base_mods/sourcemod.tar.gz
    rm -rf /tmp/base_mods
fi

# 3. Incremental Sync from GitHub
sync_from_github() {
    echo "--- Incremental Sync Starting ---"
    
    # Sync Mods
    if [ -f "assets/mods.txt" ]; then
        echo "Checking for mod updates..."
        mkdir -p "$MODS_DIR"
        while read -r mod; do
            [ -z "$mod" ] || [[ "$mod" == *.zip ]] || [[ "$mod" == *.tar.gz ]] && continue
            echo "Syncing mod: $mod"
            curl -L -o "$MODS_DIR/$mod" "$GITHUB_RAW/mods/$mod" || echo "Failed to sync $mod"
        done < assets/mods.txt
    fi

    # Sync Maps
    if [ -f "assets/maps.txt" ]; then
        echo "Checking for map updates..."
        mkdir -p "$MAPS_DIR"
        while read -r map; do
            [ -z "$map" ] && continue
            if [ ! -f "$MAPS_DIR/$map" ]; then
                echo "Downloading new map: $map"
                curl -L -o "$MAPS_DIR/$map" "$GITHUB_RAW/maps/$map" || echo "Failed to sync $map"
            fi
        done < assets/maps.txt
    fi
    
    # Sync Configs (Apply defaults if missing)
    if [ -d "/home/steam/cfg_defaults" ]; then
        cp -rn /home/steam/cfg_defaults/* "$CSTRIKE_DIR/cfg/" 2>/dev/null || true
    fi
    
    echo "--- Incremental Sync Finished ---"
}

sync_from_github

# 4. Optional Full Update
if [ "$1" == "update" ]; then
	echo "Running SteamCMD full verification..."
	./steamcmd.sh +force_install_dir "$CSS_DIR" +login anonymous +app_update 232330 validate +quit
fi

cd "$CSS_DIR"
# Fix for "undefined symbol: floorf"
# Prepend 32-bit library path
export LD_LIBRARY_PATH="/usr/lib32:$LD_LIBRARY_PATH"

./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2
