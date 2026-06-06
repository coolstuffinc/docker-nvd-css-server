#include <sourcemod>
#include <nvd_core>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define MAX_PLAYERS 65
#define MAX_MAPS 50
#define MAX_CTX 2048
#define AGENT_COOLDOWN 8.0

// Estado do agente por jogador
float g_PlayerLastAgent[MAXPLAYERS + 1];

// Comandos e permissões (SEGURANÇA: NUNCA remova sem saber o que faz)
enum AgentCmdLevel
{
    CmdLevel_All,       // Qualquer um pode votar
    CmdLevel_Admin,     // Requer flag de admin
    CmdLevel_Root,      // Requer flag de root
};

static const struct {
    char cmd[32];
    AgentCmdLevel level;
    char description[64];
} g_CommandMap[] = {
    { "sm_votemap",     CmdLevel_All,    "Iniciar votação de mapa" },
    { "sm_votekick",    CmdLevel_Admin,  "Iniciar votação de kick" },
    { "sm_voteban",     CmdLevel_Admin,  "Iniciar votação de ban" },
    { "sm_cvar",        CmdLevel_Root,   "Alterar cvar do servidor" },
    { "sm_plugins",     CmdLevel_Admin,  "Listar plugins" },
    { "sm_reloadadmin", CmdLevel_Root,   "Recarregar admins" },
};

// Cache de mapas
char g_MapList[MAX_MAPS][64];
int g_MapCount = 0;

public void OnPluginStart()
{
    RegConsoleCmd("sm_agent", Command_Agent, "AI Admin Agent - ask the AI for help");
    RegConsoleCmd("sm_agent_help", Command_AgentHelp, "Show available agent commands");
    LoadValidMaps();
}

public void OnMapStart()
{
    LoadValidMaps();
}

// ============================================================================
// COMANDOS
// ============================================================================
public Action Command_AgentHelp(int client, int args)
{
    ReplyToCommand(client, "[\x04AGENT\x01] ═══ Comandos do Agente ═══");
    ReplyToCommand(client, "[\x04AGENT\x01] !agent <pedido> - Pergunte algo à IA");
    ReplyToCommand(client, "[\x04AGENT\x01] A IA pode sugerir comandos como:");
    
    for (int i = 0; i < sizeof(g_CommandMap); i++)
    {
        int flags = GetCommandFlags(g_CommandMap[i].cmd);
        bool hasAccess = (flags == INVALID_FCVAR_FLAGS) || CheckCommandAccess(client, g_CommandMap[i].cmd, 0);
        
        if (hasAccess)
            ReplyToCommand(client, "[\x04AGENT\x01]   • [%s] %s", g_CommandMap[i].cmd, g_CommandMap[i].description);
    }
    
    ReplyToCommand(client, "[\x04AGENT\x01] ════════════════════════════");
    return Plugin_Handled;
}

public Action Command_Agent(int client, int args)
{
    if (!CheckCommandAccess(client, "sm_agent", ADMFLAG_KICK))
    {
        ReplyToCommand(client, "[\x04AGENT\x01] ❌ Você não tem permissão para usar este comando.");
        return Plugin_Handled;
    }
    
    // Rate limiting
    if (!NVD_CanRequest(client))
    {
        float timeLeft = AGENT_COOLDOWN - (GetGameTime() - g_PlayerLastAgent[client]);
        if (timeLeft < 0) timeLeft = 0.0;
        ReplyToCommand(client, "[\x04AGENT\x01] ⏱ Aguarde %.0fs antes de fazer outra requisição.", timeLeft);
        return Plugin_Handled;
    }
    
    // Cooldown
    if (GetGameTime() - g_PlayerLastAgent[client] < AGENT_COOLDOWN)
    {
        float timeLeft = AGENT_COOLDOWN - (GetGameTime() - g_PlayerLastAgent[client]);
        ReplyToCommand(client, "[\x04AGENT\x01] ⏱ Aguarde %.0fs antes de fazer outra requisição.", timeLeft);
        return Plugin_Handled;
    }
    
    if (args < 1)
    {
        ReplyToCommand(client, "[\x04AGENT\x01] Uso: !agent <seu pedido>");
        ReplyToCommand(client, "[\x04AGENT\x01] Ex: !agent trocar mapa");
        return Plugin_Handled;
    }
    
    char request[512];
    GetCmdArgString(request, sizeof(request));
    StripQuotes(request);
    TrimString(request);
    
    g_PlayerLastAgent[client] = GetGameTime();
    PrintToChat(client, "[\x04AGENT\x01] Processando...");

    // 1. Coleta contexto
    char context[MAX_CTX];
    BuildContext(context, sizeof(context), request, client);

    // 2. Chama IA (com client ID para rate limit)
    NVD_AskAI(context, 
        "Você é um agente admin de CS:S. Use EXATAMENTE [CMD: comando] para ações ou [SAY: mensagem] para chat. "
        "Máximo 2 linhas. Português ou Inglês. Seja breve e direto.", 
        Agent_Callback, client, client);
        
    return Plugin_Handled;
}

