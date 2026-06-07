#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <nvd_core>

#pragma semicolon 1
#pragma newdecls required

#define CHAT_COOLDOWN 12.0
#define EVENT_CHANCE 45

ConVar g_CvarEnabled;
ConVar g_CvarCooldown;
ConVar g_CvarChance;
ConVar g_CvarLogging;
KeyValues g_PromptKV = null;
KeyValues g_PersonalityKV = null;
KeyValues g_GameKV = null;
KeyValues g_StringsDefault = null;
KeyValues g_StringsLang = null;
ConVar g_LangCvar;

float g_LastBotChat;
Handle g_RoundStartTimer;
int g_CurrentRound;
int g_BombPlanted;

// Structured log tracking per bot
char g_LastEventType[MAXPLAYERS + 1][32];
char g_LastTarget[MAXPLAYERS + 1][64];
char g_LastMood[MAXPLAYERS + 1][128];
char g_LastSysPrompt[MAXPLAYERS + 1][1024];
char g_LastUserPrompt[MAXPLAYERS + 1][256];
float g_LastAskTime[MAXPLAYERS + 1];

// Shared _meta template snippets (loaded from _meta section)
char g_MetaKeys[16][64];
char g_MetaValues[16][1024];
int g_MetaCount;

public Plugin myinfo =
{
	name = "NVD Bot Chat",
	author = "OpenCode",
	description = "AI-powered contextual chat and roasting for bots",
	version = "2.0.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_bot_chat", "1", "Enable AI bot chat messages");
	g_CvarCooldown = CreateConVar("nvd_bot_chat_cooldown", "12.0", "Min seconds between bot messages");
	g_CvarChance = CreateConVar("nvd_bot_chat_chance", "45", "Percent chance to react to an event (0-100)");
	g_CvarLogging = CreateConVar("nvd_bot_chat_log", "1", "Enable structured bot chat logging to nvd_bot_chat.log");
	g_LangCvar = CreateConVar("nvd_bot_chat_language", "default", "Language for bot chat strings (default, pt-br, etc.)");
	g_LangCvar.AddChangeHook(OnLanguageChanged);
	AutoExecConfig(true, "nvd_bot_chat");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_say", Event_PlayerSay);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("bomb_planted", Event_BombPlanted);
	HookEvent("bomb_defused", Event_BombDefused);
	HookEvent("cs_win_panel_round", Event_WinPanel);

	// Polling timer for AI responses (every 500ms)
	CreateTimer(0.5, Timer_PollResponses, _, TIMER_REPEAT);
	
	LoadPromptTemplates();
	LoadPersonalities();
	LoadStrings();
	LoadMetaFromStrings();
	
	// Comando para recarregar templates
	RegAdminCmd("sm_botchat_reload", Command_ReloadPrompts, ADMFLAG_GENERIC);
}

public void OnMapStart()
{
	g_LastBotChat = 0.0;
	g_CurrentRound = 0;
	g_BombPlanted = 0;

	delete g_GameKV;
	g_GameKV = null;

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "../../resource/cstrike_english.txt");
	if (!FileExists(path)) return;

	char tmp[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, tmp, sizeof(tmp), "data/nvd_utf8tmp.txt");

	File f = OpenFile(path, "rb");
	if (f == null) return;
	File out = OpenFile(tmp, "wb");
	if (out == null) { delete f; return; }

	int buf[4096], outbuf[4096];
	int count;
	bool first = true;
	while ((count = f.Read(buf, 4096, 1)) > 0)
	{
		int j = 0;
		for (int i = 0; i < count; i++)
		{
			if (buf[i] != 0)
			{
				if (first && j < 2 && (buf[i] == 0xFF || buf[i] == 0xFE))
					continue; // skip UTF-16LE BOM bytes
				outbuf[j++] = buf[i];
			}
		}
		first = false;
		if (j > 0) out.Write(outbuf, j, 1);
	}
	delete f; delete out;

	g_GameKV = new KeyValues("lang");
	g_GameKV.ImportFromFile(tmp);
	DeleteFile(tmp);
}

public void OnPluginEnd()
{
	delete g_GameKV;
	delete g_StringsDefault;
	delete g_StringsLang;
}

public void OnLanguageChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
	LoadStrings();
	LoadMetaFromStrings();
}

void LoadStrings()
{
	if (g_StringsDefault != null)
		delete g_StringsDefault;
	if (g_StringsLang != null)
		delete g_StringsLang;
	g_StringsDefault = null;
	g_StringsLang = null;

	char path[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, path, sizeof(path), "configs/nvd_bot_chat_strings_default.txt");
	if (FileExists(path))
	{
		g_StringsDefault = new KeyValues("BotChatStrings");
		g_StringsDefault.ImportFromFile(path);
		PrintToServer("[BOT_CHAT] +- Default strings loaded from %s", path);
	}

	char lang[32];
	g_LangCvar.GetString(lang, sizeof(lang));
	if (!StrEqual(lang, "default") && lang[0])
	{
		char langPath[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, langPath, sizeof(langPath), "configs/nvd_bot_chat_strings_%s.txt", lang);
		if (FileExists(langPath))
		{
			g_StringsLang = new KeyValues("BotChatStrings");
			g_StringsLang.ImportFromFile(langPath);
			PrintToServer("[BOT_CHAT] +- Language overrides loaded from %s", langPath);
		}
		else
		{
			LogError("[BOT_CHAT] Language file not found: %s", langPath);
		}
	}

	if (g_StringsDefault == null && g_StringsLang == null)
		PrintToServer("[BOT_CHAT] No string configs found — using hardcoded fallbacks");
}

stock void GetStr(const char[] section, const char[] key, char[] buffer, int maxlen, const char[] fallback)
{
	if (g_StringsLang != null)
	{
		g_StringsLang.Rewind();
		if (g_StringsLang.JumpToKey(section))
		{
			g_StringsLang.GetString(key, buffer, maxlen);
			g_StringsLang.GoBack();
			if (buffer[0] != '\0')
				return;
		}
	}
	if (g_StringsDefault != null)
	{
		g_StringsDefault.Rewind();
		if (g_StringsDefault.JumpToKey(section))
		{
			g_StringsDefault.GetString(key, buffer, maxlen);
			g_StringsDefault.GoBack();
			if (buffer[0] != '\0')
				return;
		}
	}
	strcopy(buffer, maxlen, fallback);
}

// ============================================================================
// CONTEXT BUILDER
// ============================================================================

