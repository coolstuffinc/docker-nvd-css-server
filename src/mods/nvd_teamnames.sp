#include <sourcemod>
#include <sdktools>
#include <nvd_core>

#pragma semicolon 1
#pragma newdecls required

#define TEAMNAME_PANEL_ID 9001
#define TEAMNAME_VERSION "1.0.0"

ConVar g_CvarEnabled;
ConVar g_CvarAutoGenerate;
char g_TeamNameCt[64];
char g_TeamNameT[64];
bool g_Generating;
int g_VotesAccept;
int g_VotesReroll;
int g_Voters[MAXPLAYERS + 1];
bool g_PendingVote;

public Plugin myinfo =
{
	name = "NVD Team Names",
	author = "OpenCode",
	description = "AI-powered team name generator for mixes",
	version = TEAMNAME_VERSION,
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_teamnames", "1", "Enable AI team name generation");
	g_CvarAutoGenerate = CreateConVar("nvd_teamnames_auto", "1", "Auto-generate names when mix starts");
	AutoExecConfig(true, "nvd_teamnames");
	
	RegConsoleCmd("sm_teamnames", Command_TeamNames, "Suggest new team names");
	
	// Hook mix start (attempt via mixmod command detection)
	HookEvent("round_start", Event_RoundStart);
	
	PrintToServer("[NVD_TEAMNAMES] +- Loaded v%s", TEAMNAME_VERSION);
}

public void OnMapStart()
{
	g_Generating = false;
	g_PendingVote = false;
	strcopy(g_TeamNameCt, sizeof(g_TeamNameCt), "Time CT");
	strcopy(g_TeamNameT, sizeof(g_TeamNameT), "Time TR");
}

