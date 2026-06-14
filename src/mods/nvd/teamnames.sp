#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <nvd/core>
#include <nvd/strings>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

ConVar g_CvarEnabled;
char g_PlayersCt[512];
char g_PlayersT[512];

// Cookie para persistência
Handle g_hSuggestionCookie;
char g_PlayerSuggestion[MAXPLAYERS + 1][32];

public Plugin myinfo =
{
	name = "NVD Team Names (Persistent Suggestions)",
	author = "OpenCode",
	description = "Players can suggest team names anytime; suggestions persist across maps",
	version = "3.1.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_teamnames", "1", "Enable AI/Voting team name generation");
	AutoExecConfig(true, "nvd_teamnames");
	
	RegConsoleCmd("sm_teamnames", Command_TeamNames);
	RegConsoleCmd("sm_suggest", Command_Suggest);

	g_hSuggestionCookie = RegClientCookie("nvd_teamname_suggestion", "Sua sugestão favorita de nome de time", CookieAccess_Private);

	// Timer para polling da IA
	CreateTimer(0.5, Timer_PollResponses, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	// Carrega para quem já estiver no server (late load)
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && AreClientCookiesCached(i))
			OnClientCookiesCached(i);
	}
    NVD_RegisterStrings("nvd");
}

public void OnClientDisconnect(int client)
{
	g_PlayerSuggestion[client][0] = '\0';
}

public void OnClientCookiesCached(int client)
{
	char buffer[32];
	GetClientCookie(client, g_hSuggestionCookie, buffer, sizeof(buffer));
	if (buffer[0] != '\0')
	{
		strcopy(g_PlayerSuggestion[client], 32, buffer);
	}
}

public Action Command_Suggest(int client, int args)
{
	if (client == 0) return Plugin_Handled;

	if (args < 1)
	{
		if (g_PlayerSuggestion[client][0] != '\0')
			ReplyToCommand(client, "\x04[NVD] \x01Sua sugestão atual é: \x03\"%s\"\x01. Use \x04!suggest <nome>\x01 para mudar.", g_PlayerSuggestion[client]);
		else
			ReplyToCommand(client, "\x04[NVD] \x01Você ainda não sugeriu um nome. Use \x04!suggest <nome>\x01.");
		return Plugin_Handled;
	}

	char suggestion[32];
	GetCmdArgString(suggestion, sizeof(suggestion));
	StripQuotes(suggestion);
	TrimString(suggestion);

	if (strlen(suggestion) < 3)
	{
		ReplyToCommand(client, "\x04[NVD] \x01Nome muito curto (mínimo 3 letras).");
		return Plugin_Handled;
	}

	strcopy(g_PlayerSuggestion[client], 32, suggestion);
	SetClientCookie(client, g_hSuggestionCookie, suggestion);
	
	ReplyToCommand(client, "\x04[NVD] \x01Sugestão salva: \x03\"%s\"\x01. Será usada na próxima votação de time.", suggestion);

	return Plugin_Handled;
}

public Action Command_TeamNames(int client, int args)
{
	if (!g_CvarEnabled.BoolValue) return Plugin_Handled;
	
	ProcessTeamNaming(CS_TEAM_T);
	ProcessTeamNaming(CS_TEAM_CT);
	
	return Plugin_Handled;
}

void ProcessTeamNaming(int team)
{
	char teamSuggestions[5][32];
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
		{
			if (g_PlayerSuggestion[i][0] != '\0')
			{
				strcopy(teamSuggestions[count], 32, g_PlayerSuggestion[i]);
				count++;
				if (count >= 5) break;
			}
		}
	}

	if (count == 0)
	{
		PrintToChatAll("\x04[NVD] \x01Sem sugestões dos jogadores para o time \x03%s\x01. Chamando IA...", (team == CS_TEAM_T) ? "TR" : "CT");
		RefreshPlayerLists();
		QueryOllama((team == CS_TEAM_CT) ? "CT" : "TR");
	}
	else if (count == 1)
	{
		ApplyTeamName(team, teamSuggestions[0]);
	}
	else
	{
		StartTeamVoteNative(team, teamSuggestions, count);
	}
}