// Mapa de armas para nomes mais amigaveis
void FriendlyWeaponName(const char[] weapon, char[] output, int maxlen)
{
    char base[32];
    strcopy(base, sizeof(base), weapon);
    
    bool headshot = false;
    int hsPos = StrContains(base, " HS");
    if (hsPos != -1)
    {
        base[hsPos] = '\0';
        headshot = true;
    }
    
    // Tenta ler do config weapons primeiro
    if (g_PromptKV != null)
    {
        char kvName[32];
        g_PromptKV.Rewind();
        if (g_PromptKV.JumpToKey("weapons") && g_PromptKV.JumpToKey(base))
        {
            g_PromptKV.GetString("name", kvName, sizeof(kvName));
            if (kvName[0] != '\0')
            {
                strcopy(output, maxlen, kvName);
                if (headshot)
                    Format(output, maxlen, "%s HS", output);
                return;
            }
        }
    }
    
    char weaponName[32];
    GetStr("weapons_fallback", base, weaponName, sizeof(weaponName), "");
    if (weaponName[0])
        strcopy(output, maxlen, weaponName);
    else
        strcopy(output, maxlen, base);
    
    if (headshot)
        Format(output, maxlen, "%s HS", output);
}
void BuildContext(char[] buffer, int maxlen, const char[] event, 
	int mainClient = -1, int targetClient = -1, const char[] weapon = "")
{
	int ctScore = CS_GetTeamScore(CS_TEAM_CT);
	int tScore = CS_GetTeamScore(CS_TEAM_T);
	
	char timeStr[64];
	int timeLeft = RoundFloat(GetGameTime());
	int mins = timeLeft / 60;
	int secs = timeLeft % 60;
	char timeFmt[64];
	GetStr("misc", "time_format", timeFmt, sizeof(timeFmt), "%d minute(s) and %d seconds of game time");
	Format(timeStr, sizeof(timeStr), timeFmt, mins, secs);
	
	int ctAlive = 0, tAlive = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
		if (GetClientTeam(i) == 2) tAlive++;
		else if (GetClientTeam(i) == 3) ctAlive++;
	}
	
	// Detectar clutch (1 vs N) quando o 1 for um player real
	char clutchTag[32];
	clutchTag[0] = '\0';
	
	// Encontrar player real
	int humanClient = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
		{
			humanClient = i;
			break;
		}
	}
	
	if (humanClient > 0)
	{
		int humanTeam = GetClientTeam(humanClient);
		bool humanAlive = IsPlayerAlive(humanClient);
		
		// Player real e o unico vivo do time em situacao 1vN
		if (humanAlive && ((humanTeam == CS_TEAM_T && tAlive == 1 && ctAlive >= 2) ||
			(humanTeam == CS_TEAM_CT && ctAlive == 1 && tAlive >= 2)))
		{
			GetStr("misc", "clutch_tag", clutchTag, sizeof(clutchTag), " CLUTCH");
		}
	}
	
	char mainName[32], targetName[32];
	if (mainClient > 0 && IsClientInGame(mainClient))
	{
		GetClientName(mainClient, mainName, sizeof(mainName));
	}
	else
	{
		mainName[0] = '\0';
	}
	
	if (targetClient > 0 && IsClientInGame(targetClient))
	{
		GetClientName(targetClient, targetName, sizeof(targetName));
	}
	
	int pos = 0;
	
	// Evento (quem fez o que) vem primeiro
	if (mainName[0])
	{
		char mainTag[16];
		if (mainClient > 0 && IsFakeClient(mainClient))
			strcopy(mainTag, sizeof(mainTag), " BOT");
		else if (mainClient > 0)
			strcopy(mainTag, sizeof(mainTag), " Player");
		else
			mainTag[0] = '\0';
		
		pos += Format(buffer[pos], maxlen - pos, "@%s%s %s", mainName, mainTag, event);
		if (targetName[0] && targetClient != mainClient)
		{
			char targetTag[16];
			if (targetClient > 0 && IsFakeClient(targetClient))
				strcopy(targetTag, sizeof(targetTag), " BOT");
			else if (targetClient > 0)
				strcopy(targetTag, sizeof(targetTag), " Player");
			else
				targetTag[0] = '\0';
			pos += Format(buffer[pos], maxlen - pos, " @%s%s", targetName, targetTag);
		}
		if (weapon[0])
		{
			char friendlyWeapon[32];
			FriendlyWeaponName(weapon, friendlyWeapon, sizeof(friendlyWeapon));
			
			// Separa headshot das aspas: "M4 HS" -> com "M4" na cabeca
			char weaponShot[64], weaponKnife[64], hsStr[64];
			GetStr("misc", "weapon_shot", weaponShot, sizeof(weaponShot), " with %s");
			GetStr("misc", "headshot", hsStr, sizeof(hsStr), " headshot");
			GetStr("misc", "weapon_knife", weaponKnife, sizeof(weaponKnife), " with knife");
			char knifeName[32];
			GetStr("misc", "knife", knifeName, sizeof(knifeName), "knife");

			int hsPos = StrContains(friendlyWeapon, " HS");
			if (hsPos != -1)
			{
				friendlyWeapon[hsPos] = '\0';
				pos += Format(buffer[pos], maxlen - pos, weaponShot, friendlyWeapon);
				pos += Format(buffer[pos], maxlen - pos, "%s", hsStr);
			}
			else
			{
				if (StrEqual(friendlyWeapon, knifeName))
					pos += Format(buffer[pos], maxlen - pos, "%s", weaponKnife);
				else
					pos += Format(buffer[pos], maxlen - pos, weaponShot, friendlyWeapon);
			}
		}
		pos += Format(buffer[pos], maxlen - pos, ". ");
	}
	else if (event[0])
	{
		// Sem jogador especifico: "O CT venceu o round."
		pos += Format(buffer[pos], maxlen - pos, "%s ", event);
	}
	
	// Depois o estado da partida
	char mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));
	
	char mapFmt[256];
	GetStr("misc", "map_status", mapFmt, sizeof(mapFmt), 
		"Map %s, Round %d, score %d-%d, %s, %d TR alive vs %d CT alive");
	pos += Format(buffer[pos], maxlen - pos, mapFmt, 
		mapName, g_CurrentRound, tScore, ctScore, timeStr, tAlive, ctAlive);
	
	if (g_BombPlanted > 0)
	{
		char bombStatus[32];
		GetStr("misc", "bomb_planted", bombStatus, sizeof(bombStatus), ", bomb planted");
		pos += Format(buffer[pos], maxlen - pos, "%s", bombStatus);
	}
	
	pos += Format(buffer[pos], maxlen - pos, "%s.", clutchTag);
}

void GetPlayerLocation(int client, char[] buffer, int maxlen)
{
	if (client > 0 && IsClientInGame(client))
	{
		GetEntPropString(client, Prop_Send, "m_szLastPlaceName", buffer, maxlen);
		if (buffer[0] == '\0')
			strcopy(buffer, maxlen, "");
	}
	else
	{
		buffer[0] = '\0';
	}
}

