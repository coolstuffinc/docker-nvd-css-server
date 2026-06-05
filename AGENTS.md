# Agent Instructions & Troubleshooting

This file documents quirks, limitations, and operational gotchas encountered while working on this repository. Future AI agents should read this file to avoid repeating past mistakes.

## 1. Repository Architecture & Constraints

- **Immutable Infrastructure**: The container must be fully self-contained. No persistent volumes, and no runtime downloads. All plugins, maps, and configs are baked into the image during `docker build`.
- **Source Structure**: 
  - `src/mods/` contains the SourcePawn plugins.
  - `src/mods/include/` contains headers.
  - `src/mods/mixmod/` contains mixmod includes.
- **Maps**: Maps are downloaded from the `assets` branch during the Docker build stage. `maplist.txt` is auto-generated from installed `.bsp` files at build time.
- **Mixmod Strings**: All UI/strings use the SourceMod translation system (`%t`). Avoid hardcoding strings (like Portuguese or Chinese) directly in the `.sp` files.

## 2. CI & Build Flow

- **Docker Build**: The primary build mechanism is a multi-stage Docker build. 
  ```bash
  docker build -t ghcr.io/coolstuffinc/docker-nvd-css-server/css-server:latest .
  ```
- Stage 1 compiles all plugins using SourceMod 1.12 and the `ambuild` toolchain for `sm-ripext`.
- If a plugin fails to compile, the entire Docker build will fail. This is the intended CI behavior.
- **Do not use host-level Nix environments or scripts** (like the old `spcomp-nix` or `batch_compile.sh` which have been deleted) to compile plugins. Rely on the Docker builder stage or compile directly inside the running container (see below).

## 3. Compiling SourcePawn Plugins (Hot Reloading)

### The Problem
Using host-level `spcomp` can cause build failures or include resolution issues. Compiling directly into a mounted Docker volume or the container's plugin directory might fail due to `steam` vs `root` permission errors (`Permission denied` when trying to overwrite `.smx` files).

### The Solution
Use the source files from the host repository, but run the compiler inside the **currently running container** (`css-server`) to ensure the correct toolchain. Copy the source to the container's `/tmp`, compile it to `/tmp`, and then move the binary into the plugins folder using `sudo` to avoid permission issues.

```bash
# 1. Copy the local src/ folder into the running container's /tmp directory
sudo docker cp src css-server:/tmp/src

# 2. Compile the plugin using the container's native spcomp64
sudo docker exec css-server /home/steam/css/cstrike/addons/sourcemod/scripting/spcomp64 \
    -i/tmp/src -i/tmp/src/mods/include \
    /tmp/src/mods/qrcode.sp -o/tmp/qrcode.smx

# 3. Move the compiled binary into the plugins folder as root and fix permissions
sudo docker exec -u root css-server cp /tmp/qrcode.smx /home/steam/css/cstrike/addons/sourcemod/plugins/qrcode.smx
sudo docker exec -u root css-server chown steam:steam /home/steam/css/cstrike/addons/sourcemod/plugins/qrcode.smx
```

## 4. RCON & Server Execution

### The Problem
Reloading plugins or issuing server commands via RCON from the host environment or inside the container can fail due to missing dependencies:
- Attempting to run `rcon` directly inside the container (`docker exec css-server rcon ...`) fails because there is no native `rcon` binary installed in the container's `$PATH`.
- Attempting to use the host's `scripts/rcon.py` script (`python3 scripts/rcon.py ...`) fails because `python3` may not be installed in the host's runtime environment (e.g., restricted NixOS shell or stripped agent environment).

### How to Find the RCON Password
Do not guess the RCON password. It is typically passed as an environment variable when the container is started, or defined in the server's configuration files.
To find it, check the container's environment variables:
```bash
docker inspect css-server | grep RCON
```
Or check inside the running container:
```bash
docker exec css-server grep -rn "rcon_password" /home/steam/css/cstrike/cfg/
```

### How to Execute Server Commands
Since host-level RCON and container-level `rcon` binaries are unreliable, prefer the following workarounds to reload plugins or issue commands:

1. **Use `uv run` on the host:**
   The host has `uv` available, which allows executing the `rcon.py` script without installing a global Python environment.
   ```bash
   uv run python scripts/rcon.py 127.0.0.1 27015 your_rcon_password "sm plugins reload qrcode"
   ```
2. **Restart the Container:**
   For compiled plugins, sometimes it is faster and more reliable to copy the `.smx` file into the container and simply restart it:
   ```bash
   docker restart css-server
   ```
2. **Check for Python inside the container:**
   You can copy the `rcon.py` script into the container and execute it there, assuming the container image has Python installed.

## 5. Engine Limitations & Quirks

- **Source Engine Limits:** `ShowHudText` in CS:S has a hard limit of ~219 usable bytes (255 byte buffer - 36 byte header). QR codes cannot be rendered using HUD text. They must be streamed to the console using repeating timers (1 row per tick).
- **Console QR Codes:** Terminals differ in how they render characters. The QR generator includes `sm_qr_render_mode` (1 = full width `██`, 0 = half-block `█▀▄`) to accommodate different line-heights in terminals like Kitty and Neovim.
- **RCON Input Mangling:** PIX payloads containing characters like `+` get mangled by `GetCmdArgString` unless they are wrapped in quotes (`"..."`). Keep this in mind when sending data over RCON.
- **Ollama AI Integration:** The server uses the `REST in Pawn` extension (`14NGiestas/sm-ripext` fork) to make HTTP calls to a local Ollama instance for the in-game admin and bot personas. Responses are intentionally limited to 1-2 sentences.