void StartTeamVoteNative(int team, char suggestions[5][32], int count)
{
	Menu menu = new Menu(Handle_VoteResults);
	menu.SetTitle("Vote no nome do time %s:", (team == CS_TEAM_T) ? "TR" : "CT");

	for (int i = 0; i < count; i++)
	{
		menu.AddItem(suggestions[i], suggestions[i]);
	}

	menu.ExitButton = false;
	
	int clients[MAXPLAYERS], total = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
			clients[total++] = i;
	}

	if (total > 0)
		menu.DisplayVote(clients, total, 15);
}

public int Handle_VoteResults(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End) delete menu;
	else if (action == MenuAction_VoteEnd)
	{
		char winner[32];
		menu.GetItem(param1, winner, sizeof(winner));
		
		char title[64];
		menu.GetTitle(title, sizeof(title));
		int team = (StrContains(title, "TR") != -1) ? CS_TEAM_T : CS_TEAM_CT;
		
		ApplyTeamName(team, winner);
	}
	return 0;
}

void ApplyTeamName(int team, const char[] name)
{
	PrintToChatAll("\x04[NVD] \x01Nome definido para o time \x03%s\x01: \x04%s", 
		(team == CS_TEAM_T) ? "TR" : "CT", name);
	
	char cvarName[64];
	Format(cvarName, sizeof(cvarName), "sm_mixmod_custom_name_%s", (team == CS_TEAM_T) ? "t" : "ct");
	
	ConVar cv = FindConVar(cvarName);
	if (cv != null) cv.SetString(name);
}

void RefreshPlayerLists()
{
	g_PlayersCt[0] = '\0';
	g_PlayersT[0] = '\0';
	int ctPos = 0, tPos = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsClientSourceTV(i)) continue;
		char name[64]; GetClientName(i, name, sizeof(name));
		if (IsFakeClient(i)) Format(name, sizeof(name), "[BOT]%s", name);
		int team = GetClientTeam(i);
		if (team == CS_TEAM_CT && ctPos < 480)
		{ ctPos += Format(g_PlayersCt[ctPos], sizeof(g_PlayersCt) - ctPos, "%s, ", name); }
		else if (team == CS_TEAM_T && tPos < 480)
		{ tPos += Format(g_PlayersT[tPos], sizeof(g_PlayersT) - tPos, "%s, ", name); }
	}
}

void QueryOllama(const char[] team)
{
	char promptFmt[512], prompt[512], sys[256];
	if (StrEqual(team, "CT"))
		NVD_GetStr("nvd.teamnames.prompt_ct", promptFmt, sizeof(promptFmt));
	else
		NVD_GetStr("nvd.teamnames.prompt_tr", promptFmt, sizeof(promptFmt));

	NVD_GetStr("nvd.teamnames.system", sys, sizeof(sys));
	
	Format(prompt, sizeof(prompt), promptFmt, StrEqual(team, "CT") ? g_PlayersCt : g_PlayersT);

	any teamData = StrEqual(team, "CT") ? 1 : 0;
	NVD_AskAI(prompt, sys, INVALID_FUNCTION, teamData, "", 0, 0.0);
}

public Action Timer_PollResponses(Handle timer)
{
	char reply[2048];
	any teamData;
	while (NVD_PollResponse(reply, sizeof(reply), teamData))
	{
		PrintToServer("[NVD_TEAMNAMES] Recebeu resposta: \"%s\" (Data: %d)", reply, teamData);

		if (StrContains(reply, "ERROR") != -1)
		{
			PrintToServer("[NVD_TEAMNAMES] Erro detectado na resposta da IA.");
			continue;
		}

		char name[32];
		CleanName(reply, name, sizeof(name));
		ApplyTeamName(teamData == 1 ? CS_TEAM_CT : CS_TEAM_T, name);
	}
	return Plugin_Continue;
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
