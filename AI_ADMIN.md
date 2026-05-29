# AI Admin Assistant (Ollama + SourceMod)

This document details the configuration for the `llama_admin` SourceMod plugin and its integration with the Ollama service running on the host machine (`matrix`).

## Host Setup (Manual)

To run the Ollama service manually instead of using NixOS modules, run the following command on your host machine (`matrix`):

```bash
OLLAMA_HOST=0.0.0.0:11433 OLLAMA_KEEP_ALIVE=3600 ollama serve
```

Ensure this process stays running in the background (e.g., using `screen`, `tmux`, or a systemd service).

## Plugin Configuration

The `llama_admin` plugin communicates with the host via the Docker bridge network (`172.17.0.1`). Ensure your `cfg/sourcemod/mods.cfg` is configured as follows:

```cfg
// Llama Admin
llama_admin_ip "172.17.0.1"
llama_admin_port "11433"
llama_admin_model "llama3.2:1b"
llama_admin_debug "1"
```

### ConVar Reference

| ConVar | Default | Description |
|---|---|---|
| `llama_admin_ip` | "172.17.0.1" | IP of the Ollama server (Docker host IP). |
| `llama_admin_port` | "11433" | Port of the Ollama server. |
| `llama_admin_model` | "llama3.2:1b" | The Ollama model to use. |
| `llama_admin_debug` | "1" | Enable verbose logging (1=Enabled). |

## Troubleshooting

1.  **"AI server unreachable / Status 0"**:
    *   Ensure Ollama is running on the host: `systemctl status ollama`.
    *   Verify the port is correct in `mods.cfg` (default is now 11433).
    *   Check host firewall logs if connection is refused.
2.  **Plugin Crash**:
    *   Check `addons/sourcemod/logs/errors_YYYYMMDD.log`.
    *   If you see "invalid handle", the plugin failed to load its dependencies (phrases/maplist). Ensure the Docker image was rebuilt successfully.
3.  **Observability**:
    *   Logs are written to standard SourceMod error/general logs.
    *   Enable debug mode (`llama_admin_debug 1`) to see raw AI responses in the console.
