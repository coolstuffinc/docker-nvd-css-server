FROM ubuntu:22.04

# Install base dependencies (32-bit libs are essential for SRCDS, SourceMod, and compilation)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget curl lib32gcc-s1 lib32stdc++6 libtinfo5 unzip nginx \
    g++-multilib libc6-dev-i386 patchelf make && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash steam
WORKDIR /home/steam

USER steam

# Install SteamCMD
RUN wget -O /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xvzf /tmp/steamcmd_linux.tar.gz && \
    rm /tmp/steamcmd_linux.tar.gz && \
    ./steamcmd.sh +quit

# Bootstrap SourceMod (for spcomp compiler + includes)
RUN mkdir -p .sourcepawn && \
    wget -q -O .sourcepawn/sourcemod.tar.gz https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz && \
    tar -C .sourcepawn -zxf .sourcepawn/sourcemod.tar.gz && \
    rm .sourcepawn/sourcemod.tar.gz

# Copy Source Code and Includes
COPY --chown=steam:steam src/ /home/steam/src/

# Compile Plugins Natively inside Docker (Ensures ABI compatibility)
RUN mkdir -p css/cstrike/addons/sourcemod/plugins && \
    SPCOMP=.sourcepawn/addons/sourcemod/scripting/spcomp && \
    INCLUDES=.sourcepawn/addons/sourcemod/scripting/include && \
    chmod +x "$SPCOMP" && \
    for spfile in /home/steam/src/*.sp; do \
        [ -f "$spfile" ] || continue; \
        smxname=$(basename "${spfile%.sp}.smx"); \
        echo "Compiling $spfile..."; \
        "$SPCOMP" "$spfile" -i"$INCLUDES" -i"/home/steam/src/include" -o"css/cstrike/addons/sourcemod/plugins/$smxname" -v1; \
    done

# Install CSS
RUN ./steamcmd.sh +force_install_dir /home/steam/css +login anonymous +app_update 232330 validate +quit || :

# Copy assets and entrypoint
COPY --chown=steam:steam assets/ /home/steam/assets/
COPY --chown=steam:steam cfg/ /home/steam/cfg_defaults/
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

ENTRYPOINT ["./entrypoint.sh"]