// ============================================================================
// EVENTS
// ============================================================================
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_CurrentRound++;
	g_BombPlanted = 0;
	delete g_RoundStartTimer;
	g_RoundStartTimer = CreateTimer(3.0, Timer_RoundStartMsg, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundStartMsg(Handle timer)
{
	g_RoundStartTimer = null;
	if (!CanBotChat()) return Plugin_Stop;
	
	// Round events: 20% chance (menos interessante)
	if (GetRandomInt(1, 100) > 20) return Plugin_Stop;
	
	char roundStart[64], matchStart[64];
	GetStr("events", "round_start", roundStart, sizeof(roundStart), "The round has started.");
	GetStr("events", "match_start", matchStart, sizeof(matchStart), "The match has started!");
	char ctx[1024];
	BuildContext(ctx, sizeof(ctx), g_CurrentRound > 1 ? roundStart : matchStart);
	AskBotChat(ctx, -1, "round_start");
	return Plugin_Stop;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	delete g_RoundStartTimer;
	
	int winner = event.GetInt("winner");
	
	if (!CanBotChat()) return;
	
	// Round events: 20% chance
	if (GetRandomInt(1, 100) > 20) return;
	
	char trWin[64], ctWin[64];
	GetStr("events", "tr_win", trWin, sizeof(trWin), "TR won the round.");
	GetStr("events", "ct_win", ctWin, sizeof(ctWin), "CT won the round.");
	char ctx[1024];
	if (winner == 2)
		BuildContext(ctx, sizeof(ctx), trWin);
	else if (winner == 3)
		BuildContext(ctx, sizeof(ctx), ctWin);
	else
		return;
	AskBotChat(ctx, -1, "round_end");
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
	g_BombPlanted = GetGameTime();
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat())
	{
		// Bomb events: 50% chance
		if (GetRandomInt(1, 100) > 50) return;
		
		char bombPlant[64], locSuffix[64];
		GetStr("events", "bomb_plant", bombPlant, sizeof(bombPlant), "planted the bomb!");
		GetStr("events", "location_suffix", locSuffix, sizeof(locSuffix), "%s at %s.");
		char ctx[1024];
		BuildContext(ctx, sizeof(ctx), bombPlant, client);
		char loc[64];
		GetPlayerLocation(client, loc, sizeof(loc));
		if (loc[0])
		{
			char tmp[640];
			Format(tmp, sizeof(tmp), locSuffix, ctx, loc);
			strcopy(ctx, sizeof(ctx), tmp);
		}
		AskBotChat(ctx, client, "bomb_planted");
	}
}

public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
	g_BombPlanted = 0;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat())
	{
		// Bomb events: 50% chance
		if (GetRandomInt(1, 100) > 50) return;
		
		char bombDefuse[64], locSuffix[64];
		GetStr("events", "bomb_defuse", bombDefuse, sizeof(bombDefuse), "defused the bomb!");
		GetStr("events", "location_suffix", locSuffix, sizeof(locSuffix), "%s at %s.");
		char ctx[512];
		BuildContext(ctx, sizeof(ctx), bombDefuse, client);
		char loc[64];
		GetPlayerLocation(client, loc, sizeof(loc));
		if (loc[0])
		{
			char tmp[640];
			Format(tmp, sizeof(tmp), locSuffix, ctx, loc);
			strcopy(ctx, sizeof(ctx), tmp);
		}
		AskBotChat(ctx, client, "bomb_defused");
	}
}

void GetGameFunfactText(const char[] token, char[] buffer, int maxlen, int player, int data1, int data2)
{
	buffer[0] = '\0';

	char cleanToken[128];
	strcopy(cleanToken, sizeof(cleanToken), token);
	if (cleanToken[0] == '#')
	{
		int i = 0;
		while (cleanToken[i+1] != '\0')
		{
			cleanToken[i] = cleanToken[i+1];
			i++;
		}
		cleanToken[i] = '\0';
	}

	char rawText[512];

	// Try language KV first (PT-BR override)
	GetStr("funfacts", cleanToken, rawText, sizeof(rawText), "");

	// Fallback to game's built-in localization (English)
	if (rawText[0] == '\0' && g_GameKV != null)
	{
		g_GameKV.Rewind();
		if (g_GameKV.JumpToKey("Tokens"))
		{
			g_GameKV.GetString(cleanToken, rawText, sizeof(rawText));
			g_GameKV.GoBack();
		}
	}

	if (rawText[0] != '\0')
	{
		char someone[64];
		GetStr("misc", "someone", someone, sizeof(someone), "Someone");
		char playerName[64];
		if (player > 0 && IsClientInGame(player))
			GetClientName(player, playerName, sizeof(playerName));
		else
			strcopy(playerName, sizeof(playerName), someone);

		char d1[16], d2[16];
		IntToString(data1, d1, sizeof(d1));
		IntToString(data2, d2, sizeof(d2));

		ReplaceString(rawText, sizeof(rawText), "%s3", d2);
		ReplaceString(rawText, sizeof(rawText), "%s2", d1);
		ReplaceString(rawText, sizeof(rawText), "%s1", playerName);

		strcopy(buffer, maxlen, rawText);
	}
}

public void Event_WinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat() || GetRandomInt(1, 100) > 40) return;
	
	char funfact[128];
	event.GetString("funfact_token", funfact, sizeof(funfact));
	if (funfact[0] == '\0') return;
	
	int player = event.GetInt("funfact_player");
	int data1 = event.GetInt("funfact_data1");
	int data2 = event.GetInt("funfact_data2");
	
	char translatedMsg[512];
	GetGameFunfactText(funfact, translatedMsg, sizeof(translatedMsg), player, data1, data2);
	
	char someoneLower[32];
	GetStr("misc", "someone_lower", someoneLower, sizeof(someoneLower), "someone");
	char playerName[32];
	if (player > 0 && IsClientInGame(player))
		GetClientName(player, playerName, sizeof(playerName));
	else
		strcopy(playerName, sizeof(playerName), someoneLower);
	
	char ctx[768];
	if (translatedMsg[0] != '\0')
		Format(ctx, sizeof(ctx), "@%s: \"%s\"", playerName, translatedMsg);
	else
		Format(ctx, sizeof(ctx), "@%s: %s", playerName, funfact);
	
	int preferred = (player > 0 && IsFakeClient(player)) ? player : -1;
	AskBotChat(ctx, preferred, "default");
}

