FROM ubuntu:22.04

# Only install system build-deps once.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget curl lib32gcc-s1 lib32stdc++6 libtinfo5 unzip nginx \
    g++-multilib libc6-dev-i386 patchelf make && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash steam
WORKDIR /home/steam
USER steam

# Install SteamCMD (only once)
RUN wget -O /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xvzf /tmp/steamcmd_linux.tar.gz && \
    rm /tmp/steamcmd_linux.tar.gz && \
    ./steamcmd.sh +quit

# Copy required assets and scripts into the image
COPY --chown=steam:steam entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

COPY --chown=steam:steam assets /home/steam/assets
COPY --chown=steam:steam cfg /home/steam/cfg_defaults
COPY --chown=steam:steam compiled_plugins /home/steam/ci_mods

ENV CSS_HOSTNAME="[N.V.D] MIX SERVER"
EXPOSE 27015/udp 27015 1200 27005/udp 27020/udp 26901/udp

ENTRYPOINT ["./entrypoint.sh"]
