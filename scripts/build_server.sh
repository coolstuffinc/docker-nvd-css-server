#!/bin/bash
set -e

CSS_BUNDLED="/home/steam/css_bundled"
CSTRIKE_BUNDLED="$CSS_BUNDLED/cstrike"
GITHUB_RAW="https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/refs/heads/assets"

echo "--- Installing Counter-Strike: Source (AppID 232330) ---"
mkdir -p "$CSS_BUNDLED"
/home/steam/steamcmd.sh +force_install_dir "$CSS_BUNDLED" +login anonymous +app_update 232330 validate +quit

echo "--- Installing Metamod & SourceMod & Extensions ---"
mkdir -p /tmp/base_mods
curl -L -o /tmp/base_mods/mmsource.tar.gz "https://github.com/alliedmodders/metamod-source/releases/download/1.12.0.1224/mmsource-1.12.0-git1224-linux.tar.gz"
curl -L -o /tmp/base_mods/sourcemod.tar.gz "https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz"
curl -L -o /tmp/base_mods/ripext.zip "https://github.com/ErikMinekus/sm-ripext/releases/download/1.3.2/sm-ripext-1.3.2-linux.zip"

tar -C "$CSTRIKE_BUNDLED" -zxf /tmp/base_mods/mmsource.tar.gz
tar -C "$CSTRIKE_BUNDLED" -zxf /tmp/base_mods/sourcemod.tar.gz
unzip -o /tmp/base_mods/ripext.zip -d "$CSTRIKE_BUNDLED"
rm -rf /tmp/base_mods

echo "--- Downloading Maps ---"
mkdir -p "$CSTRIKE_BUNDLED/maps"
if [ -f "/home/steam/assets/maps.txt" ]; then
    while read -r map; do
        [ -z "$map" ] && continue
        echo "Downloading $map..."
        curl -L -o "$CSTRIKE_BUNDLED/maps/$map" "$GITHUB_RAW/maps/$map"
    done < /home/steam/assets/maps.txt
fi

echo "--- Downloading Legacy Mods and Translations ---"
mkdir -p /tmp/zips
# We manually pull these zip files from assets to extract their translations, configs, etc.
for zip in bot2player.zip dropbomb1.1.zip enemies_left.zip rankme.zip save_scores.zip; do
    echo "Downloading $zip..."
    curl -L -o "/tmp/zips/$zip" "$GITHUB_RAW/mods/$zip" || true
    if [ -f "/tmp/zips/$zip" ]; then
        unzip -o "/tmp/zips/$zip" -d "$CSTRIKE_BUNDLED/" || true
    fi
done
rm -rf /tmp/zips

# Download any remaining smx directly (mixmod, voicecomm, rankme, etc)
if [ -f "/home/steam/assets/mods.txt" ]; then
    while read -r mod; do
        [ -z "$mod" ] || [[ "$mod" == *.zip ]] || [[ "$mod" == *.tar.gz ]] && continue
        echo "Downloading $mod..."
        curl -L -o "$CSTRIKE_BUNDLED/addons/sourcemod/plugins/$mod" "$GITHUB_RAW/mods/$mod" || true
    done < /home/steam/assets/mods.txt
fi

echo "--- Applying CI Compiled Plugins ---"
if ls /home/steam/ci_mods/*.smx 1> /dev/null 2>&1; then
    cp -v /home/steam/ci_mods/*.smx "$CSTRIKE_BUNDLED/addons/sourcemod/plugins/"
fi

echo "--- Applying Default Configs ---"
cp -rn /home/steam/cfg_defaults/* "$CSTRIKE_BUNDLED/cfg/" 2>/dev/null || true

# Ensure maplist.txt exists for mixmod
touch "$CSTRIKE_BUNDLED/maplist.txt"
touch "$CSTRIKE_BUNDLED/cfg/maplist.txt"

# Cleanup obsolete legacy binaries that might have been unzipped
rm -f "$CSTRIKE_BUNDLED/addons/sourcemod/plugins/Cash.smx"
rm -f "$CSTRIKE_BUNDLED/addons/sourcemod/plugins/bot2player.smx"
rm -f "$CSTRIKE_BUNDLED/addons/sourcemod/plugins/bot2player_public.smx"
rm -f "$CSTRIKE_BUNDLED/addons/sourcemod/plugins/dropbomb.smx"
rm -f "$CSTRIKE_BUNDLED/addons/sourcemod/plugins/botdropbomb.smx.old"

echo "--- Server Bundling Complete! ---"