public void Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat() || GetRandomInt(1, 100) > 15) return;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || IsFakeClient(client) || IsClientSourceTV(client)) return;
	
	char text[128];
	event.GetString("text", text, sizeof(text));
	if (text[0] == '!' || text[0] == '/') return; // Comandos
	
	char mainName[32];
	GetClientName(client, mainName, sizeof(mainName));
	
	char playerChatFmt[128];
	GetStr("events", "player_chat", playerChatFmt, sizeof(playerChatFmt), "@%s said: \"%s\"");
	char ctx[1024];
	Format(ctx, sizeof(ctx), playerChatFmt, mainName, text);
	AskBotChat(ctx, -1, "default");
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat() || GetRandomInt(1, 100) > 25) return;
	
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	// SÃ³ friendly fire: mesmo time
	if (attacker < 1 || victim < 1) return;
	if (GetClientTeam(attacker) != GetClientTeam(victim)) return;
	if (attacker == victim) return;
	
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));
	
	// Prioriza bot que sofreu FF
	int preferred;
	char ffTake[64], ffGive[64];
	GetStr("events", "ff_take", ffTake, sizeof(ffTake), "took friendly fire from");
	GetStr("events", "ff_give", ffGive, sizeof(ffGive), "gave friendly fire to");
	char ctx[1024];
	if (IsFakeClient(victim))
	{
		preferred = victim;
		BuildContext(ctx, sizeof(ctx), ffTake, victim, attacker, weapon);
	}
	else if (IsFakeClient(attacker))
	{
		preferred = attacker;
		BuildContext(ctx, sizeof(ctx), ffGive, attacker, victim, weapon);
	}
	else
		return;
	
	AskBotChat(ctx, preferred, "default", weapon);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat()) return;

	int killer = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int headshot = event.GetInt("headshot");
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));

	if (headshot)
		Format(weapon, sizeof(weapon), "%s HS", weapon);

	if (killer < 1 || (!IsFakeClient(killer) && !IsFakeClient(victim)))
		return;

	// Peso varia conforme o envolvimento de player real
	int chance;
	if (IsFakeClient(killer) && !IsFakeClient(victim))
		chance = 70; // Bot matou player: MUITO interessante
	else if (!IsFakeClient(killer) && IsFakeClient(victim))
		chance = 60; // Player matou bot: interessante
	else
		chance = 30; // Bot matou bot: menos interessante
	
	if (GetRandomInt(1, 100) > chance) return;

	int dominated = event.GetInt("dominated");
	int revenge = event.GetInt("revenge");

	char evRevenge[64], evDomination[64], evKill[64], evDeath[64], locSuffix[64];
	GetStr("events", "revenge", evRevenge, sizeof(evRevenge), "took revenge on");
	GetStr("events", "domination", evDomination, sizeof(evDomination), "dominated");
	GetStr("events", "kill", evKill, sizeof(evKill), "eliminated");
	GetStr("events", "death", evDeath, sizeof(evDeath), "was eliminated by");
	GetStr("events", "location_suffix", locSuffix, sizeof(locSuffix), "%s no %s.");
	char ctx[1024];
	if (revenge)
		BuildContext(ctx, sizeof(ctx), evRevenge, killer, victim, weapon);
	else if (dominated)
		BuildContext(ctx, sizeof(ctx), evDomination, killer, victim, weapon);
	else if (IsFakeClient(killer) && !IsFakeClient(victim))
		BuildContext(ctx, sizeof(ctx), evKill, killer, victim, weapon);
	else if (IsFakeClient(victim) && !IsFakeClient(killer))
		BuildContext(ctx, sizeof(ctx), evDeath, victim, killer, weapon);
	else if (IsFakeClient(killer) && IsFakeClient(victim))
		BuildContext(ctx, sizeof(ctx), evKill, killer, victim, weapon);
	else
		return;

	char location[64];
	GetPlayerLocation(killer, location, sizeof(location));
	if (location[0] != '\0')
	{
		char withLoc[640];
		Format(withLoc, sizeof(withLoc), locSuffix, ctx, location);
		strcopy(ctx, sizeof(ctx), withLoc);
	}

	AskBotChat(ctx, IsFakeClient(killer) ? killer : victim, IsFakeClient(killer) ? "kill" : "death", weapon);
}

// ============================================================================
// AI INTEGRATION
// ============================================================================
bool CanBotChat()
{
	if (!g_CvarEnabled.BoolValue) return false;
	float delay = g_CvarCooldown.FloatValue;
	if (GetGameTime() - g_LastBotChat < delay) return false;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
			return true;
	return false;
}

