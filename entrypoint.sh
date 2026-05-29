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
    # Using verified URLs
    curl -L -o /tmp/base_mods/mmsource.tar.gz "https://github.com/alliedmodders/metamod-source/releases/download/1.12.0.1224/mmsource-1.12.0-git1224-linux.tar.gz"
    curl -L -o /tmp/base_mods/sourcemod.tar.gz "https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz"
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
    # Cleanup old legacy binaries that are now compiled from source or obsolete
    echo "Cleaning up obsolete plugins and files..."
    rm -f "$MODS_DIR/Cash.smx"
    rm -f "$MODS_DIR/bot2player.smx"
    rm -f "$MODS_DIR/bot2player_public.smx"
    rm -f "$MODS_DIR/dropbomb.smx"
    rm -f "$MODS_DIR/botdropbomb.smx.old"
    rm -f "$MODS_DIR/mmsource-1.10.6-linux.tar.gz"
    rm -f "$MODS_DIR/sourcemod-1.7.3-git5275-linux.tar.gz"
    rm -f "$MODS_DIR/bot2player.zip"
    rm -f "$MODS_DIR/dropbomb1.1.zip"
    rm -f "$MODS_DIR/enemies_left.zip"
    
    # Search for our plugins in the container, they might be in /home/steam/ci_mods instead
    CI_MODS_DIR="/home/steam/ci_mods"
    if [ -d "$CI_MODS_DIR" ]; then
        # Check if there are actually any .smx files before trying to copy
        if ls "$CI_MODS_DIR"/*.smx 1> /dev/null 2>&1; then
            echo "Applying CI-compiled plugins from $CI_MODS_DIR..."
            cp -v "$CI_MODS_DIR"/*.smx "$MODS_DIR/"
        else
            echo "CI_MODS_DIR exists but contains no .smx files."
        fi
    else
        echo "CI_MODS_DIR $CI_MODS_DIR not found, skipping."
    fi
    while read -r mod; do
        [ -z "$mod" ] || [[ "$mod" == *.zip ]] || [[ "$mod" == *.tar.gz ]] && continue
        # Only sync if not one of our compiled plugins
        if [ ! -f "$MODS_DIR/$mod" ]; then
            echo "Syncing mod: $mod"
            curl -L -o "$MODS_DIR/$mod" "$GITHUB_RAW/mods/$mod" || echo "Failed to sync $mod"
        fi
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
    
    # Inject dynamic Server IP for FastDL
    SERVER_IP=$(hostname -i | awk '{print $1}')
    sed -i "s|sv_downloadurl \".*\"|sv_downloadurl \"http://$SERVER_IP/maps/\"|g" "$CSTRIKE_DIR/cfg/server.cfg"

    echo "--- Incremental Sync Finished ---"
}

sync_from_github

cd "$CSS_DIR"
# No LD_PRELOAD needed for SourceMod 1.12+ (it's compatible with Ubuntu 22.04+)
./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2
