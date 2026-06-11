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

### The Solution (Preferred: Makefile)
Use `make mods` from the project root. This runs the full flow: `compile → deploy → reload` using the Makefile, which handles all permissions and paths automatically.

```bash
make mods   # Full hot-reload: compile all mods, deploy binaries, reload via RCON
```

The Makefile compiles each `.sp` in `src/mods/` inside the container using the container's native `spcomp64`, copies `.smx` to the plugin directory as root, then reloads via RCON.

**Reload order is intentional**: `nvd_ollama` is reloaded first (meta provider), then all other mods.

### Alternative: Manual Compilation
If you need to compile a single plugin manually:

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

## 5. Bot Chat AI System (nvd_bot_chat)

### Architecture
- `nvd_bot_chat.sp` handles game events, builds prompts, polls responses, and makes bots speak via `say`.
- `nvd_ollama.sp` (nvd_core library) manages HTTP requests to Ollama, queue/concurrency, response polling, and **centralized string system** (`NVD_RegisterStrings` / `NVD_GetStr`).
- String files are **KeyValues** files under `cfg/sourcemod/`:
  - `nvd_bot_chat_strings_default.txt` — English templates (root key: `BotChatStrings`)
  - `nvd_bot_chat_strings_pt-br.txt` — Portuguese overrides
- Language is selected by `nvd_language` convar (`"default"` = English, `"pt"` = Portuguese).

### Template System (KeyValues sections)
Templates live under the `prompts` section with keys named `{eventType}_{system|user}`:
```
"prompts"
{
    "kill_system"    "You are [bot] from [team]. [personality]. [catchphrase]. [rules] [critical] EX: easy [target] no chance"
    "kill_user"      "You killed [target] with [weapon]. Map [map]. Round [round]. Score [score]. [state] [mood]."
    "death_system"   "You are [bot] from [team]. [personality]. [catchphrase]. [rules] [critical] ..."
    "death_user"     "You died to [target] with [weapon]. Map [map]. Round [round]. Score [score]. [state] [mood]."
    ...
}
```
Placeholders: `[bot]`, `[team]`, `[target]`, `[state]`, `[event]`, `[mood]`, `[map]`, `[round]`, `[score]`, `[weapon]`, `[personality]`, `[catchphrase]`, `[style]`, `[behavior]`.

### Self-Reference Convention (CRITICAL)
- **System prompts** MUST use `"You are [bot] from [team]"` (second-person), NEVER `"[bot] from [team]"` (third-person).
- **User prompts** MUST use `"You killed"`, `"You died"`, `"You planted"`, `"You defused"` (second-person), NEVER `"[bot] killed"`, etc.
- The `rules` and `critical` meta snippets should NOT contain `"Speak as [bot]"` since identity is already established by the template prefix.

### Behavior Meta Snippets
- Registered via `NVD_SetMeta("rules", ...)` and `NVD_SetMeta("critical", ...)`.
- Stored in `nvd_ollama.sp` global arrays `g_MetaKeys[]` / `g_MetaValues[]`.
- Substituted via `ProcessTemplates()` before every request.
- **Delayed re-registration**: `nvd_bot_chat.sp` has a 5-second timer (`Timer_DelayedReRegister`) after `OnPluginStart` that re-calls `NVD_RegisterStrings` and `LoadMetaFromStrings`. This protects against the case where `nvd_ollama` is reloaded after `nvd_bot_chat` — the Makefile reloads nvd_ollama FIRST for this reason.
- To force re-registration: `sm_botchat_reload` (admin command).

### Language Cue
When `nvd_language != "default"`, `SendRequest()` in `nvd_ollama.sp:515-526` appends `" Answer in {Language}."` to the system prompt.

### Prompt Cleanup in AskBotChat (lines 489-499)
After template substitution, `AskBotChat` runs:
- `ReplaceString(buf, "  ", " ")` — collapse double spaces
- `ReplaceString(buf, ". .", ".")`, `" ." → "."`, `".." → "."` — period artifacts
- `TrimString(fullP)` — leading/trailing whitespace

### Target Name Passing
- `AskBotChat` now accepts a `targetName` parameter.
- `Event_PlayerDeath` and `Event_PlayerHurt` extract and pass the victim/killer name.
- Without this, `[target]` would be empty in kill/death prompts.

### Interest Scoring System (replaces flat random chance)
Instead of hardcoded `GetRandomInt(1,100) > X` per event, a dynamic scoring system replaces all guards:

**Base interest per event type** (defined in `IntBase_*` enum):
| Event | Base | Notes |
|---|---|---|
| Kill (bot→human) | 30 | Highest for player-facing kills |
| Kill (human→bot) | 25 | |
| Bomb plant/defuse | 50 | Always somewhat interesting |
| Round start/end | 30 | |
| Win panel (funfact) | 40 | |
| Friendly fire | 20 | |
| Player say chat | 10 | Lowest, rarely worth it |
| External (plugin) | 45 | Default for custom events |

**Game state modifiers** (added by `GetGameStateBonus()`):
- Close score (diff ≤ 2): +15
- Early rounds (≤ 3): +10
- Human in clutch (1vX+): +25
- Weapon: knife +20, AWP +10

**Event-specific bonuses** (passed as `extra` param):
- Revenge kill: +15
- Domination kill: +20
- Headshot kill: +5