void AskBotChat(const char[] context, int preferredClient = -1, const char[] eventType = "default", const char[] weapon = "")
{
    if (!g_CvarEnabled.BoolValue) return;

    int botClient;
    
    // Se tem preferredClient e e um bot valido, usa ele
    if (preferredClient >= 1 && preferredClient <= MaxClients &&
        IsClientInGame(preferredClient) && IsFakeClient(preferredClient))
    {
        botClient = preferredClient;
    }
    else
    {
        int botClients[MAXPLAYERS + 1];
        int botCount = 0;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
                botClients[botCount++] = i;
        }
        if (botCount == 0) return;
        botClient = botClients[GetRandomInt(0, botCount - 1)];
    }
    char botName[32];
    GetClientName(botClient, botName, sizeof(botName));
    
    // Personalidade do bot
    char personality[256], catchphrase[64], style[256], behavior[256];
    GetBotPersonality(botName, personality, sizeof(personality), catchphrase, sizeof(catchphrase), style, sizeof(style), behavior, sizeof(behavior));

    char teamTR[32], teamCT[32], teamUnknown[32];
    GetStr("teams", "tr", teamTR, sizeof(teamTR), "Team TR");
    GetStr("teams", "ct", teamCT, sizeof(teamCT), "Team CT");
    GetStr("teams", "unknown", teamUnknown, sizeof(teamUnknown), "Team ?");
    char botTeamName[32];
    int team = GetClientTeam(botClient);
    if (team == CS_TEAM_T)
        strcopy(botTeamName, sizeof(botTeamName), teamTR);
    else if (team == CS_TEAM_CT)
        strcopy(botTeamName, sizeof(botTeamName), teamCT);
    else
        strcopy(botTeamName, sizeof(botTeamName), teamUnknown);

    // Prompt natural: quem é + contexto
    char localContext[768];
    strcopy(localContext, sizeof(localContext), context);
    
    // Time do bot: ganhando ou perdendo?
    int tScore = CS_GetTeamScore(CS_TEAM_T);
    int ctScore = CS_GetTeamScore(CS_TEAM_CT);
    char winning[64], losing[64];
    GetStr("gamestate", "winning", winning, sizeof(winning), " You are winning.");
    GetStr("gamestate", "losing", losing, sizeof(losing), " You are losing.");
    char scoreStatus[64];
    if ((team == CS_TEAM_T && tScore > ctScore) || (team == CS_TEAM_CT && ctScore > tScore))
        strcopy(scoreStatus, sizeof(scoreStatus), winning);
    else if ((team == CS_TEAM_T && tScore < ctScore) || (team == CS_TEAM_CT && ctScore < tScore))
        strcopy(scoreStatus, sizeof(scoreStatus), losing);
    else
        strcopy(scoreStatus, sizeof(scoreStatus), "");
    
    // Mood baseado no evento
    char mood[128];
    
    // Extrai @alvo do contexto (pula o nome do proprio bot)
    char targetMention[64];
    targetMention[0] = '\0';
    
    int searchPos = 0;
    while (searchPos < strlen(localContext))
    {
        int atPos = StrContains(localContext[searchPos], "@");
        if (atPos == -1) break;
        
        atPos += searchPos;
        int endPos = atPos + 1;
        while (endPos < strlen(localContext) && localContext[endPos] != ' ' && localContext[endPos] != '.' && localContext[endPos] != ',')
            endPos++;
        
        if (endPos > atPos + 1)
        {
            char mention[64];
            strcopy(mention, sizeof(mention), localContext[atPos]);
            // Trunca
            int sp = StrContains(mention, " ");
            if (sp != -1) mention[sp] = '\0';
            int dt = StrContains(mention, ".");
            if (dt != -1) mention[dt] = '\0';
            
            // Se nao e o proprio bot, usa
            if (StrContains(mention, botName) == -1)
            {
                strcopy(targetMention, sizeof(targetMention), mention);
                break;
            }
        }
        
        searchPos = endPos;
    }
    
    char moodFFApology[64], moodFFComplain[64], moodTaunt[64], moodTauntEnemy[64];
    char moodInsult[64], moodInsultGeneric[64], moodCelebrate[64], moodComplainDefeat[64], moodReact[64];
    GetStr("moods", "ff_apology", moodFFApology, sizeof(moodFFApology), "Sorry, my bad");
    GetStr("moods", "ff_complain", moodFFComplain, sizeof(moodFFComplain), "Complain about teammate");
    GetStr("moods", "taunt", moodTaunt, sizeof(moodTaunt), "Taunt %s");
    GetStr("moods", "taunt_enemy", moodTauntEnemy, sizeof(moodTauntEnemy), "Taunt the enemy");
    GetStr("moods", "insult", moodInsult, sizeof(moodInsult), "Pretend to insult %s");
    GetStr("moods", "insult_generic", moodInsultGeneric, sizeof(moodInsultGeneric), "Pretend to insult");
    GetStr("moods", "celebrate", moodCelebrate, sizeof(moodCelebrate), "Celebrate");
    GetStr("moods", "complain_defeat", moodComplainDefeat, sizeof(moodComplainDefeat), "Complain about defeat");
    GetStr("moods", "react", moodReact, sizeof(moodReact), "React");

    if (StrContains(localContext, "friendly fire") != -1)
    {
        if (StrContains(localContext, "deu friendly fire") != -1)
            strcopy(mood, sizeof(mood), moodFFApology);
        else
            strcopy(mood, sizeof(mood), moodFFComplain);
    }
    else if (StrContains(localContext, "eliminated") != -1)
    {
        if (targetMention[0])
            Format(mood, sizeof(mood), moodTaunt, targetMention);
        else
            strcopy(mood, sizeof(mood), moodTauntEnemy);
    }
    else if (StrContains(localContext, "eliminado") != -1)
    {
        if (targetMention[0])
            Format(mood, sizeof(mood), moodInsult, targetMention);
        else
            strcopy(mood, sizeof(mood), moodInsultGeneric);
    }
    else if (StrContains(localContext, "won") != -1)
    {
        if ((StrContains(localContext, "TR won") != -1 && StrContains(botTeamName, "TR") != -1) ||
            (StrContains(localContext, "CT won") != -1 && StrContains(botTeamName, "CT") != -1))
            strcopy(mood, sizeof(mood), moodCelebrate);
        else
            strcopy(mood, sizeof(mood), moodComplainDefeat);
    }
    else
        strcopy(mood, sizeof(mood), moodReact);
    
    // Remove estado do jogo do user prompt (ja esta no system prompt)
    char eventOnly[768];
    strcopy(eventOnly, sizeof(eventOnly), localContext);
    int mapaPos = StrContains(eventOnly, ". Mapa");
    if (mapaPos != -1)
        eventOnly[mapaPos] = '\0';
    
    // System: tudo (estado + evento + instrucoes)
    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));
    
    char kwCelebrate[32], kwComplain[32], gsJustWon[64], gsJustLost[64];
    GetStr("mood_keywords", "celebrate", kwCelebrate, sizeof(kwCelebrate), "Celebrate");
    GetStr("mood_keywords", "complain", kwComplain, sizeof(kwComplain), "Complain");
    GetStr("gamestate", "just_won", gsJustWon, sizeof(gsJustWon), "Just won the round");
    GetStr("gamestate", "just_lost", gsJustLost, sizeof(gsJustLost), "Just lost the round");
    char gameState[64];
    if (StrContains(mood, kwCelebrate) != -1)
        strcopy(gameState, sizeof(gameState), gsJustWon);
    else if (StrContains(mood, kwComplain) != -1)
        strcopy(gameState, sizeof(gameState), gsJustLost);
    else if (scoreStatus[0] != '\0')
        strcopy(gameState, sizeof(gameState), scoreStatus[1]);
    else
        gameState[0] = '\0';
    
    // Evento (sem estado duplicado)
    char eventStr[768];
    if (eventOnly[0])
        Format(eventStr, sizeof(eventStr), "%s%s", eventOnly, scoreStatus);
    else
        Format(eventStr, sizeof(eventStr), "%s%s", localContext, scoreStatus);
    
    // Determina tipo de evento para o template (fallback se não passado)
    char type[32];
    strcopy(type, sizeof(type), eventType);
    if (StrEqual(type, "default"))
    {
        if (StrContains(localContext, "eliminated") != -1 || StrContains(localContext, "eliminou") != -1)
            strcopy(type, sizeof(type), "kill");
        else if (StrContains(localContext, "was eliminated") != -1 || StrContains(localContext, "foi eliminado") != -1)
            strcopy(type, sizeof(type), "death");
        else if (StrContains(localContext, "won") != -1 || StrContains(localContext, "venceu") != -1)
            strcopy(type, sizeof(type), "round_end");
        else if (StrContains(localContext, "started") != -1 || StrContains(localContext, "iniciou") != -1)
            strcopy(type, sizeof(type), "round_start");
    }
    
    char sysPrompt[2048];
    char fullPrompt[1024];
    

    if (GetPromptTemplate(type, "system", sysPrompt, sizeof(sysPrompt),
        botName, botTeamName, targetMention, gameState, eventStr, mood,
        g_CurrentRound, tScore, ctScore))
    {
        ReplaceString(sysPrompt, sizeof(sysPrompt), "[base_system]", sysPrompt);
        // Injeta personalidade nos placeholders
        ReplaceString(sysPrompt, sizeof(sysPrompt), "[personality]", personality);
        ReplaceString(sysPrompt, sizeof(sysPrompt), "[catchphrase]", catchphrase);
        ReplaceString(sysPrompt, sizeof(sysPrompt), "[style]", style);
        ReplaceString(sysPrompt, sizeof(sysPrompt), "[behavior]", behavior);
    }
    else
    {
        char fallbackSys[256];
        GetStr("misc", "fallback_system", fallbackSys, sizeof(fallbackSys),
            "Your name is %s (%s). %s %s. ONE short sentence.");
        Format(sysPrompt, sizeof(sysPrompt), fallbackSys,
            botName, botTeamName, gameState, eventStr);
    }
    
    if (!GetPromptTemplate(type, "user", fullPrompt, sizeof(fullPrompt),
        botName, botTeamName, targetMention, gameState, eventStr, mood,
        g_CurrentRound, tScore, ctScore))
    {
        char fallbackUser[128], fallbackUserSimple[64];
        GetStr("misc", "fallback_user", fallbackUser, sizeof(fallbackUser), "Speak as %s about %s.");
        GetStr("misc", "fallback_user_simple", fallbackUserSimple, sizeof(fallbackUserSimple), "Speak as %s.");
        if (targetMention[0])
            Format(fullPrompt, sizeof(fullPrompt), fallbackUser, botName, targetMention);
        else
            Format(fullPrompt, sizeof(fullPrompt), fallbackUserSimple, botName);
    }
    
    // Injeta instrução de idioma baseada no idioma do servidor ou da cvar (SEMPRE no final do sysPrompt)
    char langCode[16], langName[32];
    g_LangCvar.GetString(langCode, sizeof(langCode));
    if (StrEqual(langCode, "default")) {
        int langId = GetServerLanguage();
        GetLanguageInfo(langId, langCode, sizeof(langCode));
    }

    if (langCode[0] != '\0' && !StrEqual(langCode, "en", false) && !StrEqual(langCode, "default", false))
    {
        if (StrContains(langCode, "pt", false) != -1) strcopy(langName, sizeof(langName), "Portuguese");
        else if (StrContains(langCode, "ru", false) != -1) strcopy(langName, sizeof(langName), "Russian");
        else if (StrContains(langCode, "es", false) != -1) strcopy(langName, sizeof(langName), "Spanish");
        else if (StrContains(langCode, "zh", false) != -1 || StrContains(langCode, "chi", false) != -1) strcopy(langName, sizeof(langName), "Chinese");
        else strcopy(langName, sizeof(langName), langCode);

        char langRule[64];
        Format(langRule, sizeof(langRule), " Answer in %s.", langName);
        StrCat(sysPrompt, sizeof(sysPrompt), langRule);
    }
    
    char weaponBuf[32];
    if (weapon[0])
    {
        char friendly[32];
        FriendlyWeaponName(weapon, friendly, sizeof(friendly));
        int hsPos = StrContains(friendly, " HS");
        if (hsPos != -1) friendly[hsPos] = '\0';
        strcopy(weaponBuf, sizeof(weaponBuf), friendly);
    }
    else
    {
        // Tenta extrair do contexto se não passado (compatibilidade)
        GetStr("misc", "unknown_weapon", weaponBuf, sizeof(weaponBuf), "unknown");
        char weaponShotPrefix[32];
        GetStr("misc", "weapon_shot", weaponShotPrefix, sizeof(weaponShotPrefix), " with %s");
        char shotPrefixFind[32];
        strcopy(shotPrefixFind, sizeof(shotPrefixFind), weaponShotPrefix);
        int dotPos = StrContains(shotPrefixFind, "%s");
        if (dotPos != -1) shotPrefixFind[dotPos] = '\0';
        int wStart = StrContains(localContext, shotPrefixFind);
        if (wStart != -1)
        {
            wStart += strlen(shotPrefixFind);
            int wEnd = wStart;
            while (wEnd < strlen(localContext) && localContext[wEnd] != ' ' && localContext[wEnd] != '.' && localContext[wEnd] != ',')
                wEnd++;
            if (wEnd > wStart)
            {
                int len = wEnd - wStart;
                if (len > 31) len = 31;
                strcopy(weaponBuf, len + 1, localContext[wStart]);
            }
        }
    }
    
    // Replace user prompt placeholders (system prompt already done)
    ReplaceString(fullPrompt, sizeof(fullPrompt), "[weapon]", weaponBuf);
    ReplaceString(fullPrompt, sizeof(fullPrompt), "[behavior]", behavior);
    // Extra safety: ensure all placeholders are replaced
    ReplaceString(fullPrompt, sizeof(fullPrompt), "[mood]", mood);
    ReplaceString(fullPrompt, sizeof(fullPrompt), "[state]", gameState);
    char roundStr[16];
    IntToString(g_CurrentRound, roundStr, sizeof(roundStr));
    ReplaceString(fullPrompt, sizeof(fullPrompt), "[round]", roundStr);
    char scoreFmt[32];
	GetStr("misc", "score_format", scoreFmt, sizeof(scoreFmt), "%d-%d");
    char scoreStr[32];
    Format(scoreStr, sizeof(scoreStr), scoreFmt, tScore, ctScore);
    ReplaceString(fullPrompt, sizeof(fullPrompt), "[score]", scoreStr);
    ReplaceString(fullPrompt, sizeof(fullPrompt), "[map]", mapName);

    char timeBuf[32];
    FormatTime(timeBuf, sizeof(timeBuf), "%H:%M:%S");

    NVD_AskAI(fullPrompt, sysPrompt, INVALID_FUNCTION, botClient);
    PrintToServer("[BOT_CHAT] [%s] 🤖 Asked bot %s (%s): %s", timeBuf, botName, botTeamName, context);
    PrintToServer("[BOT_CHAT] [%s] 📝 Prompt >> system: \"%s\" | user: \"%s\"", timeBuf, sysPrompt, fullPrompt);
    
    // Store for structured log (read by PollBotResponses when response arrives)
    strcopy(g_LastEventType[botClient], sizeof(g_LastEventType[]), type);
    strcopy(g_LastTarget[botClient], sizeof(g_LastTarget[]), targetMention);
    strcopy(g_LastMood[botClient], sizeof(g_LastMood[]), mood);
    strcopy(g_LastSysPrompt[botClient], sizeof(g_LastSysPrompt[]), sysPrompt);
    strcopy(g_LastUserPrompt[botClient], sizeof(g_LastUserPrompt[]), fullPrompt);
    g_LastAskTime[botClient] = GetGameTime();
}

