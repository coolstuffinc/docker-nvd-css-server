#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define MAX_BOT_NAMES 128

ArrayList g_BotNames;
int g_BotNameIndex[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "NVD Bot Personas",
	author = "OpenCode",
	description = "Gives bots unique themed names from config",
	version = "2.0.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	g_BotNames = new ArrayList(64);
	LoadBotNames();
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
		g_BotNameIndex[i] = -1;
}

void LoadBotNames()
{
	g_BotNames.Clear();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/nvd_bot_personalities.txt");

	if (!FileExists(path))
	{
		LogError("[BOT_PERSONAS] Config not found: %s — using fallback names", path);
		// Fallback pro caso de nao ter config
		g_BotNames.PushString("FalleN");
		g_BotNames.PushString("s1mple");
		g_BotNames.PushString("coldzera");
		g_BotNames.PushString("ZywOo");
		g_BotNames.PushString("NiKo");
		return;
	}

	KeyValues kv = new KeyValues("BotPersonalities");
	if (!kv.ImportFromFile(path))
	{
		LogError("[BOT_PERSONAS] Failed to parse: %s", path);
		delete kv;
		return;
	}

	kv.Rewind();
	if (!kv.GotoFirstSubKey(false))
	{
		LogError("[BOT_PERSONAS] No entries in %s", path);
		delete kv;
		return;
	}

	do
	{
		char name[64];
		kv.GetSectionName(name, sizeof(name));
		if (name[0] != '\0')
			g_BotNames.PushString(name);
	} while (kv.GotoNextKey(false));

	delete kv;

	PrintToServer("[BOT_PERSONAS] +- Loaded %d bot names from %s", g_BotNames.Length, path);
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client) || IsClientSourceTV(client))
		return;

	int count = g_BotNames.Length;
	if (count == 0)
	{
		LogError("[BOT_PERSONAS] No names available!");
		return;
	}

	// Procura nome livre
	int idx = FindFreeName(count);
	if (idx == -1)
	{
		// Reset all used names if we ran out
		for (int i = 1; i <= MaxClients; i++)
			g_BotNameIndex[i] = -1;
		idx = FindFreeName(count);
		if (idx == -1)
		{
			LogError("[BOT_PERSONAS] No free names after reset!");
			return;
		}
	}

	g_BotNameIndex[client] = idx;

	char name[64];
	g_BotNames.GetString(idx, name, sizeof(name));
	SetClientName(client, name);
}

public void OnClientDisconnect(int client)
{
	g_BotNameIndex[client] = -1;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && g_BotNameIndex[client] != -1)
	{
		char currentName[32];
		GetClientName(client, currentName, sizeof(currentName));

		char expectedName[64];
		g_BotNames.GetString(g_BotNameIndex[client], expectedName, sizeof(expectedName));

		if (!StrEqual(currentName, expectedName))
			SetClientName(client, expectedName);
	}
	return Plugin_Continue;
}

int FindFreeName(int count)
{
	int start = GetRandomInt(0, count - 1);
	for (int i = 0; i < count; i++)
	{
		int idx = (start + i) % count;
		bool used = false;
		for (int j = 1; j <= MaxClients; j++)
		{
			if (g_BotNameIndex[j] == idx)
			{
				used = true;
				break;
			}
		}
		if (!used)
			return idx;
	}
	return -1;
}
