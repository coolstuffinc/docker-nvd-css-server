FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget lib32gcc-s1 lib32stdc++6 libtinfo5 unzip nginx lib32z1 && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash steam
WORKDIR /home/steam

USER steam

ARG ASSET_REF=assets

RUN wget -O /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xvzf /tmp/steamcmd_linux.tar.gz && \
    rm /tmp/steamcmd_linux.tar.gz

# Run steamcmd once just to let it self-update and create necessary state folders
RUN ./steamcmd.sh +quit

# Install CSS once to speed up container startup.
# SteamCMD requires +force_install_dir before +login.
RUN mkdir -p /home/steam/css && \
    ./steamcmd.sh +force_install_dir /home/steam/css +login anonymous +app_update 232330 validate +quit || :

COPY --chown=steam:steam assets/ /tmp/assets/
# Copy CI-compiled mods if they exist in the build context
COPY --chown=steam:steam ci_mods/ /tmp/ci_mods/
RUN mkdir -p /tmp/mods /tmp/maps && \
    while read -r file; do \
        [ -z "$file" ] && continue; \
        echo "Downloading mod: ${file}"; \
        wget -q -O "/tmp/mods/${file}" "https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/assets/mods/${file}" || echo "Failed to download ${file}"; \
    done < /tmp/assets/mods.txt && \
    while read -r file; do \
        [ -z "$file" ] && continue; \
        echo "Downloading map: ${file}"; \
        wget -q -O "/tmp/maps/${file}" "https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/assets/maps/${file}" || echo "Failed to download ${file}"; \
    done < /tmp/assets/maps.txt

ENV CSS_HOSTNAME=""
ENV CSS_PASSWORD=""
ENV RCON_PASSWORD=""
ENV STEAM_TOKEN=""

EXPOSE 27015/udp
EXPOSE 27015
EXPOSE 1200
EXPOSE 27005/udp
EXPOSE 27020/udp
EXPOSE 26901/udp

COPY --chown=steam:steam entrypoint.sh entrypoint.sh

# Support for 64-bit systems
# https://www.gehaxelt.in/blog/cs-go-missing-steam-slash-sdk32-slash-steamclient-dot-so/
RUN mkdir -p /home/steam/.steam && \
    ln -s /home/steam/linux32/ /home/steam/.steam/sdk32

RUN mkdir -p /home/steam/css/cstrike/addons/sourcemod/plugins && \
    mkdir -p /home/steam/css/cstrike/maps && \
    cd /home/steam/css/cstrike && \
    tar zxvf /tmp/mods/mmsource-1.10.6-linux.tar.gz && \
    tar zxvf /tmp/mods/sourcemod-1.7.3-git5275-linux.tar.gz && \
    unzip -o /tmp/mods/rankme.zip && \
    unzip -o /tmp/mods/bot2player.zip && \
    unzip -o /tmp/mods/save_scores.zip && \
    unzip -o /tmp/mods/enemies_left.zip && \
    unzip -o /tmp/mods/dropbomb1.1.zip && \
    mv /tmp/mods/mixmod.smx addons/sourcemod/plugins && \
    mv /tmp/mods/playerstacker.smx addons/sourcemod/plugins && \
    mv /tmp/mods/voicecomm.smx addons/sourcemod/plugins && \
    mv /tmp/mods/forceroundend.smx addons/sourcemod/plugins && \
    mv /tmp/mods/Cash.smx addons/sourcemod/plugins && \
    # APPLY CI PATCHES LAST (Overwrite any old versions from zips/wget)
    ([ -d /tmp/ci_mods ] && cp -v /tmp/ci_mods/*.smx addons/sourcemod/plugins/ || true) && \
    # MOVE MAPS
    (ls /tmp/maps/*.bsp >/dev/null 2>&1 && cp -v /tmp/maps/* /home/steam/css/cstrike/maps/ || echo "No maps to copy") && \
    rm -rf /tmp/mods /tmp/assets /tmp/ci_mods /tmp/maps

# Add default configuration files
COPY cfg/ /home/steam/css/cstrike/cfg
RUN true
COPY cfg/sourcemod/mods.cfg /home/steam/css/cstrike/cfg/sourcemod/mods.cfg
RUN true
COPY cfg/mapcycle.txt /home/steam/css/cstrike/mapcycle.txt
RUN true
COPY cfg/motd.txt /home/steam/css/cstrike/motd.txt
RUN true

CMD ["./entrypoint.sh"]
