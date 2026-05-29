#!/bin/bash
set -e
trap '' TERM INT HUP

CSS_DIR="/home/steam/css"
CSS_BUNDLED="/home/steam/css_bundled"
CSTRIKE_DIR="$CSS_DIR/cstrike"

echo "--- Checking Volume Synchronization ---"
if [ ! -f "$CSS_DIR/srcds_run" ]; then
    echo "--- Provisioning CSS Server from Bundled Image ---"
    cp -a "$CSS_BUNDLED/"* "$CSS_DIR/"
    echo "--- Provisioning Complete ---"
else
    echo "--- Existing Volume Detected, performing rapid sync of custom assets ---"
    cp -a "$CSS_BUNDLED/cstrike/addons/sourcemod/plugins/"* "$CSTRIKE_DIR/addons/sourcemod/plugins/" || true
    cp -a "$CSS_BUNDLED/cstrike/addons/sourcemod/translations/"* "$CSTRIKE_DIR/addons/sourcemod/translations/" || true
    cp -a "$CSS_BUNDLED/cstrike/addons/sourcemod/gamedata/"* "$CSTRIKE_DIR/addons/sourcemod/gamedata/" || true
    cp -a "$CSS_BUNDLED/cstrike/maps/"* "$CSTRIKE_DIR/maps/" || true
    cp -rn "$CSS_BUNDLED/cstrike/cfg/"* "$CSTRIKE_DIR/cfg/" || true
    
    # Cleanup legacy binaries
    rm -f "$CSTRIKE_DIR/addons/sourcemod/plugins/Cash.smx"
    rm -f "$CSTRIKE_DIR/addons/sourcemod/plugins/bot2player.smx"
    rm -f "$CSTRIKE_DIR/addons/sourcemod/plugins/bot2player_public.smx"
    rm -f "$CSTRIKE_DIR/addons/sourcemod/plugins/dropbomb.smx"
    rm -f "$CSTRIKE_DIR/addons/sourcemod/plugins/botdropbomb.smx.old"
fi

# Inject dynamic Server IP for FastDL. Note that we mapped 80 to 8080 or need to tell clients port 80.
# Wait, standard port 80 requires root. If we are running as steam, we must use a high port inside,
# and map it in docker-compose (e.g. 80:8080).
# I'll configure it to listen on 8080 inside the container.
# Nginx removed in favor of GitHub FastDL.



echo "--- Starting CSS Server ---"
cd "$CSS_DIR"
./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2

