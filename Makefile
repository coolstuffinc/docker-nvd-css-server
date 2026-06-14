# Configurações
CONTAINER_NAME = css-server
SPCOMP = /home/steam/css/cstrike/addons/sourcemod/scripting/spcomp64
INCLUDE_DIR = /home/steam/css/cstrike/addons/sourcemod/scripting/include
LOCAL_INCLUDE = /tmp/compile-src/include
PLUGIN_DIR = /home/steam/css/cstrike/addons/sourcemod/plugins/
CONFIG_DIR = /home/steam/css/cstrike/addons/sourcemod/configs/
TRANS_DIR = /home/steam/css/cstrike/addons/sourcemod/translations/
RCON_IP = 127.0.0.1
RCON_PORT = 27015

# Captura a senha do RCON dinamicamente do container
RCON_PASS = $(shell sudo docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $(CONTAINER_NAME) | grep RCON_PASSWORD | cut -d'=' -f2)

# Busca arquivos .sp
MODS_CORE = src/mods/nvd/strings.sp src/mods/nvd/ollama.sp
MODS_NVD = $(filter-out $(MODS_CORE), $(wildcard src/mods/nvd/*.sp))
MODS_ROOT = $(wildcard src/mods/*.sp)
ALL_MODS = $(MODS_CORE) $(MODS_NVD) $(MODS_ROOT)

.PHONY: all sync compile deploy reload mods clean help rcon match

all: mods

rcon:
	@if [ -z "$(cmd)" ]; then echo "Erro: Use make rcon cmd=\"seu comando\""; exit 1; fi
	@uv run python scripts/rcon.py $(RCON_IP) $(RCON_PORT) $(RCON_PASS) "$(cmd)"

match:
	@echo "--- Iniciando partida ---"
	@uv run python scripts/rcon.py $(RCON_IP) $(RCON_PORT) $(RCON_PASS) "bot_join_after_player 0; bot_quota 10; bot_quota_mode fill; mp_restartgame 1"

sync:
	@echo "--- Sincronizando fontes e recursos ---"
	@sudo docker exec -u root $(CONTAINER_NAME) rm -rf /tmp/compile-src
	@sudo docker exec -u root $(CONTAINER_NAME) mkdir -p /tmp/compile-src/include
	@sudo docker exec -u root $(CONTAINER_NAME) chown steam:steam /tmp/compile-src /tmp/compile-src/include
	@sudo docker cp src/mods/. $(CONTAINER_NAME):/tmp/compile-src/
	@sudo docker cp src/mods/nvd/. $(CONTAINER_NAME):/tmp/compile-src/
	@sudo docker cp src/mods/include/. $(CONTAINER_NAME):/tmp/compile-src/include/
	@echo "Copiando configurações..."
	@sudo docker cp cfg/sourcemod/. $(CONTAINER_NAME):$(CONFIG_DIR)
	@echo "Copiando traduções..."
	@sudo docker cp translations/. $(CONTAINER_NAME):$(TRANS_DIR)
	@sudo docker exec -u root $(CONTAINER_NAME) chown -R steam:steam $(CONFIG_DIR) $(TRANS_DIR)

compile: sync
	@echo "--- Compilando mods ---"
	@for mod in $(ALL_MODS); do \
		name=$$(basename $$mod .sp); \
		echo "Compilando $$name..."; \
		sudo docker exec $(CONTAINER_NAME) $(SPCOMP) \
			-i$(INCLUDE_DIR) -i$(LOCAL_INCLUDE) -i/tmp/compile-src/ \
			/tmp/compile-src/$$name.sp -o/tmp/compile-src/$$name.smx || { \
			echo "❌ Compilation failed for $$name"; \
			exit 1; \
		}; \
	done

deploy:
	@echo "--- Fazendo deploy dos plugins ---"
	@for mod in $(ALL_MODS); do \
		name=$$(basename $$mod .sp); \
		sudo docker exec -u root $(CONTAINER_NAME) sh -c "rm -f $(PLUGIN_DIR)$$name.smx"; \
	done
	@sudo docker exec -u root $(CONTAINER_NAME) sh -c "cp /tmp/compile-src/*.smx $(PLUGIN_DIR) && chown steam:steam $(PLUGIN_DIR)*.smx"

reload:
	@echo "--- Recarregando plugins via RCON ---"
	@echo "Reloading nvd/strings and nvd/ollama first..."
	@uv run python scripts/rcon.py $(RCON_IP) $(RCON_PORT) $(RCON_PASS) "sm plugins reload strings; sm plugins reload ollama" || true
	@for mod in $(ALL_MODS); do \
		name=$$(basename $$mod .sp); \
		if [ "$$name" = "strings" ] || [ "$$name" = "ollama" ] || [ "$$name" = "enemies_left" ]; then continue; fi; \
		echo "Reloading $$name..."; \
		uv run python scripts/rcon.py $(RCON_IP) $(RCON_PORT) $(RCON_PASS) "sm plugins reload $$name" || true; \
	done
	@echo "Reloading enemies_left last..."
	@uv run python scripts/rcon.py $(RCON_IP) $(RCON_PORT) $(RCON_PASS) "sm plugins reload enemies_left" || true

mods: clean compile deploy reload
	@echo "✅ Todos os mods atualizados com sucesso!"

clean:
	@echo "--- Limpeza completa ---"
	@sudo docker exec $(CONTAINER_NAME) rm -rf /tmp/compile-src/*.smx /tmp/compile-src/*.sp
	@for mod in $(ALL_MODS); do \
		name=$$(basename $$mod .sp); \
		sudo docker exec -u root $(CONTAINER_NAME) sh -c "rm -f $(PLUGIN_DIR)$$name.smx"; \
	done
	@echo "✅ Plugins e temporários limpos"

help:
	@echo "Comandos disponíveis:"
	@echo "  make mods    - Compila, faz deploy e recarrega todos os plugins"
	@echo "  make match   - Inicia uma partida com bots"
	@echo "  make rcon cmd=\"...\" - Executa um comando RCON"
