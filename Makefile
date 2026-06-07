# Configurações
CONTAINER_NAME = css-server
SPCOMP = /home/steam/css/cstrike/addons/sourcemod/scripting/spcomp64
INCLUDE_DIR = /home/steam/css/cstrike/addons/sourcemod/scripting/include
LOCAL_INCLUDE = /tmp/compile-src/include
PLUGIN_DIR = /home/steam/css/cstrike/addons/sourcemod/plugins/
RCON_IP = 127.0.0.1
RCON_PORT = 27015

# Captura a senha do RCON dinamicamente do container
RCON_PASS = $(shell sudo docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $(CONTAINER_NAME) | grep RCON_PASSWORD | cut -d'=' -f2)

# Busca todos os arquivos .sp em src/mods/
MODS = $(wildcard src/mods/*.sp)
# Gera os nomes dos binários .smx correspondentes
SMX = $(patsubst src/mods/%.sp, %.smx, $(MODS))

.PHONY: all sync compile deploy reload mods clean help rcon

all: mods

# Executa um comando RCON genérico (Ex: make rcon cmd="status")
rcon:
	@if [ -z "$(cmd)" ]; then echo "Erro: Use make rcon cmd=\"seu comando\""; exit 1; fi
	@uv run python scripts/rcon.py $(RCON_IP) $(RCON_PORT) $(RCON_PASS) "$(cmd)"

# Sincroniza os fontes com o container
sync:
	@echo "--- Sincronizando fontes ---"
	@sudo docker exec $(CONTAINER_NAME) mkdir -p /tmp/compile-src/include
	@sudo docker cp src/mods/. $(CONTAINER_NAME):/tmp/compile-src/
	@sudo docker cp src/mods/include/. $(CONTAINER_NAME):/tmp/compile-src/include/ 2>/dev/null || true

# Compila os mods dentro do container
compile: sync
	@echo "--- Compilando mods ---"
	@for mod in $(MODS); do \
		name=$$(basename $$mod .sp); \
		echo "Compilando $$name..."; \
		sudo docker exec $(CONTAINER_NAME) $(SPCOMP) \
			-i$(INCLUDE_DIR) -i$(LOCAL_INCLUDE) -i/tmp/compile-src/ \
			/tmp/compile-src/$$name.sp -o/tmp/compile-src/$$name.smx; \
	done

# Move os binários para a pasta de plugins e ajusta permissões
deploy:
	@echo "--- Fazendo deploy dos plugins ---"
	@sudo docker exec -u root $(CONTAINER_NAME) sh -c "cp /tmp/compile-src/*.smx $(PLUGIN_DIR) 2>/dev/null || true"
	@sudo docker exec -u root $(CONTAINER_NAME) sh -c "chown steam:steam $(PLUGIN_DIR)*.smx 2>/dev/null || true"

# Executa o reload de cada plugin via RCON
reload:
	@echo "--- Recarregando plugins via RCON ---"
	@for mod in $(MODS); do \
		name=$$(basename $$mod .sp); \
		echo "Reloading $$name..."; \
		uv run python scripts/rcon.py $(RCON_IP) $(RCON_PORT) $(RCON_PASS) "sm plugins reload $$name" || true; \
	done

# Atalho para o fluxo completo
mods: compile deploy reload
	@echo "✅ Todos os mods atualizados com sucesso!"

# Limpa os arquivos temporários no container
clean:
	@echo "--- Limpando temporários ---"
	@sudo docker exec $(CONTAINER_NAME) rm -rf /tmp/compile-src/*.smx /tmp/compile-src/*.sp

help:
	@echo "Comandos disponíveis:"
	@echo "  make mods    - Compila, faz deploy e recarrega todos os plugins (Full Hot-Reload)"
	@echo "  make compile - Apenas compila os arquivos .sp"
	@echo "  make sync    - Sincroniza os arquivos locais com o container"
	@echo "  make deploy  - Move binários compilados para a pasta de plugins"
	@echo "  make reload  - Executa o comando de reload via RCON"
	@echo "  make rcon cmd=\"status\" - Executa um comando RCON genérico"
	@echo "  make clean   - Remove arquivos temporários do container"
