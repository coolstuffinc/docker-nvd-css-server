# NVD (NemViDeOnde) - Counter-Strike: Source Server

[![Docker Image](https://img.shields.io/badge/Docker-ghcr.io-blue?style=flat-square&logo=docker)](https://github.com/coolstuffinc/docker-nvd-css-server/pkgs/container/css-server)

Docker image oficial do servidor de Counter-Strike: Source do clã **NVD (NemViDeOnde)**. Baseado na arquitetura Ubuntu 22.04, pré-configurado com MetaMod, SourceMod e plugins essenciais para 4Fun e Mix.

## 📦 Plugins Incluídos

* [MetaMod:Source v1.10.6](http://www.metamodsource.net/)
* [SourceMod v1.7.3-5275](http://www.sourcemod.net/)
* **RankMe**: Sistema de ranking completo com banco de dados SQLite.
* **Bot2Player**: Permite que jogadores mortos assumam o controle de bots vivos (apertando a tecla `E` enquanto assiste o bot).
* **Quake Sounds**: Locução clássica de Unreal/Quake para killstreaks (`!quake`).
* **MixMod**: Sistema de gerenciamento automático de Mix/Pug.
* **Damage Report/Enemies Left**: Mostra o dano causado e quem ainda está vivo no final do round.
* Entre outros: *DropBomb, Save Scores, VoiceComm, Cash, PlayerStacker, ForceRoundEnd.*

## 🚀 Como Iniciar o Container

A imagem já atualiza automaticamente o motor do CS:S via SteamCMD durante a inicialização (comando `update`). Recomendamos usar o `docker run` com as portas e variáveis de ambiente abaixo:

```bash
docker run -d --name css-server \
    -p 27015:27015/tcp \
    -p 27015:27015/udp \
    -p 1200:1200/tcp \
    -p 27005:27005/udp \
    -p 27020:27020/udp \
    -p 26901:26901/udp \
    -e CSS_HOSTNAME="NVD (NemViDeOnde) - Matrix Server" \
    -e RCON_PASSWORD="sua_senha_rcon" \
    -e STEAM_TOKEN="seu_game_server_login_token" \
    ghcr.io/coolstuffinc/docker-nvd-css-server/css-server:latest \
    ./entrypoint.sh update
```

### Variáveis de Ambiente Suportadas:
* `CSS_HOSTNAME`: O nome do servidor que aparecerá na lista da Steam.
* `RCON_PASSWORD`: A senha de administração remota (RCON).
* `CSS_PASSWORD`: (Opcional) Senha para trancar o servidor para visitantes.
* `STEAM_TOKEN`: O *Game Server Login Token (GSLT)* gerado na Steam para o App ID **240**. Essencial para o servidor não ficar anônimo.

## 🛠️ Arquitetura de Assets (Mapas e Mods)

Este repositório foi otimizado para que a branch `main` seja leve. Todos os arquivos pesados (Mapas e Plugins pré-compilados `.smx`/`.zip`) residem exclusivamente na branch `assets` utilizando o Git LFS.

Durante a construção da imagem, o Dockerfile lê o manifesto (`assets/maps.txt` e `assets/mods.txt`) e baixa os binários necessários diretamente do repositório via `media.githubusercontent.com`. Isso garante que a imagem tenha tudo que precisa sem poluir o histórico do Git com centenas de megabytes.

## 🕹️ Comandos In-Game

* **Para jogadores:**
  * `!rank` / `!top`: Visualiza as estatísticas do servidor.
  * Aperte a tecla `E` (Use) ao assistir um Bot para assumir o controle dele.
  * `!quake`: Abre o menu de sons.
* **Para Admins (via RCON):**
  * `rcon_password <senha>`: Logar como admin no console do cliente.
  * `rcon exec mr15` ou `rcon exec mr3`: Carrega configs rápidas de campeonatos.
  * `rcon sm plugins list`: Verifica os plugins carregados.

## Customizações via Volumes (Opcional)

Se desejar alterar as configurações originais do NVD sem precisar recriar a imagem, você pode extrair os arquivos `.cfg` de dentro do container, editá-los e injetá-los novamente, ou mapeá-los usando Volumes (cuidado para não sobrescrever pastas inteiras se o container não tiver inicializado o jogo ainda).

```bash
# Exemplo de extração do server.cfg para edição local:
docker cp css-server:/home/steam/css/cstrike/cfg/server.cfg ./meu_server.cfg
```

---
*Fork original de [foxylion/docker-steam-css](https://github.com/foxylion/docker-steam-css) - Adaptado para o clan NemViDeOnde.*