public Action Command_TeamNames(int client, int args)
{
	if (!g_CvarEnabled.BoolValue)
	{
		ReplyToCommand(client, "[NVD] Team name generation is disabled.");
		return Plugin_Handled;
	}
	
	if (g_Generating)
	{
		ReplyToCommand(client, "[NVD] Already generating names, wait...");
		return Plugin_Handled;
	}
	
	GenerateTeamNames();
	return Plugin_Handled;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Auto-generate on first round if enabled
	static bool firstRound = true;
	if (firstRound && g_CvarAutoGenerate.BoolValue && g_CvarEnabled.BoolValue)
	{
		firstRound = false;
		CreateTimer(5.0, Timer_AutoGenerate, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_AutoGenerate(Handle timer)
{
	// Only generate if there are human players
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
		{
			GenerateTeamNames();
			break;
		}
	}
	return Plugin_Stop;
}

void GenerateTeamNames()
{
	if (g_Generating) return;
	
	// Build player list for context
	char playerContext[512];
	int pos = 0;
	int playerCount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
		{
			char name[32];
			GetClientName(i, name, sizeof(name));
			if (pos < 400)
				pos += Format(playerContext[pos], sizeof(playerContext) - pos, "%s, ", name);
			playerCount++;
		}
	}
	
	if (playerCount == 0)
	{
		PrintToServer("[NVD_TEAMNAMES] No players online, skipping generation");
		return;
	}
	
	g_Generating = true;
	
	char prompt[1024];
	Format(prompt, sizeof(prompt),
		"Generate 4 creative, aggressive Brazilian Portuguese Counter-Strike team names. Players: %s. Format: one per line, no numbers. Examples: Os Imortais, Furia Noturna, Chapa Quente, Pura Maldade",
		playerContext);
	
	char sysPrompt[256];
	Format(sysPrompt, sizeof(sysPrompt),
		"Generate CS team names in PT-BR. Short (max 20 chars), aggressive, creative, war-themed or BR slang. Return exactly 4 names, one per line. No numbers.");
	
	PrintToServer("[NVD_TEAMNAMES] Generating names for %d players...", playerCount);
	
	NVD_AskAI(prompt, sysPrompt, OnNamesGenerated, 0);
}

public void OnNamesGenerated(const char[] response, any data)
{
	g_Generating = false;
	
	if (response[0] == '\0' || StrContains(response, "ERROR_") != -1)
	{
		PrintToServer("[NVD_TEAMNAMES] Generation failed: %s", response);
		PrintToChatAll("[NVD] \x04Failed to generate team names. Use !teamnames to retry.");
		return;
	}
	
	// Parse names (one per line, pick first 2)
	char names[4][64];
	int nameCount = 0;
	
	char buffer[512];
	strcopy(buffer, sizeof(buffer), response);
	
	int start = 0;
	int end;
	while (start < strlen(buffer) && nameCount < 4)
	{
		// Skip empty lines and numbers
		while (start < strlen(buffer) && (buffer[start] == '\n' || buffer[start] == '\r' || buffer[start] == ' '))
			start++;
		
		if (start >= strlen(buffer)) break;
		
		end = start;
		while (end < strlen(buffer) && buffer[end] != '\n' && buffer[end] != '\r')
			end++;
		
		if (end > start)
		{
			char raw[64];
			int len = end - start;
			if (len > 63) len = 63;
			strcopy(raw, len + 1, buffer[start]);
			TrimString(raw);
			
			// Remove leading numbers like "1. " or "1- "
			if (raw[0] >= '0' && raw[0] <= '9')
			{
				int skip = 0;
				while (skip < len && raw[skip] >= '0' && raw[skip] <= '9') skip++;
				while (skip < len && (raw[skip] == '.' || raw[skip] == ')' || raw[skip] == '-' || raw[skip] == ' ')) skip++;
				if (skip > 0 && skip < len)
				{
					char cleaned[64];
					strcopy(cleaned, sizeof(cleaned), raw[skip]);
					strcopy(raw, sizeof(raw), cleaned);
				}
			}
			
			if (strlen(raw) > 3)
			{
				strcopy(names[nameCount], sizeof(names[]), raw);
				nameCount++;
			}
		}
		
		start = end + 1;
	}
	
	if (nameCount < 2)
	{
		PrintToServer("[NVD_TEAMNAMES] Not enough names generated");
		PrintToChatAll("[NVD] \x04Could not parse enough names. Try !teamnames.");
		return;
	}
	
	// Show panel with generated names
	ShowTeamNamePanel(names, nameCount);
}

void ShowTeamNamePanel(char[][] names, int count)
{
	char buffer[512];
	Panel panel = new Panel();
	
	panel.SetTitle("Team Names Generator");
	
	panel.DrawText(" ");
	panel.DrawText(" Suggested Teams:");
	panel.DrawText(" ");
	
	for (int i = 0; i < count && i < 4; i += 2)
	{
		char line[256];
		if (i + 1 < count)
			Format(line, sizeof(line), "  [%d] %s  vs  [%d] %s", i/2 + 1, names[i], i/2 + 1, names[i+1]);
		else
			Format(line, sizeof(line), "  [%d] %s", i/2 + 1, names[i]);
		panel.DrawText(line);
	}
	
	panel.DrawText(" ");
	panel.DrawText("1-4: Select pair  5: Reroll  0: Cancel");
	panel.DrawText(" ");
	
	// For simplicity: use the first pair
	strcopy(g_TeamNameCt, sizeof(g_TeamNameCt), names[0]);
	if (count > 1)
		strcopy(g_TeamNameT, sizeof(g_TeamNameT), names[1]);
	else
		Format(g_TeamNameT, sizeof(g_TeamNameT), "%s II", names[0]);
	
	char ctLine[128], trLine[128];
	Format(ctLine, sizeof(ctLine), ">> Auto-set: CT = %s", g_TeamNameCt);
	Format(trLine, sizeof(trLine), ">> Auto-set: TR = %s", g_TeamNameT);
	panel.DrawText(ctLine);
	panel.DrawText(trLine);
	
	panel.DrawText(" ");
	panel.CurrentKey = 5;
	panel.DrawText("Reroll");
	panel.CurrentKey = 10;
	panel.DrawText("Close");
	
	// Send to all players
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
			panel.Send(i, PanelHandler, 30);
	}
	
	delete panel;
	
	// Announce
	PrintToChatAll("\x04[NVD] \x01Teams: \x03%s \x01vs \x03%s", g_TeamNameCt, g_TeamNameT);
	PrintToChatAll("\x04[NVD] \x01Use \x04!teamnames\x01 to reroll.");
	
	// Update hostname
	char newHostname[128];
	Format(newHostname, sizeof(newHostname), "NVD | %s vs %s", g_TeamNameCt, g_TeamNameT);
	ServerCommand("hostname \"%s\"", newHostname);
	
	PrintToServer("[NVD_TEAMNAMES] Teams set: %s vs %s", g_TeamNameCt, g_TeamNameT);
}

public int PanelHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		if (param2 == 5) // Reroll
		{
			if (!g_Generating)
				GenerateTeamNames();
			else
				PrintToChat(client, "[NVD] Already generating, wait...");
		}
	}
	return 0;
}
