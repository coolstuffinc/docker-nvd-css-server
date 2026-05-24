FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget lib32gcc-s1 lib32stdc++6 libtinfo5 unzip nginx && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash steam
WORKDIR /home/steam

USER steam

ARG ASSET_REF=assets

RUN wget -O /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xvzf /tmp/steamcmd_linux.tar.gz && \
    rm /tmp/steamcmd_linux.tar.gz

# Install CSS once to speed up container startup.
# SteamCMD requires +force_install_dir before +login.
RUN ./steamcmd.sh +force_install_dir /home/steam/css +login anonymous +app_update 232330 validate +quit

COPY --chown=steam:steam assets/ /tmp/assets/
RUN mkdir -p /tmp/mods /tmp/maps && \
    while read -r file; do \
        wget -q -O "/tmp/mods/${file}" "https://raw.githubusercontent.com/coolstuffinc/docker-steam-css/${ASSET_REF}/mods/${file}"; \
    done < /tmp/assets/mods.txt && \
    while read -r file; do \
        wget -q -O "/tmp/maps/${file}" "https://raw.githubusercontent.com/coolstuffinc/docker-steam-css/${ASSET_REF}/maps/${file}"; \
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
RUN ln -s /home/steam/linux32/ /home/steam/.steam/sdk32

RUN cd /home/steam/css/cstrike && \
    tar zxvf /tmp/mods/mmsource-1.10.6-linux.tar.gz && \
    tar zxvf /tmp/mods/sourcemod-1.7.3-git5275-linux.tar.gz && \
    unzip /tmp/mods/rankme.zip && \
    unzip /tmp/mods/bot2player.zip && \
    unzip /tmp/mods/save_scores.zip && \
    unzip /tmp/mods/enemies_left.zip && \
    unzip /tmp/mods/dropbomb1.1.zip && \
    mv /tmp/mods/mixmod.smx addons/sourcemod/plugins && \
    mv /tmp/mods/playerstacker.smx addons/sourcemod/plugins && \
    mv /tmp/mods/voicecomm.smx addons/sourcemod/plugins && \
    mv /tmp/mods/forceroundend.smx addons/sourcemod/plugins && \
    mv /tmp/mods/Cash.smx addons/sourcemod/plugins && \
    rm -rf /tmp/mods /tmp/assets

RUN mv /tmp/maps/* /home/steam/css/cstrike/maps/ && \
    rmdir /tmp/maps

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
