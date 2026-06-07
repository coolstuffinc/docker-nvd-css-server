#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

// Natives do nvd_ollama
native int NVD_AskAI(const char[] prompt, const char[] system, Function callback, any data, int client = -1);
native bool NVD_PollResponse(char[] reply, int maxlen, any &data);

ConVar g_CvarEnabled;
bool g_Generating;
char g_TeamNameCt[64];
char g_TeamNameT[64];
char g_PlayersCt[512];
char g_PlayersT[512];
char g_DefaultHostname[256]; // Armazena o hostname original

public Plugin myinfo =
{
	name = "NVD Team Names",
	author = "OpenCode",
	description = "AI team name generator",
	version = "1.1.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_teamnames", "1", "Enable AI team name generation");
	AutoExecConfig(true, "nvd_teamnames");
	RegConsoleCmd("sm_teamnames", Command_TeamNames);

	// Hook para resetar o hostname no fim do round
	HookEvent("round_end", Event_RoundEnd);

	// Timer para ficar checando se a IA respondeu (Polling)
	CreateTimer(0.5, Timer_PollResponses, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnConfigsExecuted()
{
	// Salva o hostname padrão configurado no server.cfg
	ConVar cvarHostname = FindConVar("hostname");
	if (cvarHostname)
	{
		cvarHostname.GetString(g_DefaultHostname, sizeof(g_DefaultHostname));
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	// Reseta o hostname para o padrão do servidor ao fim do round
	if (g_DefaultHostname[0] != '\0')
	{
		ServerCommand("hostname \"%s\"", g_DefaultHostname);
	}
}

public Action Command_TeamNames(int client, int args)
{
	if (!g_CvarEnabled.BoolValue) { ReplyToCommand(client, "[NVD] Disabled."); return Plugin_Handled; }
	if (g_Generating) { ReplyToCommand(client, "[NVD] Generating..."); return Plugin_Handled; }
	GenerateTeamNames();
	return Plugin_Handled;
}

void GenerateTeamNames()
{
	g_Generating = true;
	g_PlayersCt[0] = '\0';
	g_PlayersT[0] = '\0';
	int ctPos = 0, tPos = 0, ctCount = 0, tCount = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsClientSourceTV(i)) continue;
		char name[64]; GetClientName(i, name, sizeof(name));
		if (IsFakeClient(i)) Format(name, sizeof(name), "[BOT]%s", name);
		int team = GetClientTeam(i);
		if (team == CS_TEAM_CT && ctPos < 480)
		{ ctPos += Format(g_PlayersCt[ctPos], sizeof(g_PlayersCt) - ctPos, "%s, ", name); ctCount++; }
		else if (team == CS_TEAM_T && tPos < 480)
		{ tPos += Format(g_PlayersT[tPos], sizeof(g_PlayersT) - tPos, "%s, ", name); tCount++; }
	}

	PrintToServer("[NVD_TEAMNAMES] CT(%d) TR(%d) - generating...", ctCount, tCount);
	QueryOllama("CT");
}

void QueryOllama(const char[] team)
{
	char prompt[512];
	if (StrEqual(team, "CT"))
		Format(prompt, sizeof(prompt), "Generate 1 creative CS team name for CT team. Players: %s", g_PlayersCt);
	else
		Format(prompt, sizeof(prompt), "Generate 1 creative CS team name for TR team. Players: %s CT team is '%s'. TR must be different.", g_PlayersT, g_TeamNameCt);

	char sys[256] = "Generate 1 short (max 25 chars) aggressive PT-BR CS team name. Return ONLY the name.";

	// Usamos 'teamData' para identificar quem é quem quando a resposta chegar
	any teamData = StrEqual(team, "CT") ? 0 : 1;

	// Chama a native do nvd_ollama (a requisição entra na fila se estiver cheio)
	NVD_AskAI(prompt, sys, INVALID_FUNCTION, teamData, 0);
}

public Action Timer_PollResponses(Handle timer)
{
	char reply[2048];
	any teamData;

	// Tenta pegar respostas destinadas a este plugin
	while (NVD_PollResponse(reply, sizeof(reply), teamData))
	{
		if (StrContains(reply, "ERROR") != -1)
		{
			PrintToServer("[NVD_TEAMNAMES] AI error: %s", reply);
			g_Generating = false;
			continue;
		}

		if (teamData == 0) // Resposta do CT
		{
			CleanName(reply, g_TeamNameCt, sizeof(g_TeamNameCt));
			PrintToServer("[NVD_TEAMNAMES] CT = '%s'", g_TeamNameCt);

			if (g_PlayersT[0])
				QueryOllama("TR");
			else
				Finish();
		}
		else if (teamData == 1) // Resposta do TR
		{
			CleanName(reply, g_TeamNameT, sizeof(g_TeamNameT));
			PrintToServer("[NVD_TEAMNAMES] TR = '%s'", g_TeamNameT);
			Finish();
		}
	}
	return Plugin_Continue;
}

void Finish()
{
	g_Generating = false;
	if (g_TeamNameCt[0] && g_TeamNameT[0])
	{
		PrintToChatAll("\x04[NVD] \x01Teams: \x03%s \x01(CT) vs \x03%s \x01(TR)", g_TeamNameCt, g_TeamNameT);
		PrintToChatAll("\x04[NVD] \x01Use \x04!teamnames\x01 to reroll.");
		ServerCommand("hostname \"NVD | %s vs %s\"", g_TeamNameCt, g_TeamNameT);
	}
}

void CleanName(const char[] raw, char[] out, int max)
{
	strcopy(out, max, raw);
	ReplaceString(out, max, "\"", "");
	ReplaceString(out, max, "\n", ""); ReplaceString(out, max, "\r", "");
	ReplaceString(out, max, "1.", ""); ReplaceString(out, max, "2.", ""); 
	ReplaceString(out, max, "- ", ""); ReplaceString(out, max, "#", "");
	TrimString(out);
	if (strlen(out) > 25) out[25] = '\0';
}
