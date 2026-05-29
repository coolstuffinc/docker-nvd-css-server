# Stage 1: Build SourcePawn plugins
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates lib32gcc-s1 lib32stdc++6 && \
    rm -rf /var/lib/apt/lists/*

RUN wget -q -O /tmp/sm.tar.gz https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz && \
    tar -C /tmp -zxf /tmp/sm.tar.gz && rm /tmp/sm.tar.gz

RUN wget -q -O /tmp/ripext.zip https://github.com/ErikMinekus/sm-ripext/releases/download/1.3.2/sm-ripext-1.3.2-linux.zip && \
    unzip -q -o /tmp/ripext.zip -d /tmp && rm /tmp/ripext.zip

COPY src/ /src/
RUN mkdir /output && \
    for spfile in /src/*.sp; do \
        [ -e "$spfile" ] || continue; \
        smxname=$(basename "${spfile%.sp}.smx"); \
        echo "Compiling $smxname..."; \
        /tmp/addons/sourcemod/scripting/spcomp \
            -i/tmp/addons/sourcemod/scripting/include \
            -i/src \
            -i/src/include \
            "$spfile" \
            -o"/output/$smxname" || \
        echo "Warning: Failed to compile $spfile, skipping..."; \
    done

# Stage 2: Runtime
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget curl lib32gcc-s1 lib32stdc++6 libtinfo5 unzip && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash steam
WORKDIR /home/steam
USER steam

RUN wget -q -O /tmp/steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -C /home/steam -zxf /tmp/steamcmd.tar.gz && rm /tmp/steamcmd.tar.gz && \
    ./steamcmd.sh +quit

RUN mkdir -p /home/steam/css && \
    ./steamcmd.sh +force_install_dir /home/steam/css +login anonymous +app_update 232330 validate +quit

RUN curl -L -o /tmp/mmsource.tar.gz https://github.com/alliedmodders/metamod-source/releases/download/1.12.0.1224/mmsource-1.12.0-git1224-linux.tar.gz && \
    tar -C /home/steam/css/cstrike -zxf /tmp/mmsource.tar.gz && rm /tmp/mmsource.tar.gz && \
    curl -L -o /tmp/sourcemod.tar.gz https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz && \
    tar -C /home/steam/css/cstrike -zxf /tmp/sourcemod.tar.gz && rm /tmp/sourcemod.tar.gz && \
    curl -L -o /tmp/ripext.zip https://github.com/ErikMinekus/sm-ripext/releases/download/1.3.2/sm-ripext-1.3.2-linux.zip && \
    unzip -o /tmp/ripext.zip -d /home/steam/css/cstrike && rm /tmp/ripext.zip

COPY assets/maps.txt /tmp/maps.txt
RUN mkdir -p /home/steam/css/cstrike/maps && \
    while read -r map; do \
        [ -z "$map" ] && continue; \
        curl -L -o "/home/steam/css/cstrike/maps/$map" \
            "https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/refs/heads/assets/maps/$map"; \
    done < /tmp/maps.txt && rm /tmp/maps.txt

RUN for zip in bot2player.zip dropbomb1.1.zip enemies_left.zip rankme.zip save_scores.zip; do \
        echo "Downloading $zip..."; \
        curl -L -o "/tmp/$zip" \
            "https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/refs/heads/assets/mods/$zip" || true; \
        if [ -f "/tmp/$zip" ]; then \
            unzip -o "/tmp/$zip" -d "/home/steam/css/cstrike/" || true; \
        fi; \
    done && rm -f /tmp/*.zip

COPY assets/mods.txt /tmp/mods.txt
RUN while read -r mod; do \
        [ -z "$mod" ] && continue; \
        [[ "$mod" == *.zip ]] || [[ "$mod" == *.tar.gz ]] && continue; \
        echo "Downloading $mod..."; \
        curl -L -o "/home/steam/css/cstrike/addons/sourcemod/plugins/$mod" \
            "https://media.githubusercontent.com/media/coolstuffinc/docker-nvd-css-server/refs/heads/assets/mods/$mod" || true; \
    done < /tmp/mods.txt && rm /tmp/mods.txt

RUN rm -f /home/steam/css/cstrike/addons/sourcemod/plugins/Cash.smx && \
    rm -f /home/steam/css/cstrike/addons/sourcemod/plugins/bot2player.smx && \
    rm -f /home/steam/css/cstrike/addons/sourcemod/plugins/bot2player_public.smx && \
    rm -f /home/steam/css/cstrike/addons/sourcemod/plugins/dropbomb.smx && \
    rm -f /home/steam/css/cstrike/addons/sourcemod/plugins/botdropbomb.smx.old

COPY --from=builder --chown=steam:steam /output/*.smx /home/steam/css/cstrike/addons/sourcemod/plugins/
COPY --chown=steam:steam gamedata/ /home/steam/css/cstrike/gamedata/
COPY --chown=steam:steam cfg/ /home/steam/css/cstrike/cfg/
COPY --chown=steam:steam entrypoint.sh /home/steam/entrypoint.sh

RUN touch /home/steam/css/cstrike/maplist.txt && \
    touch /home/steam/css/cstrike/cfg/maplist.txt

ENV CSS_HOSTNAME="[N.V.D] MIX SERVER"
EXPOSE 27015/udp 27015 1200 27005/udp 27020/udp 26901/udp

ENTRYPOINT ["./entrypoint.sh"]