// No-op callback — responses come through NVD_PollResponse polling
public void OnPollingDummy(const char[] response, any data)
{
}

// ── Polling timer ─────────────────────────────────────────────────────
public Action Timer_PollResponses(Handle timer)
{
    PollBotResponses();
    return Plugin_Continue;
}

void PollBotResponses()
{
    char reply[2048];
    any botClient;
    char ts[32];
    FormatTime(ts, sizeof(ts), "%H:%M:%S");

    while (NVD_PollResponse(reply, sizeof(reply), botClient))
    {
        PrintToServer("[BOT_CHAT] [%s] 📥 Polled response for bot %d: \"%s\"", ts, botClient, reply);
        
        // Log the raw response for analysis
        LogPolledResponse(botClient, reply);

        // Check for explicit error responses
        if (StrContains(reply, "ERROR_") != -1)
        {
            LogError("[BOT_CHAT] ❌ Ollama error received: %s", reply);
            continue;
        }

        if (reply[0] == '\0') continue;
        if (!g_CvarEnabled.BoolValue) continue;

        char botName[32];

        // If the original bot is invalid (morto ainda pode falar), find another
        if (botClient == 0 || !IsClientInGame(botClient) || !IsFakeClient(botClient))
        {
            int activeBots[MAXPLAYERS + 1];
            int activeBotCount = 0;
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
                {
                    activeBots[activeBotCount++] = i;
                }
            }

            if (activeBotCount == 0)
            {
                PrintToServer("[BOT_CHAT] ⏭ Dropped (no active bots): \"%s\"", reply);
                LogBotInteraction("DROP", "?", "?", "?", "?", "sem_bots", reply);
                continue;
            }

            char oldName[32];
            if (botClient > 0 && IsClientInGame(botClient))
                GetClientName(botClient, oldName, sizeof(oldName));
            else
                strcopy(oldName, sizeof(oldName), "unknown");

            botClient = activeBots[GetRandomInt(0, activeBotCount - 1)];
            char newName[32];
            GetClientName(botClient, newName, sizeof(newName));
            PrintToServer("[BOT_CHAT] 🔄 Resposta de %s redirecionada para %s (original invalido)", oldName, newName);
        }

        GetClientName(botClient, botName, sizeof(botName));

        char cleanMsg[320];
        strcopy(cleanMsg, sizeof(cleanMsg), reply);
        ReplaceString(cleanMsg, sizeof(cleanMsg), "\"", "");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "[", "");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "]", "");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "\\n", " ");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "\\r", " ");
        TrimString(cleanMsg);

        // Remove bot name prefix if model repeated it (e.g. "TACO: mensagem" or "TACO mensagem")
        char namePattern[64];
        Format(namePattern, sizeof(namePattern), "%s", botName);
        if (StrContains(cleanMsg, namePattern) == 0)
        {
            int nameLen = strlen(namePattern);
            int rest = strlen(cleanMsg) - nameLen;
            if (rest > 0)
            {
                char tmp[256];
                int start = nameLen;
                // Skip colon and space after name
                while (start < strlen(cleanMsg) && (cleanMsg[start] == ':' || cleanMsg[start] == ' '))
                    start++;
                strcopy(tmp, sizeof(tmp), cleanMsg[start]);
                strcopy(cleanMsg, sizeof(cleanMsg), tmp);
                TrimString(cleanMsg);
            }
        }

        // Remove leftover "chat:" prefix
        if (StrContains(cleanMsg, "chat:") == 0 || StrContains(cleanMsg, "chat :") == 0)
        {
            int pos = StrContains(cleanMsg, ":");
            if (pos >= 0)
            {
                char tmp[256];
                strcopy(tmp, sizeof(tmp), cleanMsg[pos + 1]);
                strcopy(cleanMsg, sizeof(cleanMsg), tmp);
                TrimString(cleanMsg);
            }
        }

        if (cleanMsg[0] == '\0')
        {
            PrintToServer("[BOT_CHAT] ⏭ Dropped (empty after clean): \"%s\"", reply);
            LogBotInteraction("DROP", botName, "?", "?", "?", "vazio", reply);
            continue;
        }

        // Trunca mensagens longas (limite do comando say)
        if (strlen(cleanMsg) > 100)
        {
            cleanMsg[100] = '\0';
            // Volta ate encontrar pontuacao
            int truncPos = 100;
            while (truncPos > 80 && cleanMsg[truncPos] != '.' && cleanMsg[truncPos] != '!' && cleanMsg[truncPos] != '?' && cleanMsg[truncPos] != ',')
                truncPos--;
            if (truncPos > 80)
                cleanMsg[truncPos + 1] = '\0';
            else
                cleanMsg[100] = '\0';
        }

        PrintToServer("[BOT_CHAT] [%s] ✅ Sent: [BOT %s] %s", ts, botName, cleanMsg);
        
        // Structured log: response sent
        LogBotInteraction("SENT", botName,
            g_LastEventType[botClient], g_LastTarget[botClient], g_LastMood[botClient],
            g_LastSysPrompt[botClient], g_LastUserPrompt[botClient], cleanMsg);

        // Bot-to-bot reply: 15% chance de outro bot responder
        if (GetRandomInt(1, 100) <= 15)
        {
            int otherBots[MAXPLAYERS + 1];
            int otherCount = 0;
            for (int i = 1; i <= MaxClients; i++)
            {
                if (i != botClient && IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
                    otherBots[otherCount++] = i;
            }
            if (otherCount > 0)
            {
                int replyBot = otherBots[GetRandomInt(0, otherCount - 1)];
                char replyBotName[32];
                GetClientName(replyBot, replyBotName, sizeof(replyBotName));
                char replySaidFmt[64];
                GetStr("misc", "bot_reply_said", replySaidFmt, sizeof(replySaidFmt), "%s said: \"%s\"");
                char replyCtx[640];
                Format(replyCtx, sizeof(replyCtx), replySaidFmt, botName, cleanMsg);
                // Forca rate limit manual
                g_LastBotChat = 0.0;
                AskBotChat(replyCtx, replyBot);
            }
        }

        // Bot speaks via say command (RP: actual bot chat, not server message)
        FakeClientCommand(botClient, "say %s", cleanMsg);
        g_LastBotChat = GetGameTime();
    }
}

