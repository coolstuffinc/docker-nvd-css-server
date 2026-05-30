#include <sourcemod>
#include <nvd_core>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define MAX_PLAYERS 65
#define MAX_MAPS 50
#define MAX_CTX 2048

// Estado do agente
bool g_AgentBusy = false;
int g_AgentClient = 0;

// Comandos permitidos (SEGURANÇA: NUNCA remova sem saber o que faz)
static const char g_AllowedCmds[][] = {
    "sm_votekick", "sm_voteban", "sm_votemap", "sm_map", 
    "sm_cvar", "status", "sm_plugins", "sm_reloadadmin"
};

// Cache de mapas
char g_MapList[MAX_MAPS][64];
int g_MapCount = 0;

public void OnPluginStart()
{
    RegConsoleCmd("sm_agent", Command_Agent, "AI Admin Agent");
    LoadValidMaps();
}

// ============================================================================
// COMANDO DE ENTRADA
// ============================================================================
public Action Command_Agent(int client, int args)
{
    if (g_AgentBusy)
    {
        ReplyToCommand(client, "[\x04AGENT\x01] Ocupado. Aguarde o processamento anterior.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        ReplyToCommand(client, "[\x04AGENT\x01] Uso: !agent <seu pedido>");
        return Plugin_Handled;
    }

    char request[512];
    GetCmdArgString(request, sizeof(request));
    StripQuotes(request);
    TrimString(request);

    g_AgentClient = client;
    g_AgentBusy = true;
    PrintToChat(client, "[\x04AGENT\x01] Processando...");

    // 1. Coleta contexto
    char context[MAX_CTX];
    BuildContext(context, sizeof(context), request);

    // 2. Chama IA
    NVD_AskAI(context, 
        "Você é um agente admin de CS:S. Use EXATAMENTE [CMD: comando] para ações ou [SAY: mensagem] para chat. Máximo 2 linhas. Português ou Inglês.", 
        Agent_Callback, client);
        
    return Plugin_Handled;
}

// ============================================================================
// CONSTRUÇÃO DO CONTEXTO (IDs + Mapas)
// ============================================================================
void BuildContext(char[] buffer, int maxlen, const char[] request)
{
    int pos = 0;
    
    // Lista de jogadores: [ID] Nome (Time)
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
        
        pos += Format(buffer[pos], maxlen - pos, "[%d] %s (%s)\n", i, name, teamName);
    }
    
    // Lista de mapas válidos
    pos += Format(buffer[pos], maxlen - pos, "VALID MAPS: ");
    for (int i = 0; i < g_MapCount; i++)
    {
        pos += Format(buffer[pos], maxlen - pos, "%s%s", i == 0 ? "" : ", ", g_MapList[i]);
        if (pos >= maxlen - 10) break;
    }
    Format(buffer[pos], maxlen - pos, "\nCURRENT: %s\n", GetCurrentMap());
    
    // Prompt final
    pos += Format(buffer[pos], maxlen - pos, "\nREQUEST: %s\n\nRULES:\n1. Use [CMD: <comando>] OU [SAY: <mensagem>].\n2. Máximo 2 linhas.\n3. NUNCA invente comandos ou mapas.", request);
}

// ============================================================================
// CALLBACK DA IA
// ============================================================================
public void Agent_Callback(const char[] response, any data)
{
    int client = view_as<int>(data);
    g_AgentBusy = false;
    
    if (!IsClientInGame(client)) return;

    bool executed = false;
    char line[256];
    int len = strlen(response);
    int start = 0;
    
    // Parse linha por linha
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
                
                if (cmd[0] != '\0' && IsCommandAllowed(cmd))
                {
                    LogAction(-1, -1, "[AGENT] Executing: %s", cmd);
                    ServerCommand("%s", cmd);
                    PrintToChat(client, "[\x04AGENT\x01] Comando executado: %s", cmd);
                    executed = true;
                }
                else if (cmd[0] != '\0')
                {
                    PrintToChat(client, "[\x04AGENT\x01] ❌ Comando bloqueado: %s", cmd);
                }
            }
        }
    }
    
    // Fallback: se não usou tags, imprime resposta crua (com cuidado)
    if (!executed && response[0] != '\0')
    {
        PrintToChat(client, "[\x04AGENT\x01] %s", response);
    }
}

// ============================================================================
// SEGURANÇA & UTILITÁRIOS
// ============================================================================
bool IsCommandAllowed(const char[] cmd)
{
    char base[64];
    strcopy(base, sizeof(base), cmd);
    int space = StrContains(base, " ");
    if (space != -1) base[space] = '\0';
    
    for (int i = 0; i < sizeof(g_AllowedCmds); i++)
    {
        if (StrEqual(base, g_AllowedCmds[i], false))
            return true;
    }
    return false;
}

void LoadValidMaps()
{
    g_MapCount = 0;
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/maplist.txt");
    
    // Tenta ler mapcycle.txt ou usa fallback
    File f = OpenFile(path, "r");
    if (f == null)
    {
        // Fallback: mapas padrão do CS:S
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