Final: `score = base + game_bonus + weapon_bonus + extra`, clamped to 0-100.
Guard: `if (GetRandomInt(1, 100) > score) return;`

### Recent Chat Context (conversation memory)
After a bot speaks, `RecordBotMessage()` stores the last 3 bot messages (`@bot: "msg"`) in a circular buffer. Before every `AskBotChat` call, `BuildRecentChatContext()` appends them to the user prompt:

```
You killed Cabra with M4. Map de_aztec. Round 2. Score 3-8. You are winning.

@fnx: "ez"
@ZywOo: "lets go guys"
```

This lets bots reference what others just said — creating连贯 conversation instead of isolated one-liners. The buffer is per-plugin (global), reset on plugin reload/map start.

### External Plugin Hook API
**Include**: `#include <nvd_bot_chat>` (new, in `src/mods/include/nvd_bot_chat.inc`)

**Native**:
```pawn
native void NVD_SubmitChatEvent(
    const char[] context,       // Event description (fills [event] in template)
    int preferredBot = -1,      // -1 for random bot
    int priority = 50,          // Interest score 0-100
    const char[] eventType = "" // Template key, or "" for "default"
);
```

Usage example (from RankMe, mixmod, etc.):
```pawn
#include <nvd_bot_chat>

public void SomeEvent(int client)
{
    if (GetFeatureStatus(FeatureType_Native, "NVD_SubmitChatEvent") == FeatureStatus_Available)
        NVD_SubmitChatEvent("Just reached rank #1!", -1, 80, "rankme");
}
```

The native lives in `nvd_bot_chat.smx` (NOT in nvd_core). Plugins link optionally via `#include <nvd_bot_chat>` with `required = 0`.

### Makefile Reload Order (critical)
In `make reload`:
1. `nvd_ollama` is reloaded FIRST (meta provider).
2. All other mods are reloaded SECOND (including `nvd_bot_chat`).
The `Timer_DelayedReRegister` backup is still needed because other reload sequences (e.g. manual `sm plugins reload`) might not follow this order.

## 6. Prompt Engineering Gotchas

- **Self-referencing models**: Models may still say "I'm Twistzz" despite `NO self-name` in rules. Strengthen negative prompting: `"NEVER say I, me, or your own name"` or add explicit negative examples.
- **Message truncation**: Bot responses are truncated at 180 chars in `PollBotResponses` (line 522).
- **HTTP 307 Redirect**: Ollama may return 307 if the endpoint URL is wrong or the model isn't loaded. Check `nvd_ollama_ip`, `nvd_ollama_port`, and `nvd_ollama_model` convars.
- **PT-BR strings file**: The root key in `nvd_bot_chat_strings_pt-br.txt` is `BotChatStrings`, but `LoadPluginStrings` in `nvd_ollama.sp` uses `new KeyValues("Strings")`. This works because `ImportFromFile` merges/replaces regardless of root key name. Just ensure the file root key matches across languages.

## 7. GGUF Model Support in Ollama

Ollama natively supports GGUF models. To use a custom GGUF (e.g., TeenyTinyLlama for Brazilian Portuguese):
1. Place the `.gguf` file in the container (e.g., `/home/steam/ollama/models/`).
2. Create a Modelfile:
   ```
   FROM /home/steam/ollama/models/teenytinyllama-460m.Q8_0.gguf
   ```
3. Import: `ollama create teenytinyllama -f Modelfile`
4. Set convar: `sm_convar nvd_ollama_model teenytinyllama`

TeenyTinyLlama (460m and 160m) is a Brazilian Portuguese-only model from nicholasKluge. Available as GGUF on HuggingFace (`afrideva/TeenyTinyLlama-460m-Chat-GGUF`). It has 2048 context length and works for trash talk but may struggle with complex instructions.

## 8. Engine Limitations & Quirks

- **Source Engine Limits:** `ShowHudText` in CS:S has a hard limit of ~219 usable bytes (255 byte buffer - 36 byte header). QR codes cannot be rendered using HUD text. They must be streamed to the console using repeating timers (1 row per tick).
- **Console QR Codes:** Terminals differ in how they render characters. The QR generator includes `sm_qr_render_mode` (1 = full width `██`, 0 = half-block `█▀▄`) to accommodate different line-heights in terminals like Kitty and Neovim.
- **RCON Input Mangling:** PIX payloads containing characters like `+` get mangled by `GetCmdArgString` unless they are wrapped in quotes (`"..."`). Keep this in mind when sending data over RCON.
- **Ollama AI Integration:** The server uses the `REST in Pawn` extension (`14NGiestas/sm-ripext` fork) to make HTTP calls to a local Ollama instance for the in-game admin and bot personas. Responses are intentionally limited to 1-2 sentences.

## 9. Testing Bot Chat

To verify that bot chat is working properly:
1. Check bot presence: `make rcon cmd="status"`
2. If bots are missing, add them: `make rcon cmd="bot_join_after_player 0; bot_quota 10; bot_quota_mode fill; mp_restartgame 1"`
3. Lower cooldown for testing: `make rcon cmd="sm_cvar nvd_bot_chat_cooldown 1.0"`
4. Tail the logs for activity: `docker logs -f css-server | grep -E "\[NVD|\[BOT_CHAT\]"`