// ============================================================================
// CONSTRUÇÃO DO CONTEXTO
// ============================================================================
void BuildContext(char[] buffer, int maxlen, const char[] request, int client)
{
    int pos = 0;
    char playerName[MAX_NAME_LENGTH];
    
    if (client > 0 && IsClientInGame(client))
        GetClientName(client, playerName, sizeof(playerName));
    else
        playerName = "Console";
    
    // 1. Quem pediu
    pos += Format(buffer[pos], maxlen - pos, "REQUESTER: %s\n", playerName);
    
    // 2. Lista de jogadores
    pos += Format(buffer[pos], maxlen - pos, "PLAYERS:\n");
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        
        char name[MAX_NAME_LENGTH];
        GetClientName(i, name, sizeof(name));
        int team = GetClientTeam(i);
        
        char teamName[8];
        if (team == 2) teamName = "T";
        else if (team == 3) teamName = "CT";
        else teamName = "SPEC";
        
        char isAdmin[4];
        if (CheckCommandAccess(i, "sm_kick", ADMFLAG_KICK))
            isAdmin = " [ADMIN]";
        else
            isAdmin = "";
        
        pos += Format(buffer[pos], maxlen - pos, "[%d] %s (%s)%s\n", i, name, teamName, isAdmin);
    }
    
    // 3. Lista de mapas válidos
    pos += Format(buffer[pos], maxlen - pos, "VALID MAPS: ");
    for (int i = 0; i < g_MapCount; i++)
    {
        pos += Format(buffer[pos], maxlen - pos, "%s%s", i == 0 ? "" : ", ", g_MapList[i]);
        if (pos >= maxlen - 60) break;
    }
    
    // 4. Mapa atual
    char currentMap[64];
    GetCurrentMap(currentMap, sizeof(currentMap));
    pos += Format(buffer[pos], maxlen - pos, "\nCURRENT: %s\n", currentMap);
    
    // 5. Comandos disponíveis para este jogador
    pos += Format(buffer[pos], maxlen - pos, "AVAILABLE COMMANDS for %s:\n", playerName);
    for (int i = 0; i < sizeof(g_CommandMap); i++)
    {
        bool canUse = false;
        switch (g_CommandMap[i].level)
        {
            case CmdLevel_All:   canUse = true;
            case CmdLevel_Admin: canUse = client > 0 && CheckCommandAccess(client, g_CommandMap[i].cmd, ADMFLAG_KICK);
            case CmdLevel_Root:  canUse = client > 0 && CheckCommandAccess(client, g_CommandMap[i].cmd, ADMFLAG_ROOT);
        }
        
        if (canUse)
            pos += Format(buffer[pos], maxlen - pos, "  - %s\n", g_CommandMap[i].cmd);
    }
    
    // 6. Conexões SSH ativas (se aplicável)
    pos += Format(buffer[pos], maxlen - pos, "SSH TUNNELS: fermi-ollama (11434), fermi-webapp (8888)\n");
    
    // 7. Instruções finais
    pos += Format(buffer[pos], maxlen - pos, "\nREQUEST: %s\n", request);
    pos += Format(buffer[pos], maxlen - pos, "RULES:\n");
    pos += Format(buffer[pos], maxlen - pos, "1. Use [CMD: <comando>] OU [SAY: <mensagem>].\n");
    pos += Format(buffer[pos], maxlen - pos, "2. Só use comandos listados em AVAILABLE COMMANDS.\n");
    pos += Format(buffer[pos], maxlen - pos, "3. Máximo 2 linhas.\n");
    pos += Format(buffer[pos], maxlen - pos, "4. NUNCA invente comandos ou mapas.\n");
    pos += Format(buffer[pos], maxlen - pos, "5. Responda no mesmo idioma do pedido.");
}

