#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <ripext>

#pragma semicolon 1
#pragma newdecls required

#define OLLAMA_URL "http://172.17.0.1:11433/api/generate"

ConVar g_CvarEnabled;
ConVar g_CvarModel;
bool g_Generating;
char g_TeamNameCt[64];
char g_TeamNameT[64];
char g_PlayersCt[512];
char g_PlayersT[512];

public Plugin myinfo =
{
	name = "NVD Team Names",
	author = "OpenCode",
	description = "AI team name generator",
	version = "1.0.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_teamnames", "1", "Enable AI team name generation");
	g_CvarModel = CreateConVar("nvd_teamnames_model", "qwen2.5:1.5b", "Ollama model");
	AutoExecConfig(true, "nvd_teamnames");
	RegConsoleCmd("sm_teamnames", Command_TeamNames);
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
	QueryOllama("CT", OnCtName);
}

void QueryOllama(const char[] team, HTTPRequestCallback callback)
{
	char model[64]; g_CvarModel.GetString(model, sizeof(model));
	
	char prompt[512];
	if (StrEqual(team, "CT"))
		Format(prompt, sizeof(prompt), "Generate 1 creative CS team name for CT team. Players: %s", g_PlayersCt);
	else
		Format(prompt, sizeof(prompt), "Generate 1 creative CS team name for TR team. Players: %s CT team is '%s'. TR must be different.", g_PlayersT, g_TeamNameCt);
	
	char sys[256] = "Generate 1 short (max 25 chars) aggressive PT-BR CS team name. Return ONLY the name.";
	
	// Build JSON manually
	char json[2048];
	Format(json, sizeof(json),
		"{\"model\":\"%s\",\"prompt\":\"%s\",\"system\":\"%s\",\"stream\":false,\"options\":{\"temperature\":0.8}}",
		model, prompt, sys);
	
	HTTPRequest req = new HTTPRequest(OLLAMA_URL);
	JSONObject body = JSONObject.FromString(json);
	req.Post(body, callback);
	delete body;
}

public void OnCtName(HTTPResponse response, any value)
{
	if (response.Status != HTTPStatus_OK)
	{
		LogError("[NVD_TEAMNAMES] CT name HTTP error: %d", response.Status);
		g_Generating = false; return;
	}
	
	JSONObject obj = view_as<JSONObject>(response.Data);
	char raw[256]; obj.GetString("response", raw, sizeof(raw));
	delete obj;
	
	CleanName(raw, g_TeamNameCt, sizeof(g_TeamNameCt));
	PrintToServer("[NVD_TEAMNAMES] CT = '%s'", g_TeamNameCt);
	
	// Now generate TR name
	if (g_PlayersT[0])
		QueryOllama("TR", OnTrName);
	else
		Finish();
}

public void OnTrName(HTTPResponse response, any value)
{
	if (response.Status != HTTPStatus_OK)
	{
		LogError("[NVD_TEAMNAMES] TR name HTTP error: %d", response.Status);
		Format(g_TeamNameT, sizeof(g_TeamNameT), "%s II", g_TeamNameCt);
		Finish(); return;
	}
	
	JSONObject obj = view_as<JSONObject>(response.Data);
	char raw[256]; obj.GetString("response", raw, sizeof(raw));
	delete obj;
	
	CleanName(raw, g_TeamNameT, sizeof(g_TeamNameT));
	PrintToServer("[NVD_TEAMNAMES] TR = '%s'", g_TeamNameT);
	Finish();
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
