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
# Since the container runs as 'steam', we cannot write to /etc/nginx/conf.d directly.
# However, nginx in the ubuntu image typically can be run if configured correctly,
# but we need to write the config to a location 'steam' has access to.

mkdir -p /home/steam/nginx_logs
cat << 'EOF' > /home/steam/nginx.conf
worker_processes 1;
daemon on;
error_log /home/steam/nginx_logs/error.log;
pid /home/steam/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/steam/nginx_logs/access.log;
    client_body_temp_path /home/steam/nginx_logs/client_body;
    fastcgi_temp_path /home/steam/nginx_logs/fastcgi_temp;
    proxy_temp_path /home/steam/nginx_logs/proxy_temp;
    scgi_temp_path /home/steam/nginx_logs/scgi_temp;
    uwsgi_temp_path /home/steam/nginx_logs/uwsgi_temp;
    server {
        listen 8080;
        location /maps/ {
            alias /home/steam/css/cstrike/maps/;
            autoindex on;
        }
    }
}
EOF

nginx -c /home/steam/nginx.conf

# Inject dynamic Server IP for FastDL. Note that we mapped 80 to 8080 or need to tell clients port 80.
# Wait, standard port 80 requires root. If we are running as steam, we must use a high port inside,
# and map it in docker-compose (e.g. 80:8080).
# I'll configure it to listen on 8080 inside the container.
SERVER_IP=$(hostname -i | awk '{print $1}')
# Nginx is listening on 8080 inside, but external clients will connect on whatever docker maps it to.
# Assuming standard 80 external mapping, we point sv_downloadurl to the external port. If 80 is used:
sed -i "s|sv_downloadurl \".*\"|sv_downloadurl \"http://$SERVER_IP:8080/maps/\"|g" "$CSTRIKE_DIR/cfg/server.cfg"


echo "--- Starting CSS Server ---"
cd "$CSS_DIR"
./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2