// ============================================================================
// PERSONALITY SYSTEM
// ============================================================================

void LoadPersonalities()
{
    if (g_PersonalityKV != null)
        delete g_PersonalityKV;
    
    g_PersonalityKV = new KeyValues("BotPersonalities");
    
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/nvd_bot_personalities.txt");
    
    if (!FileExists(path))
    {
        LogError("[BOT_CHAT] Personalities file not found: %s", path);
        delete g_PersonalityKV;
        g_PersonalityKV = null;
        return;
    }
    
    if (!g_PersonalityKV.ImportFromFile(path))
    {
        LogError("[BOT_CHAT] Failed to load personalities from: %s", path);
        delete g_PersonalityKV;
        g_PersonalityKV = null;
        return;
    }
    
    PrintToServer("[BOT_CHAT] +- Personalities loaded from %s", path);
}

void GetBotPersonality(const char[] botName, char[] personality, int personalityLen,
    char[] catchphrase, int catchphraseLen, char[] style, int styleLen,
    char[] behavior, int behaviorLen)
{
    if (g_PersonalityKV == null)
    {
        personality[0] = '\0';
        catchphrase[0] = '\0';
        style[0] = '\0';
        behavior[0] = '\0';
        return;
    }
    
    g_PersonalityKV.Rewind();
    if (!g_PersonalityKV.JumpToKey(botName))
    {
        personality[0] = '\0';
        catchphrase[0] = '\0';
        style[0] = '\0';
        behavior[0] = '\0';
        return;
    }
    
    g_PersonalityKV.GetString("personality", personality, personalityLen);
    g_PersonalityKV.GetString("catchphrase", catchphrase, catchphraseLen);
    g_PersonalityKV.GetString("style", style, styleLen);
    g_PersonalityKV.GetString("behavior", behavior, behaviorLen);
}

// ============================================================================
// STRUCTURED LOGGING
// ============================================================================

void LogBotInteraction(const char[] action, const char[] bot,
    const char[] eventType, const char[] target, const char[] mood,
    const char[] data1 = "", const char[] data2 = "", const char[] data3 = "")
{
    if (!g_CvarLogging.BoolValue) return;
    
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "logs/nvd_bot_chat.log");
    
    char ts[64];
    FormatTime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ");
    
    // JSONL: build a single json string per line
    char line[4096];
    int pos = 0;
    
    // Always: timestamp, action, bot
    pos += Format(line[pos], sizeof(line) - pos,
        "{\"ts\":\"%s\",\"a\":\"%s\",\"b\":\"%s\"",
        ts, action, bot);
    
    // Event if any
    if (eventType[0] || target[0] || mood[0])
    {
        pos += Format(line[pos], sizeof(line) - pos, ",\"e\":{\"t\":\"%s\"", eventType);
        if (target[0]) pos += Format(line[pos], sizeof(line) - pos,
            ",\"tg\":\"%s\"", target);
        if (mood[0]) pos += Format(line[pos], sizeof(line) - pos,
            ",\"m\":\"%s\"", mood);
        pos += Format(line[pos], sizeof(line) - pos, "}");
    }
    
    // System prompt if available (for RESP and SENT)
    if (data1[0] && (StrEqual(action, "RESP") || StrEqual(action, "SENT")))
    {
        pos += Format(line[pos], sizeof(line) - pos, ",\"sys\":\"");
        pos = JsonEsc(line, sizeof(line), pos, data1);
        pos += Format(line[pos], sizeof(line) - pos, "\"");
    }
    
    // User prompt if available
    if (data2[0] && (StrEqual(action, "RESP") || StrEqual(action, "SENT")))
    {
        pos += Format(line[pos], sizeof(line) - pos, ",\"usr\":\"");
        pos = JsonEsc(line, sizeof(line), pos, data2);
        pos += Format(line[pos], sizeof(line) - pos, "\"");
    }
    
    // Response
    if (data3[0])
    {
        pos += Format(line[pos], sizeof(line) - pos, ",\"r\":\"");
        pos = JsonEsc(line, sizeof(line), pos, data3);
        pos += Format(line[pos], sizeof(line) - pos, "\"");
    }
    
    // Close
    pos += Format(line[pos], sizeof(line) - pos, "}\n");
    
    Handle file = OpenFile(path, "a");
    if (file != null)
    {
        WriteFileString(file, line, false);
        delete file;
    }
}