// ============================================================================
// CALLBACK DA IA
// ============================================================================
public void Agent_Callback(const char[] response, any data)
{
    int client = view_as<int>(data);
    
    if (!IsClientInGame(client) && client != 0)
    {
        // Print to server console if client disconnected
        if (response[0] != '\0' && StrContains(response, "ERROR_") != 0)
            PrintToServer("[AGENT] Response (client gone): %s", response);
        return;
    }

    bool executed = false;
    char line[256];
    int len = strlen(response);
    int start = 0;
    
    while (start < len)
    {
        int end = FindCharInString(response[start], '\n', false);
        if (end == -1) end = strlen(response) - start;
        
        strcopy(line, sizeof(line), response[start]);
        line[end] = '\0';
        TrimString(line);
        start += end + 1;
        
        if (line[0] == '\0') continue;
        
        // Extrai [SAY: ...]
        if (StrContains(line, "[SAY:") == 0)
        {
            char msg[256];
            int tagEnd = StrContains(line, "]");
            if (tagEnd != -1)
            {
                strcopy(msg, sizeof(msg), line[tagEnd + 1]);
                TrimString(msg);
                if (msg[0] != '\0')
                {
                    PrintToChatAll("[\x04AGENT\x01] %s", msg);
                    executed = true;
                }
            }
        }
        // Extrai [CMD: ...]
        else if (StrContains(line, "[CMD:") == 0)
        {
            char cmd[256];
            int tagEnd = StrContains(line, "]");
            if (tagEnd != -1)
            {
                strcopy(cmd, sizeof(cmd), line[5]);
                cmd[tagEnd - 5] = '\0';
                TrimString(cmd);
                
                if (cmd[0] != '\0')
                {
                    char base[64];
                    strcopy(base, sizeof(base), cmd);
                    int space = StrContains(base, " ");
                    if (space != -1) base[space] = '\0';
                    
                    // Verifica se o comando é permitido e usuário tem acesso
                    int cmdIndex = -1;
                    for (int i = 0; i < sizeof(g_CommandMap); i++)
                    {
                        if (StrEqual(base, g_CommandMap[i].cmd, false))
                        {
                            cmdIndex = i;
                            break;
                        }
                    }
                    
                    if (cmdIndex == -1)
                    {
                        PrintToChat(client, "[\x04AGENT\x01] ❌ Comando não reconhecido: %s", base);
                        continue;
                    }
                    
                    // Verifica permissão
                    bool hasPerm = false;
                    switch (g_CommandMap[cmdIndex].level)
                    {
                        case CmdLevel_All:   hasPerm = true;
                        case CmdLevel_Admin: hasPerm = CheckCommandAccess(client, base, ADMFLAG_KICK);
                        case CmdLevel_Root:  hasPerm = CheckCommandAccess(client, base, ADMFLAG_ROOT);
                    }
                    
                    if (!hasPerm)
                    {
                        PrintToChat(client, "[\x04AGENT\x01] ❌ Sem permissão para: %s", base);
                        continue;
                    }
                    
                    // Força votação para comandos destrutivos
                    char finalCmd[256];
                    if (StrContains(cmd, "sm_kick") == 0)
                        Format(finalCmd, sizeof(finalCmd), "sm_votekick %s", cmd[8]);
                    else if (StrContains(cmd, "sm_ban") == 0)
                        Format(finalCmd, sizeof(finalCmd), "sm_voteban %s", cmd[7]);
                    else if (StrContains(cmd, "sm_map") == 0)
                        Format(finalCmd, sizeof(finalCmd), "sm_votemap %s", cmd[7]);
                    else
                        strcopy(finalCmd, sizeof(finalCmd), cmd);

                    LogAction(-1, -1, "[AGENT] %L executed: %s", client, finalCmd);
                    PrintToChat(client, "[\x04AGENT\x01] ✅ Executando: %s", finalCmd);
                    ServerCommand("%s", finalCmd);
                    executed = true;
                }
            }
        }
    }
    
    // Fallback
    if (!executed && response[0] != '\0')
    {
        if (StrContains(response, "ERROR_") != 0)
            PrintToChat(client, "[\x04AGENT\x01] %s", response);
        else
            PrintToChat(client, "[\x04AGENT\x01] ❌ Erro: %s", response);
    }
}

// ============================================================================
// UTILITÁRIOS
// ============================================================================
void LoadValidMaps()
{
    g_MapCount = 0;
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/maplist.txt");
    
    File f = OpenFile(path, "r");
    if (f == null)
    {
        static const char defaultMaps[][] = {
            "de_dust2", "de_inferno", "de_nuke", "de_train", "de_tides", 
            "cs_italy", "cs_office", "de_cbble", "de_aztec"
        };
        for (int i = 0; i < sizeof(defaultMaps); i++)
        {
            if (g_MapCount < MAX_MAPS)
            {
                strcopy(g_MapList[g_MapCount], 64, defaultMaps[i]);
                g_MapCount++;
            }
        }
        return;
    }
    
    char line[64];
    while (f.ReadLine(line, sizeof(line)) && g_MapCount < MAX_MAPS)
    {
        TrimString(line);
        if (line[0] != '\0' && line[0] != '/' && line[1] != '/')
        {
            strcopy(g_MapList[g_MapCount], 64, line);
            g_MapCount++;
        }
    }
    delete f;
}
