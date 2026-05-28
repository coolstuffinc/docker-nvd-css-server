FROM ubuntu:22.04

# Install base dependencies (32-bit libs are essential for SRCDS and SourceMod)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget curl lib32gcc-s1 lib32stdc++6 libtinfo5 unzip lib32z1 && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash steam
WORKDIR /home/steam

USER steam

# Install SteamCMD
RUN wget -O /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xvzf /tmp/steamcmd_linux.tar.gz && \
    rm /tmp/steamcmd_linux.tar.gz && \
    ./steamcmd.sh +quit

# Copy local lists of assets (used by entrypoint for syncing)
COPY --chown=steam:steam assets/ /home/steam/assets/

# Copy default configurations
COPY --chown=steam:steam cfg/ /home/steam/cfg_defaults/

# Copy entrypoint
COPY --chown=steam:steam entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

# Setup Steam 64-bit compatibility link
RUN mkdir -p /home/steam/.steam && \
    ln -s /home/steam/linux32/ /home/steam/.steam/sdk32

ENV CSS_HOSTNAME="[N.V.D] MIX SERVER"
ENV CSS_PASSWORD=""
ENV RCON_PASSWORD=""
ENV STEAM_TOKEN=""

EXPOSE 27015/udp 27015 1200 27005/udp 27020/udp 26901/udp

# Entrypoint will handle incremental syncing and launching
ENTRYPOINT ["./entrypoint.sh"]
