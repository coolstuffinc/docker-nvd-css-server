#include <sourcemod>
#include <nvd/core>
#include <nvd/strings>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define MAX_PLAYERS 65
#define MAX_MAPS 50
#define MAX_CTX 3072
#define AGENT_COOLDOWN 8.0

// Cache para RCON
char g_LastRconResponse[2048];

// Estado do agente por jogador
float g_PlayerLastAgent[MAXPLAYERS + 1];

// Comandos e permissões
static const char g_CommandNames[][] = {
    "sm_votemap", "sm_votekick", "sm_voteban", 
    "sm_cvar", "sm_plugins", "sm_reloadadmin",
    "sm_rr", "sm_swap", "sm_live", "sm_prac",
    "bot_quota", "bot_add", "bot_kick", "bot_join_after_player",
    "mp_autoteambalance", "mp_limitteams", "mp_friendlyfire"
};

#define COMMAND_COUNT 17

// Cache de mapas
char g_MapList[MAX_MAPS][64];
int g_MapCount = 0;

public Plugin myinfo =
{
	name = "NVD Admin Agent",
	author = "OpenCode",
	description = "AI Admin Assistant with centralized strings",
	version = "3.2.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_agent", Command_Agent, "AI Admin Agent - ask the IA for help");
	RegConsoleCmd("sm_agent_help", Command_AgentHelp, "Show available agent commands");
	RegConsoleCmd("sm_agent_check", Command_AgentCheck, "Poll for the last RCON response");
	
	LoadValidMaps();
	NVD_RegisterStrings("nvd_agent");

	// Inicia timer de polling
	CreateTimer(0.5, Timer_PollResponses, _, TIMER_REPEAT);
}

stock void GetStr(const char[] section, const char[] key, char[] buffer, int maxlen)
{
    NVD_GetStr("nvd_agent", section, key, buffer, maxlen);
}

public void OnMapStart()
{
	LoadValidMaps();
}

public Action Command_AgentHelp(int client, int args)
{
	ReplyToCommand(client, "[\x04AGENT\x01] ═══ Comandos que posso sugerir ═══");
	for (int i = 0; i < COMMAND_COUNT; i++)
	{
		ReplyToCommand(client, "[\x04AGENT\x01]   • [%s]", g_CommandNames[i]);
	}
	return Plugin_Handled;
}

public Action Command_AgentCheck(int client, int args)
{
	if (g_LastRconResponse[0] == '\0') ReplyToCommand(client, "PENDING");
	else {
		ReplyToCommand(client, "%s", g_LastRconResponse);
		g_LastRconResponse[0] = '\0';
	}
	return Plugin_Handled;
}

public Action Command_Agent(int client, int args)
{
	if (!CheckCommandAccess(client, "sm_agent", ADMFLAG_KICK))
	{
		char msg[128]; GetStr("misc", "no_perm", msg, sizeof(msg));
		ReplyToCommand(client, msg);
		return Plugin_Handled;
	}
	
	float now = GetGameTime();
	if (client > 0 && now - g_PlayerLastAgent[client] < AGENT_COOLDOWN)
	{
		char msg[128]; GetStr("misc", "cooldown", msg, sizeof(msg));
		ReplyToCommand(client, msg, AGENT_COOLDOWN - (now - g_PlayerLastAgent[client]));
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		char usage[64], example[64];
		GetStr("misc", "usage", usage, sizeof(usage));
		GetStr("misc", "example", example, sizeof(example));
		ReplyToCommand(client, "[\x04AGENT\x01] %s", usage);
		ReplyToCommand(client, "[\x04AGENT\x01] %s", example);
		return Plugin_Handled;
	}
	
	char request[512];
	GetCmdArgString(request, sizeof(request));
	StripQuotes(request);
	TrimString(request);
	
	if (client > 0) g_PlayerLastAgent[client] = now;
	char proc[64]; GetStr("misc", "processing", proc, sizeof(proc));
	ReplyToCommand(client, proc);

	char context[MAX_CTX];
	BuildContext(context, sizeof(context), request, client);

	char sysBase[1024], sysRules[1024], systemPrompt[2048];
	GetStr("behavior", "system", sysBase, sizeof(sysBase));
	GetStr("behavior", "rules", sysRules, sizeof(sysRules));
	Format(systemPrompt, sizeof(systemPrompt), "%s %s", sysBase, sysRules);

	NVD_AskAI(context, systemPrompt, INVALID_FUNCTION, client);
	return Plugin_Handled;
}

