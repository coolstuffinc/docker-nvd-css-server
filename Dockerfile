# Stage 1: Build SourcePawn plugins
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl unzip ca-certificates lib32gcc-s1 lib32stdc++6 \
    git build-essential g++-multilib libstdc++6 lib32stdc++6 \
    python3 python3-pip clang perl && \
    rm -rf /var/lib/apt/lists/*

# Clone build dependencies pinned
RUN git clone --branch 1.12.0.7236 --depth 1 https://github.com/alliedmodders/sourcemod.git /sourcemod && \
    git -C /sourcemod submodule update --init --recursive && \
    git clone https://github.com/alliedmodders/ambuild.git /ambuild && \
    pip3 install ./ambuild

# Compile plugins and extensions
RUN mkdir /output && \
    git clone https://github.com/14NGiestas/sm-ripext.git /ripext && \
    mkdir /ripext/build && \
    cp /etc/ssl/certs/ca-certificates.crt /ripext/build/ca-bundle.crt && \
    cd /ripext/build && \
    python3 ../configure.py --enable-optimize --sm-path=/sourcemod --targets=x86 && \
    ambuild && \
    find . -name "rip.ext.so" -exec cp {} /output/ \; && \
    find . -name "rip.ext.txt" -exec cp {} /output/ \; && \
    touch /output/rip.ext.so /output/rip.ext.txt && \
    find /src/mods/ -name "*.sp" ! -path "*/mixmod/*" | while read spfile; do \
        smxname=$(basename "${spfile%.sp}.smx"); \
        echo "Compiling $smxname..."; \
        /tmp/addons/sourcemod/scripting/spcomp \
            -i/tmp/addons/sourcemod/scripting/include \
            -i/src \
            -i/src/mods/include \
            "$spfile" \
            -o"/output/$smxname" || \
        { echo "ERROR: Failed to compile $spfile"; exit 1; }; \
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
    for i in 1 2 3; do \
        ./steamcmd.sh +force_install_dir /home/steam/css +login anonymous +app_update 232330 validate +quit && \
        exit_code=0 && break || \
        exit_code=$? && echo "Attempt $i failed (code $exit_code), retrying in 10s..." && sleep 10; \
    done && exit $exit_code

RUN curl -L -o /tmp/mmsource.tar.gz https://github.com/alliedmodders/metamod-source/releases/download/1.12.0.1224/mmsource-1.12.0-git1224-linux.tar.gz && \
    tar -C /home/steam/css/cstrike -zxf /tmp/mmsource.tar.gz && rm /tmp/mmsource.tar.gz && \
    curl -L -o /tmp/sourcemod.tar.gz https://github.com/alliedmodders/sourcemod/releases/download/1.12.0.7236/sourcemod-1.12.0-git7236-linux.tar.gz && \
    tar -C /home/steam/css/cstrike -zxf /tmp/sourcemod.tar.gz && rm /tmp/sourcemod.tar.gz && \
    curl -L -o /tmp/ripext.zip https://github.com/ErikMinekus/sm-ripext/releases/download/1.3.2/sm-ripext-1.3.2-linux.zip && \
    unzip -o /tmp/ripext.zip -d /home/steam/css/cstrike && rm /tmp/ripext.zip && \
    printf '"Extensions"\n{\n    "rip"\n    {\n        "file"    "addons/sourcemod/extensions/rip.ext.so"\n    }\n}\n' > /home/steam/css/cstrike/addons/sourcemod/extensions/rip.ext.txt

COPY --chown=steam:steam assets/maps.txt /tmp/maps.txt
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

COPY --chown=steam:steam assets/mods.txt /tmp/mods.txt
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
COPY --from=builder --chown=steam:steam /output/rip.ext.so /home/steam/css/cstrike/addons/sourcemod/extensions/
COPY --from=builder --chown=steam:steam /output/rip.ext.txt /home/steam/css/cstrike/addons/sourcemod/extensions/
COPY --chown=steam:steam cfg/ /home/steam/css/cstrike/cfg/
COPY --chown=steam:steam gamedata/ /home/steam/css/cstrike/addons/sourcemod/gamedata/
COPY --chown=steam:steam translations/ /home/steam/css/cstrike/addons/sourcemod/translations/
COPY --chown=steam:steam entrypoint.sh /home/steam/entrypoint.sh

RUN ls /home/steam/css/cstrike/maps/*.bsp | xargs -n1 basename | sed 's/\.bsp//' > /home/steam/css/maplist.txt && \
    cp /home/steam/css/maplist.txt /home/steam/css/cstrike/maplist.txt && \
    cp /home/steam/css/maplist.txt /home/steam/css/cstrike/mapcycle.txt && \
    cp /home/steam/css/maplist.txt /home/steam/css/cstrike/cfg/maplist.txt && \
    mkdir -p /home/steam/css/cstrike/addons/sourcemod/configs && \
    cp /home/steam/css/maplist.txt /home/steam/css/cstrike/addons/sourcemod/configs/maplist.txt

COPY --chown=steam:steam cfg/sourcemod/languages.cfg /home/steam/css/cstrike/addons/sourcemod/configs/languages.cfg
COPY --chown=steam:steam cfg/sourcemod/admins_simple.ini /home/steam/css/cstrike/addons/sourcemod/configs/admins_simple.ini

ENV CSS_HOSTNAME="[N.V.D] MIX SERVER"
ENV NVD_OLLAMA_IP="172.17.0.1"
ENV NVD_OLLAMA_PORT="11433"
ENV NVD_OLLAMA_MODEL="nvd-admin"
ENV NVD_OLLAMA_ENDPOINT="chat"
EXPOSE 27015/udp 27015 1200 27005/udp 27020/udp 26901/udp

ENTRYPOINT ["./entrypoint.sh"]
