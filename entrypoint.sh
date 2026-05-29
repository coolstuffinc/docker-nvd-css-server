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

# Start Nginx in background to serve maps locally
echo "--- Starting Nginx for FastDL ---"
mkdir -p /var/log/nginx
echo "server {
    listen 80;
    location /maps/ {
        alias /home/steam/css/cstrike/maps/;
        autoindex on;
    }
}" > /etc/nginx/conf.d/default.conf
nginx

# Inject dynamic Server IP for FastDL
SERVER_IP=$(hostname -i | awk '{print $1}')
sed -i "s|sv_downloadurl \".*\"|sv_downloadurl \"http://$SERVER_IP/maps/\"|g" "$CSTRIKE_DIR/cfg/server.cfg"

echo "--- Starting CSS Server ---"
cd "$CSS_DIR"
./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2

