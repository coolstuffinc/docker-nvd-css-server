#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define NAMES_COUNT 30

static const char g_BotNames[NAMES_COUNT][] = {
	"FalleN", "coldzera", "fer", "fnx", "KSCERATO",
	"yuurih", "boltz", "HEN1", "TACO", "s1mple",
	"ZywOo", "donk", "NiKo", "m0NESY", "dev1ce",
	"ropz", "Twistzz", "EliGE", "sh1ro", "jL",
	"iM", "frozen", "b1t", "XANTARES", "NAF",
	"apEX", "flameZ", "jks", "cadiaN", "rain"
};

bool g_NameUsed[NAMES_COUNT];
int g_BotNameIndex[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "NVD Bot Personas",
	author = "OpenCode",
	description = "Gives bots unique themed names and personas",
	version = "1.0.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnMapStart()
{
	for (int i = 0; i < NAMES_COUNT; i++)
		g_NameUsed[i] = false;

	for (int i = 1; i <= MaxClients; i++)
		g_BotNameIndex[i] = -1;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
		return;

	int idx = FindFreeName();
	if (idx == -1)
	{
		LogError("NVD Bot Personas: No free names available!");
		return;
	}

	g_NameUsed[idx] = true;
	g_BotNameIndex[client] = idx;
	SetClientName(client, g_BotNames[idx]);
}

public void OnClientDisconnect(int client)
{
	if (g_BotNameIndex[client] != -1)
	{
		g_NameUsed[g_BotNameIndex[client]] = false;
		g_BotNameIndex[client] = -1;
	}
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && g_BotNameIndex[client] != -1)
	{
		char currentName[32];
		GetClientName(client, currentName, sizeof(currentName));
		if (!StrEqual(currentName, g_BotNames[g_BotNameIndex[client]]))
			SetClientName(client, g_BotNames[g_BotNameIndex[client]]);
	}
	return Plugin_Continue;
}

int FindFreeName()
{
	int start = GetRandomInt(0, NAMES_COUNT - 1);
	for (int i = 0; i < NAMES_COUNT; i++)
	{
		int idx = (start + i) % NAMES_COUNT;
		if (!g_NameUsed[idx])
			return idx;
	}
	return -1;
}
