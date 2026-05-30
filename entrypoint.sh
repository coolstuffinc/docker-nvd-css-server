#!/bin/bash
set -e
trap '' TERM INT HUP

CSS_DIR="/home/steam/css"
CSTRIKE_DIR="$CSS_DIR/cstrike"
SM_CFG_DIR="$CSTRIKE_DIR/cfg/sourcemod"

# Gera nvd_core.cfg a partir das env vars (usado pelo AutoExecConfig)
mkdir -p "$SM_CFG_DIR"
cat > "$SM_CFG_DIR/nvd_core.cfg" << EOF
// Auto-generated from environment variables
nvd_ollama_ip "${NVD_OLLAMA_IP:-172.17.0.1}"
nvd_ollama_port "${NVD_OLLAMA_PORT:-11433}"
nvd_ollama_model "${NVD_OLLAMA_MODEL:-nvd-admin}"
nvd_ollama_endpoint "${NVD_OLLAMA_ENDPOINT:-chat}"
nvd_ollama_debug "${NVD_OLLAMA_DEBUG:-1}"
EOF

echo "--- Server Environment Ready ---"
echo "Hostname: $CSS_HOSTNAME"
echo "Ollama target: http://${NVD_OLLAMA_IP:-172.17.0.1}:${NVD_OLLAMA_PORT:-11433}"

# Test Ollama connectivity if curl is available
OLLAMA_URL="http://${NVD_OLLAMA_IP:-172.17.0.1}:${NVD_OLLAMA_PORT:-11433}"
if curl -s --max-time 3 "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
    echo "Ollama connectivity: OK ($OLLAMA_URL)"
else
    echo "Ollama connectivity: FAILED ($OLLAMA_URL)"
    echo "Check: Ollama listening on 0.0.0.0:${NVD_OLLAMA_PORT:-11433}?"
    echo "Check: docker network / firewall?"
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

