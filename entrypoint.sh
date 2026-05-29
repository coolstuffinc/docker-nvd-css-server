#!/bin/bash
set -e
trap '' TERM INT HUP

CSS_DIR="/home/steam/css"
CSTRIKE_DIR="$CSS_DIR/cstrike"

# Since we no longer use persistent volumes, we work directly in the container's /home/steam/css
# The files were baked in by build_server.sh during the Docker build.

echo "--- Server Environment Ready ---"

echo "--- Starting CSS Server ---"
cd "$CSS_DIR"
./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2

