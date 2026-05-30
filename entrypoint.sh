#!/bin/bash
set -e
trap '' TERM INT HUP

CSS_DIR="/home/steam/css"
CSTRIKE_DIR="$CSS_DIR/cstrike"

echo "--- Server Environment Ready ---"
echo "Hostname: $CSS_HOSTNAME"
echo "Ollama target: http://${NVD_OLLAMA_IP:-172.17.0.1}:${NVD_OLLAMA_PORT:-11433}"

# Test Ollama connectivity if curl is available
if curl -s --max-time 3 "http://${NVD_OLLAMA_IP:-172.17.0.1}:${NVD_OLLAMA_PORT:-11433}/api/tags" > /dev/null 2>&1; then
    echo "Ollama connectivity: OK"
else
    echo "Ollama connectivity: FAILED (will retry in-game via sm_ollama_test)"
fi

echo "--- Starting CSS Server ---"
cd "$CSS_DIR"
./srcds_run -game cstrike \
            +exec server.cfg \
            +hostname "$CSS_HOSTNAME" \
            +sv_password "$CSS_PASSWORD" \
            +rcon_password "$RCON_PASSWORD" \
            +sv_setsteamaccount "$STEAM_TOKEN" \
            +map de_dust2

