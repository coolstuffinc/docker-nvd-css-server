# NVD (NemViDeOnde) - Counter-Strike: Source Server

Fully immutable Docker image for the NVD CS:S server. Everything is baked in during `docker build` — no volumes, no runtime downloads.

## Build

```bash
docker build -t ghcr.io/coolstuffinc/docker-nvd-css-server/css-server:latest .
```

The build is multi-stage:
1. **Builder** — compiles SourcePawn plugins from `src/` using SM 1.12 + ripext includes
2. **Runtime** — installs CSS via SteamCMD, Metamod 1.12, SourceMod 1.12, REST in Pawn, maps, configs, and compiled plugins

## Run

```bash
docker run -d --name css-server \
    -p 27015:27015/tcp \
    -p 27015:27015/udp \
    -p 1200:1200/tcp \
    -p 27005:27005/udp \
    -p 27020:27020/udp \
    -p 26901:26901/udp \
    -e CSS_HOSTNAME="[N.V.D] MIX SERVER" \
    -e RCON_PASSWORD="your_rcon_password" \
    -e CSS_PASSWORD="" \
    -e STEAM_TOKEN="your_gslt_token" \
    ghcr.io/coolstuffinc/docker-nvd-css-server/css-server:latest
```

## Environment Variables

| Variable | Description |
|---|---|
| `CSS_HOSTNAME` | Server name shown in the Steam browser |
| `RCON_PASSWORD` | Remote console password |
| `CSS_PASSWORD` | Optional server join password |
| `STEAM_TOKEN` | GSLT token (App ID 240) |

## AI Admin Assistant

This server includes an AI Admin assistant powered by Ollama. For detailed setup and troubleshooting, see [AI_ADMIN.md](AI_ADMIN.md).

Compiled from `src/` during build:
- bot2player, botdropbomb, enemies_left, forceroundend, givecash, llama_admin, playerstacker

Pre-compiled from the `assets` branch:
- mixmod, voicecomm, rankme, save_scores

## Maps

Downloaded from `assets` branch during build (CS:GO ported maps like de_cache, de_mirage, de_nuke, de_overpass, etc.).

## Directory Structure

```
├── assets/          # manifest files for maps/mods
├── cfg/             # server.cfg, sourcemod configs
├── gamedata/        # signature files for plugins
├── ollama/          # Modelfile for AI admin
├── src/             # SourcePawn source files + includes
├── Dockerfile       # multi-stage build
└── entrypoint.sh    # container entrypoint
```
