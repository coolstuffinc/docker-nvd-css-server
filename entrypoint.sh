#!/bin/bash
set -e
trap '' TERM INT HUP

MODS_DIR="/home/steam/css/cstrike/addons/sourcemod/plugins"
MAPS_DIR="/home/steam/css/cstrike/maps"
GITHUB_RAW="https://raw.githubusercontent.com/coolstuffinc/docker-nvd-css-server/assets"

# Ensure directories exist
mkdir -p "$MODS_DIR"
mkdir -p "$MAPS_DIR"

# Incremental Sync Function
sync_from_github() {
    echo "--- Incremental Sync Starting ---"
    
    # Sync Mods
    if [ -f "assets/mods.txt" ]; then
        echo "Checking for mod updates..."
        while read -r mod; do
            [ -z "$mod" ] && continue
            echo "Syncing mod: $mod"
            wget -q -O "$MODS_DIR/$mod" "$GITHUB_RAW/mods/$mod" || echo "Failed to sync $mod"
        done < assets/mods.txt
    fi

    # Sync Maps
    if [ -f "assets/maps.txt" ]; then
        echo "Checking for map updates..."
        while read -r map; do
            [ -z "$map" ] && continue
            if [ ! -f "$MAPS_DIR/$map" ]; then
                echo "Downloading new map: $map"
                wget -q -O "$MAPS_DIR/$map" "$GITHUB_RAW/maps/$map" || echo "Failed to sync $map"
            fi
        done < assets/maps.txt
    fi
    
    echo "--- Incremental Sync Finished ---"
}

# Run sync before anything else
sync_from_github

# Ensure CSS is up to date only if requested
if [ "$1" == "update" ]; then
	echo "Running SteamCMD full verification (this may take a while)..."
	./steamcmd.sh +login anonymous +force_install_dir ./css +app_update 232330 validate +quit
fi

if [ -d /home/steam/htdocs ]; then
	echo "Copying htdocs..."
	mkdir -p /home/steam/htdocs/cstrike
	cp -fR /home/steam/css/cstrike/maps /home/steam/htdocs/cstrike
	cp -fR /home/steam/css/cstrike/sound /home/steam/htdocs/cstrike
fi

cd css
# Fix for "undefined symbol: floorf" in older SourceMod on newer Ubuntu
export LD_PRELOAD="/lib32/libm.so.6"
./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2
