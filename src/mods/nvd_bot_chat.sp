#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <nvd_core>

#pragma semicolon 1
#pragma newdecls required

#define CHAT_COOLDOWN 20.0
#define EVENT_CHANCE 35

ConVar g_CvarEnabled;
ConVar g_CvarCooldown;
ConVar g_CvarChance;

float g_LastBotChat;
Handle g_RoundStartTimer;
int g_CurrentRound;

public Plugin myinfo =
{
	name = "NVD Bot Chat",
	author = "OpenCode",
	description = "AI-powered contextual chat and roasting for bots",
	version = "1.0.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_bot_chat", "1", "Enable AI bot chat messages");
	g_CvarCooldown = CreateConVar("nvd_bot_chat_cooldown", "20.0", "Min seconds between bot messages");
	g_CvarChance = CreateConVar("nvd_bot_chat_chance", "35", "Percent chance to react to an event (0-100)");
	AutoExecConfig(true, "nvd_bot_chat");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("bomb_planted", Event_BombPlanted);
	HookEvent("bomb_defused", Event_BombDefused);
}

public void OnMapStart()
{
	g_LastBotChat = 0.0;
	g_CurrentRound = 0;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_CurrentRound++;
	delete g_RoundStartTimer;
	g_RoundStartTimer = CreateTimer(3.0, Timer_RoundStartMsg, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundStartMsg(Handle timer)
{
	g_RoundStartTimer = null;
	if (!CanBotChat())
		return Plugin_Stop;

	char context[256];
	if (g_CurrentRound > 1)
		Format(context, sizeof(context), "Round %d started. Generate a short motivational or trash-talk call in Portuguese BR, max 80 chars.", g_CurrentRound);
	else
		Format(context, sizeof(context), "Match started. Generate a short opening trash-talk phrase in Portuguese BR, max 80 chars.");

	AskBotChat(context);
	return Plugin_Stop;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	delete g_RoundStartTimer;

	int winner = event.GetInt("winner");
	int localTeam = GetLocalTeam();

	if (winner != localTeam && winner != 0)
		AskBotChat("Your team lost the round. Generate a short reaction in Portuguese BR roasting your team or acknowledging the loss, max 80 chars.");
	else if (winner == localTeam)
		AskBotChat("Your team won the round. Generate a short celebration or trash-talk in Portuguese BR, max 80 chars.");
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat())
	{
		char botName[32];
		GetClientName(client, botName, sizeof(botName));
		char context[256];
		Format(context, sizeof(context), "Bot '%s' planted the bomb. Generate a short celebratory phrase in Portuguese BR, max 80 chars.", botName);
		AskBotChat(context);
	}
}

public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat())
	{
		char botName[32];
		GetClientName(client, botName, sizeof(botName));
		char context[256];
		Format(context, sizeof(context), "Bot '%s' defused the bomb. Generate a short celebratory phrase in Portuguese BR, max 80 chars.", botName);
		AskBotChat(context);
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat() || GetRandomInt(1, 100) > g_CvarChance.IntValue)
		return;

	int killer = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int headshot = event.GetInt("headshot");
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));

	if (killer < 1 || !IsFakeClient(killer) && !IsFakeClient(victim))
		return;

	char killerName[32], victimName[32];
	GetClientName(killer, killerName, sizeof(killerName));
	GetClientName(victim, victimName, sizeof(victimName));

	char context[512];

	if (IsFakeClient(killer) && !IsFakeClient(victim))
	{
		if (headshot)
			Format(context, sizeof(context), "Bot '%s' killed player '%s' with HEADSHOT using %s. Generate a short roast trash-talking the dead player in Portuguese BR, max 80 chars.", killerName, victimName, weapon);
		else
			Format(context, sizeof(context), "Bot '%s' killed player '%s' with %s. Generate a short roast trash-talking the dead player in Portuguese BR, max 80 chars.", killerName, victimName, weapon);
	}
	else if (IsFakeClient(victim) && !IsFakeClient(killer))
	{
		if (headshot)
			Format(context, sizeof(context), "Bot '%s' was killed by player '%s' with HEADSHOT using %s. Generate a short phrase acknowledging the outplay in Portuguese BR, max 80 chars.", victimName, killerName, weapon);
		else
			Format(context, sizeof(context), "Bot '%s' was killed by player '%s' with %s. Generate a short reaction phrase in Portuguese BR, max 80 chars.", victimName, killerName, weapon);
	}
	else if (IsFakeClient(killer) && IsFakeClient(victim))
	{
		Format(context, sizeof(context), "Bot '%s' killed bot '%s' with %s. Generate a short funny phrase about bots fighting each other in Portuguese BR, max 80 chars.", killerName, victimName, weapon);
	}
	else
	{
		return;
	}

	AskBotChat(context);
}

bool CanBotChat()
{
	if (!g_CvarEnabled.BoolValue)
		return false;

	float delay = g_CvarCooldown.FloatValue;
	if (GetGameTime() - g_LastBotChat < delay)
		return false;

	int bots = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
			bots++;
	}
	return bots > 0;
}

void AskBotChat(const char[] context)
{
	if (!g_CvarEnabled.BoolValue)
		return;

	NVD_AskAI(context, "You are a Counter-Strike bot on a Brazilian server. Generate ONLY the message text, nothing else. Max 80 chars. Language: Brazilian Portuguese, informal. Style: humorous trash talk like Brazilian Twitch chat.", OnBotPhraseReady, 0);
}

public void OnBotPhraseReady(const char[] response, any data)
{
	if (response[0] == '\0')
		return;

	if (!g_CvarEnabled.BoolValue)
		return;

	float delay = g_CvarCooldown.FloatValue;
	if (GetGameTime() - g_LastBotChat < delay)
		return;

	int bots[MAXPLAYERS + 1];
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
			bots[count++] = i;
	}
	if (count == 0)
		return;

	char cleanMsg[160];
	strcopy(cleanMsg, sizeof(cleanMsg), response);
	ReplaceString(cleanMsg, sizeof(cleanMsg), "\"", "");

	char botName[32];
	GetClientName(bots[GetRandomInt(0, count - 1)], botName, sizeof(botName));

	PrintToChatAll("\x04[BOT %s]\x01 %s", botName, cleanMsg);
	g_LastBotChat = GetGameTime();
}

int GetLocalTeam()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
			return GetClientTeam(i);
	}
	return 3;
}