// Escape string for JSON value
int JsonEsc(char[] buf, int max, int pos, const char[] inp)
{
    int len = strlen(inp);
    for (int i = 0; i < len && pos < max - 6; i++)
    {
        switch (inp[i])
        {
            case '\"': { buf[pos++] = '\\'; buf[pos++] = '\"'; break; }
            case '\\': { buf[pos++] = '\\'; buf[pos++] = '\\'; break; }
            case '\n': { buf[pos++] = '\\'; buf[pos++] = 'n'; break; }
            case '\r': { buf[pos++] = '\\'; buf[pos++] = 'r'; break; }
            case '\t': { buf[pos++] = '\\'; buf[pos++] = 't'; break; }
            default: { buf[pos++] = inp[i]; }
        }
    }
    buf[pos] = '\0';
    return pos;
}

void LogPolledResponse(int botClient, const char[] reply)
{
    if (!g_CvarLogging.BoolValue) return;
    
    char botName[32];
    if (botClient > 0 && IsClientInGame(botClient))
        GetClientName(botClient, botName, sizeof(botName));
    else
        strcopy(botName, sizeof(botName), "?");
    
    // Log raw response with stored prompt info
    LogBotInteraction("RESP", botName,
        g_LastEventType[botClient], g_LastTarget[botClient], g_LastMood[botClient],
        g_LastSysPrompt[botClient], g_LastUserPrompt[botClient], reply);
}

// ============================================================================
// PROMPT TEMPLATE SYSTEM
// ============================================================================
void LoadPromptTemplates()
{
    if (g_PromptKV != null)
        delete g_PromptKV;
    
    g_PromptKV = new KeyValues("BotChatPrompts");
    
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/nvd_bot_chat_prompts.txt");
    
    if (!FileExists(path))
    {
        LogError("[BOT_CHAT] Prompt file not found: %s", path);
        delete g_PromptKV;
        g_PromptKV = null;
        return;
    }
    
    if (!g_PromptKV.ImportFromFile(path))
    {
        LogError("[BOT_CHAT] Failed to load prompts from: %s", path);
        delete g_PromptKV;
        g_PromptKV = null;
        return;
    }
    
    PrintToServer("[BOT_CHAT] +- Prompt templates loaded from %s", path);
    g_PromptKV.Rewind();
}

void LoadMetaFromStrings()
{
    g_MetaCount = 0;
    char keys[2][16] = {"rules", "critical"};
    for (int i = 0; i < 2; i++)
    {
        strcopy(g_MetaKeys[g_MetaCount], sizeof(g_MetaKeys[]), keys[i]);
        GetStr("behavior", keys[i], g_MetaValues[g_MetaCount], sizeof(g_MetaValues[]), "");
        if (g_MetaValues[g_MetaCount][0] != '\0')
            g_MetaCount++;
    }
    if (g_MetaCount > 0)
        PrintToServer("[BOT_CHAT] +- Loaded %d _meta snippets from language strings", g_MetaCount);
}

public Action Command_ReloadPrompts(int client, int args)
{
    LoadPromptTemplates();
    LoadStrings();
    LoadMetaFromStrings();
    ReplyToCommand(client, "[BOT_CHAT] +- Prompts and strings reloaded");
    return Plugin_Handled;
}

bool GetPromptTemplate(const char[] eventType, const char[] promptType,
    char[] buffer, int maxlen,
    const char[] bot = "", const char[] team = "",
    const char[] target = "", const char[] state = "",
    const char[] event = "", const char[] mood = "",
    int round = 0, int tScore = 0, int ctScore = 0)
{
    char template[2048];
    char langKey[64];
    Format(langKey, sizeof(langKey), "%s_%s", eventType, promptType);
    GetStr("prompts", langKey, template, sizeof(template), "");
    
    if (template[0] == '\0')
    {
        if (g_PromptKV == null) return false;
        g_PromptKV.Rewind();
        if (!g_PromptKV.JumpToKey(eventType))
        {
            g_PromptKV.Rewind();
            if (!g_PromptKV.JumpToKey("default"))
                return false;
        }
        g_PromptKV.GetString(promptType, template, sizeof(template));
        if (template[0] == '\0')
            return false;
    }
    

    ReplaceString(template, sizeof(template), "[bot]", bot);
    ReplaceString(template, sizeof(template), "[team]", team);
    ReplaceString(template, sizeof(template), "[target]", target);
    ReplaceString(template, sizeof(template), "[state]", state);
    ReplaceString(template, sizeof(template), "[event]", event);
    ReplaceString(template, sizeof(template), "[mood]", mood);
    
    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));
    ReplaceString(template, sizeof(template), "[map]", mapName);
    
    char roundStr[16];
    IntToString(round, roundStr, sizeof(roundStr));
    ReplaceString(template, sizeof(template), "[round]", roundStr);
    
    char scoreFmtPT[32];
    GetStr("misc", "score_format", scoreFmtPT, sizeof(scoreFmtPT), "%d-%d");
    char scoreStr[32];
    Format(scoreStr, sizeof(scoreStr), scoreFmtPT, tScore, ctScore);
    ReplaceString(template, sizeof(template), "[score]", scoreStr);
    
    // Replace shared _meta snippets: [rules], [critical], [examples], etc.
    if (g_MetaCount > 0)
    {
        for (int mi = 0; mi < g_MetaCount; mi++)
        {
            char placeholder[64];
            Format(placeholder, sizeof(placeholder), "[%s]", g_MetaKeys[mi]);
            if (StrContains(template, placeholder) != -1)
                ReplaceString(template, sizeof(template), placeholder, g_MetaValues[mi]);
        }
    }
    
    // Second pass: meta values may contain [bot] etc.
    ReplaceString(template, sizeof(template), "[bot]", bot);
    ReplaceString(template, sizeof(template), "[team]", team);
    ReplaceString(template, sizeof(template), "[target]", target);
    
    strcopy(buffer, maxlen, template);
    return true;
}