void BuildContext(char[] buffer, int maxlen, const char[] request, int client)
{
	int pos = 0;
	char name[32]; 
	if (client > 0) GetClientName(client, name, sizeof(name));
	else strcopy(name, sizeof(name), "RCON");
	
	pos += Format(buffer[pos], maxlen - pos, "User:%s\nPlayers:", name);
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			char pName[20]; GetClientName(i, pName, sizeof(pName));
			int team = GetClientTeam(i);
			pos += Format(buffer[pos], maxlen - pos, "%d:%s(%s)%s ", i, pName, team==2?"T":"CT", CheckCommandAccess(i, "sm_kick", ADMFLAG_KICK)?"*":"");
		}
	}
	
	pos += Format(buffer[pos], maxlen - pos, "\nCmds:");
	for (int i = 0; i < COMMAND_COUNT; i++) {
		if (CheckCommandAccess(client, g_CommandNames[i], ADMFLAG_KICK)) {
			pos += Format(buffer[pos], maxlen - pos, "%s,", g_CommandNames[i]);
		}
	}

	pos += Format(buffer[pos], maxlen - pos, "\nReq:%s", request);
}

public Action Timer_PollResponses(Handle timer)
{
	char reply[2048];
	any data;
	while (NVD_PollResponse(reply, sizeof(reply), data))
	{
		ProcessResponse(reply, data);
	}
	return Plugin_Continue;
}

void ProcessResponse(const char[] response, any data)
{
	int client = view_as<int>(data);
	if (client == 0) strcopy(g_LastRconResponse, sizeof(g_LastRconResponse), response);
	if (client != 0 && !IsClientInGame(client)) return;

	char line[256], unknownMsg[128], noAccMsg[128], execMsg[128];
	GetStr("misc", "unknown_cmd", unknownMsg, sizeof(unknownMsg));
	GetStr("misc", "no_access", noAccMsg, sizeof(noAccMsg));
	GetStr("misc", "executing", execMsg, sizeof(execMsg));

	int start = 0, len = strlen(response);
	while (start < len) {
		int end = FindCharInString(response[start], '\n');
		if (end == -1) end = strlen(response) - start;
		strcopy(line, sizeof(line), response[start]);
		line[end] = '\0'; TrimString(line);
		start += end + 1;
		if (!line[0]) continue;

		if (StrContains(line, "[SAY:") == 0) {
			char msg[256];
			int tagEnd = StrContains(line, "]");
			if (tagEnd != -1) {
				strcopy(msg, sizeof(msg), line[5]);
				msg[tagEnd - 5] = '\0'; TrimString(msg);
				if (msg[0]) {
					PrintToChatAll("[\x04AGENT\x01] %s", msg);
					PrintToServer("[AGENT] 💬 Mensagem: %s", msg);
				}
			}
		} else if (StrContains(line, "[CMD:") == 0) {
			char cmd[256];
			int tagEnd = StrContains(line, "]");
			if (tagEnd != -1) {
				strcopy(cmd, sizeof(cmd), line[5]);
				cmd[tagEnd - 5] = '\0'; TrimString(cmd);
				if (cmd[0]) {
					PrintToServer("[AGENT] ⚡ Comando: %s", cmd);
					char base[64]; strcopy(base, sizeof(base), cmd);
					int sp = StrContains(base, " "); if (sp != -1) base[sp] = '\0';
					
					bool found = false;
					for (int i=0; i<COMMAND_COUNT; i++) if (StrEqual(base, g_CommandNames[i], false)) { found = true; break; }
					
					if (!found) { ReplyToCommand(client, unknownMsg, base); continue; }
					if (!CheckCommandAccess(client, base, ADMFLAG_KICK)) { ReplyToCommand(client, noAccMsg, base); continue; }
					
					ReplyToCommand(client, execMsg, cmd);
					ServerCommand("%s", cmd);
				}
			}
		}
	}
}

void LoadValidMaps()
{
	g_MapCount = 0;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/maplist.txt");
	File f = OpenFile(path, "r");
	if (f == null) return;
	char line[64];
	while (f.ReadLine(line, sizeof(line)) && g_MapCount < MAX_MAPS) {
		TrimString(line);
		if (line[0] != '\0' && line[0] != '/') strcopy(g_MapList[g_MapCount++], 64, line);
	}
	delete f;
}
