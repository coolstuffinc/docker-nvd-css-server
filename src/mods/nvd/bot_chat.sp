#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <ripext>
#include <nvd/core>
#include <nvd/strings>
#include <nvd/utils>

#pragma semicolon 1
#pragma newdecls required

#define CHAT_COOLDOWN 12.0
#define CONTEXT_PACK_VERSION 1

ConVar g_CvarEnabled;
ConVar g_CvarCooldown;
ConVar g_CvarTimeout;
KeyValues g_PromptKV = null;
KeyValues g_PersonalityKV = null;
KeyValues g_GameKV = null;

enum struct BotCacheEntry {
    int enemies;
    int allies;
    char response[320];
    bool valid;
}
enum struct BotCache {
    BotCacheEntry entries[30];
    int count;
}
BotCache g_BotCache[MAXPLAYERS + 1];
int g_LastEnemies[MAXPLAYERS + 1];
int g_LastAllies[MAXPLAYERS + 1];

float g_LastBotChat;
Handle g_RoundStartTimer;
int g_CurrentRound;
float g_BombPlanted;

// Timeline history: alternating events (system) + bot messages
#define MAX_HISTORY_ENTRIES 8
#define HISTORY_CONTENT_LEN 256
enum struct HistoryEntry {
    char role[32];
    char content[HISTORY_CONTENT_LEN];
}
HistoryEntry g_History[MAX_HISTORY_ENTRIES];
int g_HistIdx = 0;
int g_HistCount = 0;

// Per-map bot K/D tracking
int g_BotKills[MAXPLAYERS + 1];
int g_BotDeaths[MAXPLAYERS + 1];

// Structured log tracking per bot
char g_LastEventType[MAXPLAYERS + 1][32];
float g_LastAskTime[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "NVD Bot Chat",
	author = "OpenCode",
	description = "AI-powered contextual chat with centralized strings",
	version = "3.1.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("NVD_SubmitChatEvent", Native_SubmitChatEvent);
	CreateNative("NVD_GetCachedResponse", Native_GetCachedResponse);
	CreateNative("NVD_BuildPrompts", Native_BuildPrompts);
	RegPluginLibrary("nvd_bot_chat");
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	// Centralizado via Core
	NVD_RegisterStrings("nvd");
	LoadMetaFromStrings();
}

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_bot_chat", "1", "Enable AI bot chat messages");
	g_CvarCooldown = CreateConVar("nvd_bot_chat_cooldown", "12.0", "Min seconds between bot messages");
	g_CvarTimeout = CreateConVar("nvd_bot_chat_timeout", "120.0", "Max seconds to wait for AI response before giving up");
	
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
	
	// Comando para recarregar templates
	RegAdminCmd("sm_botchat_reload", Command_ReloadPrompts, ADMFLAG_GENERIC);
	RegAdminCmd("sm_botchat_history", Command_BotChatHistory, ADMFLAG_GENERIC);

	// Comando para recarregar templates
}

public Action Timer_DelayedReRegister(Handle timer)
{
	NVD_RegisterStrings("nvd_bot_chat");
	LoadMetaFromStrings();
	return Plugin_Stop;
}

public void OnMapStart()
{
	g_LastBotChat = 0.0;
	g_CurrentRound = 0;
	g_BombPlanted = 0.0;

	for (int i = 1; i <= MaxClients; i++) { g_BotKills[i] = 0; g_BotDeaths[i] = 0; g_BotCache[i].count = 0; g_LastEnemies[i] = 0; g_LastAllies[i] = 0; }
	g_HistIdx = 0; g_HistCount = 0;

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
	delete g_PromptKV;
	delete g_PersonalityKV;
}

void LoadMetaFromStrings()
{
    char val[1024];
    GetStr("behavior", "rules", val, sizeof(val));
    if (val[0]) NVD_SetMeta("rules", val);
    
    GetStr("behavior", "critical", val, sizeof(val));
    if (val[0]) NVD_SetMeta("critical", val);

    PrintToServer("[BOT_CHAT] +- Behavior snippets registered to NVD Core");
}

public Action Command_ReloadPrompts(int client, int args)
{
    LoadPromptTemplates();
    NVD_RegisterStrings("nvd_bot_chat");
    LoadMetaFromStrings();
    ReplyToCommand(client, "[BOT_CHAT] +- Prompts and strings reloaded");
    return Plugin_Handled;
}

public Action Command_BotChatHistory(int client, int args)
{
    ReplyToCommand(client, "[BOT_CHAT] ═══ History (last %d) ═══", g_HistCount);
    if (g_HistCount == 0) { ReplyToCommand(client, "[BOT_CHAT] (empty)"); return Plugin_Handled; }
    int take = g_HistCount > 8 ? 8 : g_HistCount;
    int start = (g_HistIdx - take + MAX_HISTORY_ENTRIES) % MAX_HISTORY_ENTRIES;
    for (int i = 0; i < take; i++) {
        int idx = (start + i) % MAX_HISTORY_ENTRIES;
        if (g_History[idx].content[0] == '\0') continue;
        ReplyToCommand(client, "[BOT_CHAT] %s: %s", g_History[idx].role, g_History[idx].content);
    }
    return Plugin_Handled;
}

stock void GetStr(const char[] section, const char[] key, char[] buffer, int maxlen)
{
    char fullPath[256];
    Format(fullPath, sizeof(fullPath), "nvd.bot_chat.%s.%s", section, key);
    NVD_GetStr(fullPath, buffer, maxlen);
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
    GetStr("prompts", langKey, template, sizeof(template));

    // Fallback to global system if event-specific system is missing
    if (template[0] == '\0' && StrEqual(promptType, "system"))
    {
        GetStr("prompts", "system", template, sizeof(template));
    }
    
    if (template[0] == '\0')
    {
        if (g_PromptKV == null) return false;
        g_PromptKV.Rewind();
        
        // Try event-specific prompt first
        if (g_PromptKV.JumpToKey(eventType))
        {
            g_PromptKV.GetString(promptType, template, sizeof(template));
        }
        
        // Fallback
        if (template[0] == '\0')
        {
            g_PromptKV.Rewind();
            if (StrEqual(promptType, "system"))
            {
                g_PromptKV.GetString("system", template, sizeof(template));
            } else {
                if (g_PromptKV.JumpToKey("default"))
                {
                    g_PromptKV.GetString(promptType, template, sizeof(template));
                }
            }
        }
        if (template[0] == '\0') return false;
    }
    
    ReplaceString(template, sizeof(template), "|bot|", bot);
    ReplaceString(template, sizeof(template), "|team|", team);
    ReplaceString(template, sizeof(template), "|target|", target);
    ReplaceString(template, sizeof(template), "|state|", state);
    ReplaceString(template, sizeof(template), "|event|", event);
    ReplaceString(template, sizeof(template), "|mood|", mood);
    
    char roundStr[16];
    IntToString(round, roundStr, sizeof(roundStr));
    ReplaceString(template, sizeof(template), "|round|", roundStr);
    
    char scoreFmtPT[32];
    GetStr("misc", "score_format", scoreFmtPT, sizeof(scoreFmtPT));
    char scoreStr[32];
    Format(scoreStr, sizeof(scoreStr), scoreFmtPT, tScore, ctScore);
    ReplaceString(template, sizeof(template), "|score|", scoreStr);
    
    strcopy(buffer, maxlen, template);
    return true;
}

// ----------------------------------------------------------------------------
// Lógica de Eventos e Contexto
// ----------------------------------------------------------------------------

void FriendlyWeaponName(const char[] weapon, char[] output, int maxlen)
{
    char base[32];
    strcopy(base, sizeof(base), weapon);
    bool headshot = false;
    int hsPos = StrContains(base, " HS");
    if (hsPos != -1) { base[hsPos] = '\0'; headshot = true; }
    
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
                if (headshot) Format(output, maxlen, "%s HS", output);
                return;
            }
        }
    }
    char fp[256]; Format(fp, sizeof(fp), "nvd.bot_chat.weapons_fallback.%s", base);
    if (NVD_HasStr(fp)) GetStr("weapons_fallback", base, output, maxlen);
    else strcopy(output, maxlen, base);
    if (headshot) Format(output, maxlen, "%s HS", output);
}

void BuildContext(char[] buffer, int maxlen, const char[] event, int mainClient = -1, int targetClient = -1, const char[] weapon = "")
{
	char mainName[32], targetName[32];
	if (mainClient > 0 && IsClientInGame(mainClient)) GetClientName(mainClient, mainName, sizeof(mainName)); else mainName[0] = '\0';
	if (targetClient > 0 && IsClientInGame(targetClient)) GetClientName(targetClient, targetName, sizeof(targetName)); else targetName[0] = '\0';
	
	int pos = 0;
	if (mainName[0]) {
		pos += Format(buffer[pos], maxlen - pos, "%s %s", mainName, event);
		if (targetName[0] && targetClient != mainClient) {
			pos += Format(buffer[pos], maxlen - pos, " %s", targetName);
		}
		if (weapon[0]) {
			char friendly[32], wShot[64], hsStr[64], wKnife[64], kName[32];
			FriendlyWeaponName(weapon, friendly, sizeof(friendly));
    GetStr("misc", "weapon_shot", wShot, sizeof(wShot));
    GetStr("misc", "headshot", hsStr, sizeof(hsStr));
    GetStr("misc", "weapon_knife", wKnife, sizeof(wKnife));
    GetStr("misc", "knife", kName, sizeof(kName));
			int hsPos = StrContains(friendly, " HS");
			if (hsPos != -1) {
				friendly[hsPos] = '\0';
				pos += Format(buffer[pos], maxlen - pos, wShot, friendly);
				pos += Format(buffer[pos], maxlen - pos, "%s", hsStr);
			} else {
				if (StrEqual(friendly, kName)) pos += Format(buffer[pos], maxlen - pos, "%s", wKnife);
				else pos += Format(buffer[pos], maxlen - pos, wShot, friendly);
			}
		}
		pos += Format(buffer[pos], maxlen - pos, ".");
	} else if (event[0]) pos += Format(buffer[pos], maxlen - pos, "%s ", event);
}

void GetPlayerLocation(int client, char[] buffer, int maxlen) {
	if (client > 0 && IsClientInGame(client)) {
		char token[64];
		GetEntPropString(client, Prop_Send, "m_szLastPlaceName", token, sizeof(token));
		if (token[0] != '\0') {
			GetLocationName(token, buffer, maxlen);
		} else {
			buffer[0] = '\0';
		}
	} else buffer[0] = '\0';
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	g_CurrentRound++; g_BombPlanted = 0.0;
	delete g_RoundStartTimer;
	g_RoundStartTimer = CreateTimer(3.0, Timer_RoundStartMsg, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundStartMsg(Handle timer) {
	g_RoundStartTimer = null;
	if (!CanBotChat() || !RollInterest(IntBase_RoundStart)) return Plugin_Stop;
	char rs[64], ms[64], ctx[1024];
	GetStr("events", "round_start", rs, sizeof(rs));
	GetStr("events", "match_start", ms, sizeof(ms));
	BuildContext(ctx, sizeof(ctx), g_CurrentRound > 1 ? rs : ms);
	GameEvent ev; strcopy(ev.description, sizeof(ev.description), ctx); ev.preferredBot = -1; strcopy(ev.eventType, sizeof(ev.eventType), "round_start");
	AskBotChat(ev);
	return Plugin_Stop;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	delete g_RoundStartTimer;
	int winner = event.GetInt("winner");
	if (!CanBotChat() || !RollInterest(IntBase_RoundEnd)) return;
	char trW[64], ctW[64], ctx[1024];
	GetStr("events", "tr_win", trW, sizeof(trW));
	GetStr("events", "ct_win", ctW, sizeof(ctW));
	GameEvent ev; ev.preferredBot = -1; strcopy(ev.eventType, sizeof(ev.eventType), "round_end");
	if (winner == 2) { BuildContext(ctx, sizeof(ctx), trW); strcopy(ev.description, sizeof(ev.description), ctx); }
	else if (winner == 3) { BuildContext(ctx, sizeof(ctx), ctW); strcopy(ev.description, sizeof(ev.description), ctx); }
	else return;
	AskBotChat(ev);
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast) {
	g_BombPlanted = GetGameTime();
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat() && RollInterest(IntBase_BombPlant)) {
		char bp[64], ls[64], ctx[1024], loc[64];
		GetStr("events", "bomb_plant", bp, sizeof(bp));
		GetStr("events", "location_suffix", ls, sizeof(ls));
		BuildContext(ctx, sizeof(ctx), bp, client);
		GetPlayerLocation(client, loc, sizeof(loc));
		if (loc[0]) { char tmp[640]; Format(tmp, sizeof(tmp), ls, ctx, loc); strcopy(ctx, sizeof(ctx), tmp); }
		GameEvent ev; strcopy(ev.description, sizeof(ev.description), ctx); ev.preferredBot = client; strcopy(ev.eventType, sizeof(ev.eventType), "bomb_planted");
		AskBotChat(ev);
	}
}

public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast) {
	g_BombPlanted = 0.0;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat() && RollInterest(IntBase_BombDefuse)) {
		char bd[64], ls[64], ctx[1024], loc[64];
		GetStr("events", "bomb_defuse", bd, sizeof(bd));
		GetStr("events", "location_suffix", ls, sizeof(ls));
		BuildContext(ctx, sizeof(ctx), bd, client);
		GetPlayerLocation(client, loc, sizeof(loc));
		if (loc[0]) { char tmp[640]; Format(tmp, sizeof(tmp), ls, ctx, loc); strcopy(ctx, sizeof(ctx), tmp); }
		GameEvent ev; strcopy(ev.description, sizeof(ev.description), ctx); ev.preferredBot = client; strcopy(ev.eventType, sizeof(ev.eventType), "bomb_defused");
		AskBotChat(ev);
	}
}

void GetGameFunfactText(const char[] token, char[] buffer, int maxlen, int player, int data1, int data2) {
	buffer[0] = '\0'; char clean[128]; strcopy(clean, sizeof(clean), token);
	if (clean[0] == '#') { int i=0; while(clean[i+1]) { clean[i]=clean[i+1]; i++; } clean[i]='\0'; }
	char raw[512]; GetStr("funfacts", clean, raw, sizeof(raw));
	if (raw[0] == '\0' && g_GameKV != null) {
		g_GameKV.Rewind(); if (g_GameKV.JumpToKey("Tokens")) { g_GameKV.GetString(clean, raw, sizeof(raw)); g_GameKV.GoBack(); }
	}
	if (raw[0]) {
		char pName[64];
		if (player > 0 && IsClientInGame(player)) GetClientName(player, pName, sizeof(pName)); else pName[0] = '\0';
		char d1[16], d2[16]; IntToString(data1, d1, sizeof(d1)); IntToString(data2, d2, sizeof(d2));
		ReplaceString(raw, sizeof(raw), "%s3", d2); ReplaceString(raw, sizeof(raw), "%s2", d1);
		if (pName[0]) ReplaceString(raw, sizeof(raw), "%s1", pName); else ReplaceString(raw, sizeof(raw), "%s1", "");
		TrimString(raw); while (ReplaceString(raw, sizeof(raw), "  ", " ")) {}
		strcopy(buffer, maxlen, raw);
	}
}

public void Event_WinPanel(Event event, const char[] name, bool dontBroadcast) {
	if (!CanBotChat() || !RollInterest(IntBase_WinPanel)) return;
	char ff[128]; event.GetString("funfact_token", ff, sizeof(ff)); if (!ff[0]) return;
	int player = event.GetInt("funfact_player"), d1 = event.GetInt("funfact_data1"), d2 = event.GetInt("funfact_data2");
	char msg[512], ctx[1024];
	GetGameFunfactText(ff, msg, sizeof(msg), player, d1, d2);
	if (msg[0]) strcopy(ctx, sizeof(ctx), msg); else Format(ctx, sizeof(ctx), "Fun fact: %s", ff);
	GameEvent ev; strcopy(ev.description, sizeof(ev.description), ctx); ev.preferredBot = (player > 0 && IsFakeClient(player)) ? player : -1; strcopy(ev.eventType, sizeof(ev.eventType), "default");
	AskBotChat(ev);
}

public void Event_PlayerSay(Event event, const char[] name, bool dontBroadcast) {
	if (!CanBotChat() || !RollInterest(IntBase_PlayerSay)) return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || IsFakeClient(client) || IsClientSourceTV(client)) return;
	char text[128]; event.GetString("text", text, sizeof(text)); if (text[0] == '!' || text[0] == '/') return;
	char pName[32], fmt[128], ctx[1024]; GetClientName(client, pName, sizeof(pName));
	GetStr("events", "player_chat", fmt, sizeof(fmt));
	Format(ctx, sizeof(ctx), fmt, pName, text);
	GameEvent ev; strcopy(ev.description, sizeof(ev.description), ctx); ev.preferredBot = -1; strcopy(ev.eventType, sizeof(ev.eventType), "default");
	AskBotChat(ev);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	if (!CanBotChat() || !RollInterest(IntBase_FriendlyFire)) return;
	int atk = GetClientOfUserId(event.GetInt("attacker")), vic = GetClientOfUserId(event.GetInt("userid"));
	if (atk < 1 || vic < 1 || GetClientTeam(atk) != GetClientTeam(vic) || atk == vic) return;
	char wpn[32], fT[64], fG[64], ctx[1024]; event.GetString("weapon", wpn, sizeof(wpn));
	GetStr("events", "ff_take", fT, sizeof(fT));
	GetStr("events", "ff_give", fG, sizeof(fG));
	GameEvent ev; strcopy(ev.eventType, sizeof(ev.eventType), "default"); strcopy(ev.weapon, sizeof(ev.weapon), wpn);
	if (IsFakeClient(vic)) { ev.preferredBot = vic; BuildContext(ctx, sizeof(ctx), fT, vic, atk, wpn); strcopy(ev.description, sizeof(ev.description), ctx); if (atk > 0 && IsClientInGame(atk)) GetClientName(atk, ev.targetName, sizeof(ev.targetName)); }
	else if (IsFakeClient(atk)) { ev.preferredBot = atk; BuildContext(ctx, sizeof(ctx), fG, atk, vic, wpn); strcopy(ev.description, sizeof(ev.description), ctx); if (vic > 0 && IsClientInGame(vic)) GetClientName(vic, ev.targetName, sizeof(ev.targetName)); }
	else return;
	AskBotChat(ev);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	PrintToServer("[NVD_DEBUG] Event_PlayerDeath");
	if (!CanBotChat()) return;
	int kil = GetClientOfUserId(event.GetInt("attacker")), vic = GetClientOfUserId(event.GetInt("userid")), hs = event.GetInt("headshot");
	if (kil < 1 || vic < 1) return;
	char wpn[32]; event.GetString("weapon", wpn, sizeof(wpn)); if (hs) Format(wpn, sizeof(wpn), "%s HS", wpn);
	if (kil >= 1 && kil <= MaxClients && IsFakeClient(kil)) g_BotKills[kil]++;
	if (vic >= 1 && vic <= MaxClients && IsFakeClient(vic)) g_BotDeaths[vic]++;
	if (kil < 1 || (!IsFakeClient(kil) && !IsFakeClient(vic))) return;
	bool botKillsHuman = IsFakeClient(kil) && !IsFakeClient(vic);
	bool humanKillsBot = !IsFakeClient(kil) && IsFakeClient(vic);
	int baseInt = botKillsHuman ? IntBase_Kill : (humanKillsBot ? IntBase_Death : 25);
	int extra = (event.GetInt("revenge") ? 15 : 0) + (event.GetInt("dominated") ? 20 : 0) + (hs ? 5 : 0);
	if (!RollInterest(baseInt, wpn, extra)) return;
	char rev[64], dom[64], kln[64], dth[64], ls[64], ctx[1024];
	GetStr("events", "revenge", rev, sizeof(rev));
	GetStr("events", "domination", dom, sizeof(dom));
	GetStr("events", "kill", kln, sizeof(kln));
	GetStr("events", "death", dth, sizeof(dth));
	GetStr("events", "location_suffix", ls, sizeof(ls));
	GameEvent ev; strcopy(ev.weapon, sizeof(ev.weapon), wpn);
	if (event.GetInt("revenge")) { BuildContext(ctx, sizeof(ctx), rev, kil, vic, wpn); }
	else if (event.GetInt("dominated")) { BuildContext(ctx, sizeof(ctx), dom, kil, vic, wpn); }
	else if (IsFakeClient(kil) && !IsFakeClient(vic)) { BuildContext(ctx, sizeof(ctx), kln, kil, vic, wpn); strcopy(ev.eventType, sizeof(ev.eventType), "kill"); }
	else if (IsFakeClient(vic) && !IsFakeClient(kil)) { BuildContext(ctx, sizeof(ctx), dth, vic, kil, wpn); strcopy(ev.eventType, sizeof(ev.eventType), "death"); }
	else { BuildContext(ctx, sizeof(ctx), kln, kil, vic, wpn); }
	char loc[64]; GetPlayerLocation(kil, loc, sizeof(loc));
	if (loc[0]) { char tmp[640]; Format(tmp, sizeof(tmp), ls, ctx, loc); strcopy(ctx, sizeof(ctx), tmp); }
	strcopy(ev.description, sizeof(ev.description), ctx);
	if (IsFakeClient(kil) && vic > 0 && IsClientInGame(vic)) GetClientName(vic, ev.targetName, sizeof(ev.targetName));
	else if (IsFakeClient(vic) && kil > 0 && IsClientInGame(kil)) GetClientName(kil, ev.targetName, sizeof(ev.targetName));
	ev.preferredBot = IsFakeClient(kil) ? kil : vic;
	if (!ev.eventType[0]) strcopy(ev.eventType, sizeof(ev.eventType), IsFakeClient(kil) ? "kill" : "death");
	AskBotChat(ev);
}

bool CanBotChat() {
	if (!g_CvarEnabled.BoolValue) { PrintToServer("[NVD_DEBUG] CvarEnabled false"); return false; }
	if (GetGameTime() - g_LastBotChat < g_CvarCooldown.FloatValue) { PrintToServer("[NVD_DEBUG] Cooldown active"); return false; }
	for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) return true;
	PrintToServer("[NVD_DEBUG] No bots found");
	return false;
}

// ── Interest Scoring ──
enum {
	IntBase_Kill        = 30,
	IntBase_Death       = 25,
	IntBase_BombPlant   = 50,
	IntBase_BombDefuse  = 50,
	IntBase_RoundStart  = 30,
	IntBase_RoundEnd    = 30,
	IntBase_WinPanel    = 40,
	IntBase_FriendlyFire = 20,
	IntBase_PlayerSay   = 10,
	IntBase_External    = 45,
};

int GetGameStateBonus()
{
	int bonus = 0;
	if (g_CurrentRound <= 3) bonus += 10;
	int t = CS_GetTeamScore(2), ct = CS_GetTeamScore(3);
	if (t - ct <= 2 && ct - t <= 2) bonus += 15;
	int ctA = 0, tA = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
		if (GetClientTeam(i) == 2) tA++; else if (GetClientTeam(i) == 3) ctA++;
	}
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i) || !IsPlayerAlive(i)) continue;
		int ht = GetClientTeam(i);
		if ((ht == 2 && tA == 1 && ctA >= 2) || (ht == 3 && ctA == 1 && tA >= 2))
			{ bonus += 25; break; }
	}
	return bonus;
}

int CalculateInterest(int base, const char[] weapon = "", int extra = 0)
{
	int score = base + GetGameStateBonus() + extra;
	if (weapon[0]) {
		if (StrContains(weapon, "knife") != -1) score += 20;
		else if (StrContains(weapon, "awp") != -1) score += 10;
	}
	return score > 100 ? 100 : score < 0 ? 0 : score;
}

bool RollInterest(int base, const char[] weapon = "", int extra = 0)
{
	return GetRandomInt(1, 100) <= CalculateInterest(base, weapon, extra);
}

// ── External Plugin Native ──
public int Native_SubmitChatEvent(Handle plugin, int numParams)
{
	char context[512], eventType[32];
	GetNativeString(1, context, sizeof(context));
	int bot = GetNativeCell(2);
	int priority = GetNativeCell(3);
	GetNativeString(4, eventType, sizeof(eventType));
	int enemies = (numParams >= 5) ? GetNativeCell(5) : 0;
	int allies = (numParams >= 6) ? GetNativeCell(6) : 0;
	if (!eventType[0]) strcopy(eventType, sizeof(eventType), "default");
	if (!RollInterest(priority > 0 ? priority : IntBase_External)) return 0;
	if (!StrEqual(eventType, "enemies_left") && !CanBotChat()) return 0;
	GameEvent ev; strcopy(ev.description, sizeof(ev.description), context); ev.preferredBot = bot; strcopy(ev.eventType, sizeof(ev.eventType), eventType); ev.enemies = enemies; ev.allies = allies;
	AskBotChat(ev);
	return 1;
}

public int Native_GetCachedResponse(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	int enemies = GetNativeCell(2);
	int allies = GetNativeCell(3);
	if (bot < 1 || bot > MaxClients) return false;
	for (int i = 0; i < g_BotCache[bot].count; i++) {
		if (g_BotCache[bot].entries[i].enemies == enemies && g_BotCache[bot].entries[i].allies == allies) {
			SetNativeString(4, g_BotCache[bot].entries[i].response, GetNativeCell(5));
			return true;
		}
	}
	// fallback: match enemies count
	for (int i = 0; i < g_BotCache[bot].count; i++) {
		if (g_BotCache[bot].entries[i].enemies == enemies && g_BotCache[bot].entries[i].allies == 0) {
			SetNativeString(4, g_BotCache[bot].entries[i].response, GetNativeCell(5));
			return true;
		}
	}
	// fallback: match allies count
	for (int i = 0; i < g_BotCache[bot].count; i++) {
		if (g_BotCache[bot].entries[i].enemies == 0 && g_BotCache[bot].entries[i].allies == allies) {
			SetNativeString(4, g_BotCache[bot].entries[i].response, GetNativeCell(5));
			return true;
		}
	}
	return false;
}

// ── Timeline History for multi-turn API ──
enum struct GameEvent {
    char description[1024];
    int preferredBot;
    char eventType[32];
    char weapon[32];
    char targetName[32];
    int enemies;
    int allies;
}

void BuildPromptsFromJSON(const char[] json, const char[] section,
    char[] sysP, int sysPLen, char[] fullP, int fullPLen,
    int botId)
{
    JSONObject obj = JSONObject.FromString(json);
    if (obj == null) return;

    char templateType[32], description[1024], target[64], weapon[32], cpFormatted[128];
    obj.GetString("type", templateType, sizeof(templateType));
    obj.GetString("description", description, sizeof(description));
    obj.GetString("target", target, sizeof(target));
    obj.GetString("weapon", weapon, sizeof(weapon));
    obj.GetString("catchphrase", cpFormatted, sizeof(cpFormatted));
    int tScore = obj.GetInt("tScore");
    int ctScore = obj.GetInt("ctScore");
    int enemies = obj.GetInt("enemies");
    int allies = obj.GetInt("allies");
    delete obj;

    char bName[32], bTeam[32];
    if (botId < 1 || botId > MaxClients || !IsClientInGame(botId)) {
        strcopy(bName, sizeof(bName), "Bot");
        strcopy(bTeam, sizeof(bTeam), "Team");
    } else {
        GetClientName(botId, bName, sizeof(bName));
        GetStr("teams", (GetClientTeam(botId) == 2) ? "tr" : "ct", bTeam, sizeof(bTeam));
    }
    int bT = (botId >= 1 && botId <= MaxClients && IsClientInGame(botId)) ? GetClientTeam(botId) : 0;

    char sS[128];
    if ((bT == 2 && tScore > ctScore) || (bT == 3 && ctScore > tScore))
        GetStr("gamestate", "winning", sS, sizeof(sS));
    else if ((bT == 2 && tScore < ctScore) || (bT == 3 && ctScore < tScore))
        GetStr("gamestate", "losing", sS, sizeof(sS));
    else sS[0] = '\0';

    char mapName[64]; GetCurrentMap(mapName, sizeof(mapName));
    char tStr[64]; int gt = RoundFloat(GetGameTime());
    Format(tStr, sizeof(tStr), "%d:%02d", gt / 60, gt % 60);
    char wStr[8], lStr[8], eStr[8], aStr[8];
    IntToString(tScore, wStr, sizeof(wStr)); IntToString(ctScore, lStr, sizeof(lStr));
    IntToString(enemies, eStr, sizeof(eStr)); IntToString(allies, aStr, sizeof(aStr));
    char roundStr[16]; IntToString(g_CurrentRound, roundStr, sizeof(roundStr));
    char bombStr[32]; GetStr("misc", "bomb_planted", bombStr, sizeof(bombStr));
    if (!g_BombPlanted) bombStr[0] = '\0';

    char wBuf[32]; if (weapon[0]) { FriendlyWeaponName(weapon, wBuf, sizeof(wBuf)); int hsP = StrContains(wBuf, " HS"); if (hsP!=-1) wBuf[hsP]='\0'; }
    else GetStr("misc", "unknown_weapon", wBuf, sizeof(wBuf));

    if (StrEqual(section, "system") || StrEqual(section, "both")) {
        if (!GetPromptTemplate(templateType, "system", sysP, sysPLen, bName, bTeam, target, sS, description, cpFormatted, g_CurrentRound, tScore, ctScore))
            Format(sysP, sysPLen, "Speak as %s (%s). %s", bName, bTeam, description);
        ReplaceString(sysP, sysPLen, "|map|", mapName);
        ReplaceString(sysP, sysPLen, "|wins|", wStr);
        ReplaceString(sysP, sysPLen, "|losses|", lStr);
        ReplaceString(sysP, sysPLen, "|time|", tStr);
        ReplaceString(sysP, sysPLen, "|round|", roundStr);
        ReplaceString(sysP, sysPLen, "|bomb|", bombStr);
        ReplaceString(sysP, sysPLen, "|weapon|", wBuf);
        ReplaceString(sysP, sysPLen, "|enemies|", eStr);
        ReplaceString(sysP, sysPLen, "|allies|", aStr);
        ReplaceString(sysP, sysPLen, "|catchphrase|", cpFormatted);
        ReplaceString(sysP, sysPLen, "  ", " ");
        ReplaceString(sysP, sysPLen, " .", ".");
        ReplaceString(sysP, sysPLen, "..", ".");
    }

    if (StrEqual(section, "user") || StrEqual(section, "both")) {
        if (!GetPromptTemplate(templateType, "user", fullP, fullPLen, bName, bTeam, target, sS, description, cpFormatted, g_CurrentRound, tScore, ctScore))
            Format(fullP, fullPLen, "Speak as %s about %s", bName, description);
        ReplaceString(fullP, fullPLen, "|map|", mapName);
        ReplaceString(fullP, fullPLen, "|wins|", wStr);
        ReplaceString(fullP, fullPLen, "|losses|", lStr);
        ReplaceString(fullP, fullPLen, "|time|", tStr);
        ReplaceString(fullP, fullPLen, "|round|", roundStr);
        ReplaceString(fullP, fullPLen, "|bomb|", bombStr);
        ReplaceString(fullP, fullPLen, "|weapon|", wBuf);
        ReplaceString(fullP, fullPLen, "|enemies|", eStr);
        ReplaceString(fullP, fullPLen, "|allies|", aStr);
        ReplaceString(fullP, fullPLen, "|catchphrase|", cpFormatted);
        ReplaceString(fullP, fullPLen, "  ", " ");
        ReplaceString(fullP, fullPLen, ". .", ".");
        ReplaceString(fullP, fullPLen, " .", ".");
        ReplaceString(fullP, fullPLen, "..", ".");
        TrimString(fullP);
    }
}

// NVD_BuildPrompts native for inter-plugin use (ollama.sp calls this)
public int Native_BuildPrompts(Handle plugin, int numParams)
{
    char json[1024], section[16];
    GetNativeString(1, json, sizeof(json));
    GetNativeString(2, section, sizeof(section));
    int botId = GetNativeCell(3);

    if (botId < 1 || botId > MaxClients || !IsClientInGame(botId)) {
        LogMessage("[NVD_ERROR] Native_BuildPrompts: Invalid or disconnected botId=%d", botId);
        return 0;
    }

    char sysP[2048], fullP[1024];
    BuildPromptsFromJSON(json, section, sysP, sizeof(sysP), fullP, sizeof(fullP), botId);

    SetNativeString(4, sysP, GetNativeCell(5));
    SetNativeString(6, fullP, GetNativeCell(7));
    return 1;
}

void RecordEvent(const char[] description)
{
	if (description[0] == '\0') return;
	strcopy(g_History[g_HistIdx].role, 32, "user");
	strcopy(g_History[g_HistIdx].content, HISTORY_CONTENT_LEN, description);
	g_HistIdx = (g_HistIdx + 1) % MAX_HISTORY_ENTRIES;
	if (g_HistCount < MAX_HISTORY_ENTRIES) g_HistCount++;
}

void RecordBotMessage(const char[] botName, const char[] message)
{
	if (message[0] == '\0') return;
	strcopy(g_History[g_HistIdx].role, 32, botName);
	strcopy(g_History[g_HistIdx].content, HISTORY_CONTENT_LEN, message);
	g_HistIdx = (g_HistIdx + 1) % MAX_HISTORY_ENTRIES;
	if (g_HistCount < MAX_HISTORY_ENTRIES) g_HistCount++;
}

void EscapeJSON(const char[] input, char[] output, int maxlen)
{
    int ep = 0;
    for (int c = 0; input[c] != '\0' && ep < maxlen - 4; c++) {
        if (input[c] == '"') { output[ep++] = '\\'; output[ep++] = '"'; }
        else if (input[c] == '\\') { output[ep++] = '\\'; output[ep++] = '\\'; }
        else output[ep++] = input[c];
    }
    output[ep] = '\0';
}

void BuildHistoryBlock(char[] buffer, int maxlen, const char[] catchphrase = "")
{
    buffer[0] = '\0';
    int pos = 0;
    pos += Format(buffer[pos], maxlen - pos, "[");
    bool first = true;

    // Real history (cap at 3 most recent)
    static const int MAX_REAL_HISTORY = 3;
    if (g_HistCount > 0) {
        int take = g_HistCount > MAX_REAL_HISTORY ? MAX_REAL_HISTORY : g_HistCount;
        int start = (g_HistIdx - take + MAX_HISTORY_ENTRIES) % MAX_HISTORY_ENTRIES;
        for (int i = 0; i < take; i++) {
            int idx = (start + i) % MAX_HISTORY_ENTRIES;
            if (g_History[idx].content[0] == '\0') continue;
            
            char escaped[512], role[32], content[HISTORY_CONTENT_LEN + 64];
            EscapeJSON(g_History[idx].content, escaped, sizeof(escaped));
            
            if (StrEqual(g_History[idx].role, "user")) {
                strcopy(role, sizeof(role), "user");
                strcopy(content, sizeof(content), escaped);
            } else {
                strcopy(role, sizeof(role), "assistant");
                Format(content, sizeof(content), "@%s: %s", g_History[idx].role, escaped);
            }

            if (!first) pos += Format(buffer[pos], maxlen - pos, ",");
            pos += Format(buffer[pos], maxlen - pos, "{\"role\":\"%s\",\"content\":\"%s\"}", role, content);
            first = false;
        }
    } else {
        // Fallback seed if no history
        char phrases[3][64]; int pCount = 0;
        if (catchphrase[0]) pCount = ExplodeString(catchphrase, ";", phrases, 3, 64);
        if (pCount == 0) { strcopy(phrases[0], sizeof(phrases[]), "ez"); pCount = 1; }
        pos += Format(buffer[pos], maxlen - pos, "{\"role\":\"user\",\"content\":\"Round start.\"},{\"role\":\"assistant\",\"content\":\"%s\"}", phrases[0]);
    }

    pos += Format(buffer[pos], maxlen - pos, "]");
}

void AskBotChat(GameEvent ev) {
    PrintToServer("[NVD_DEBUG] AskBotChat called. Event: %s", ev.eventType);
    int bot; if (ev.preferredBot >= 1 && ev.preferredBot <= MaxClients && IsClientInGame(ev.preferredBot) && IsFakeClient(ev.preferredBot)) bot = ev.preferredBot;
    else {
        int bots[MAXPLAYERS+1], bCnt = 0;
        for (int i=1; i<=MaxClients; i++) if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) bots[bCnt++] = i;
        if (!bCnt) return; bot = bots[GetRandomInt(0, bCnt-1)];
    }

    char type[32]; strcopy(type, sizeof(type), ev.eventType);
    if (StrEqual(type, "default")) {
        if (StrContains(ev.description, "eliminated") != -1 || StrContains(ev.description, "eliminou") != -1) strcopy(type, sizeof(type), "kill");
        else if (StrContains(ev.description, "was eliminated") != -1 || StrContains(ev.description, "foi eliminado") != -1) strcopy(type, sizeof(type), "death");
    }

    char target[32];
    if (ev.targetName[0]) strcopy(target, sizeof(target), ev.targetName);
    else target[0] = '\0';

    char wBuf[32]; if (ev.weapon[0]) { FriendlyWeaponName(ev.weapon, wBuf, sizeof(wBuf)); int hsP = StrContains(wBuf, " HS"); if (hsP!=-1) wBuf[hsP]='\0'; }
    else GetStr("misc", "unknown_weapon", wBuf, sizeof(wBuf));

    int tS = CS_GetTeamScore(2), ctS = CS_GetTeamScore(3);

    char catchphrase[64], pers[8], sty[8], beh[8];
    char bName[32]; GetClientName(bot, bName, sizeof(bName));
    GetBotPersonality(bName, pers, sizeof(pers), catchphrase, sizeof(catchphrase), sty, sizeof(sty), beh, sizeof(beh));
    char cpFormatted[128];
    char parts[3][32]; int n = ExplodeString(catchphrase, ";", parts, 3, 32);
    for (int i = 0; i < n; i++) { TrimString(parts[i]); if (parts[i][0]) { if (i > 0) StrCat(cpFormatted, sizeof(cpFormatted), " "); Format(cpFormatted, sizeof(cpFormatted), "%s\"%s\"", cpFormatted, parts[i]); } }

    // ── Context JSON (rebuilt at queue/display time) ──
    JSONObject ctx = new JSONObject();
    ctx.SetString("type", type);
    ctx.SetString("description", type); // ENVIA APENAS O TIPO, NADA DE NARRAÇÃO
    ctx.SetString("target", target);
    ctx.SetString("weapon", wBuf);
    ctx.SetInt("tScore", tS);
    ctx.SetInt("ctScore", ctS);
    ctx.SetInt("enemies", ev.enemies);
    ctx.SetInt("allies", ev.allies);
    ctx.SetString("catchphrase", cpFormatted);
    char contextJSON[1024];
    ctx.ToString(contextJSON, sizeof(contextJSON));
    delete ctx;

    int cachedIdx = -1;
    // 30% de chance de ignorar o cache para forçar criatividade
    if (GetRandomInt(1, 100) > 30) {
        for (int i = 0; i < g_BotCache[bot].count; i++) {
            if (g_BotCache[bot].entries[i].enemies == ev.enemies && g_BotCache[bot].entries[i].allies == ev.allies) {
                cachedIdx = i;
                break;
            }
        }
    }
    if (cachedIdx != -1)
    {
        char clean[320];
        strcopy(clean, sizeof(clean), g_BotCache[bot].entries[cachedIdx].response);
        ReplaceString(clean, 320, "\"", ""); ReplaceString(clean, 320, "[", ""); ReplaceString(clean, 320, "]", ""); TrimString(clean);
        if (clean[0])
        {
            if (strlen(clean) > 180) clean[180] = '\0';
            FakeClientCommand(bot, "say %s", clean); g_LastBotChat = GetGameTime();
            RecordBotMessage(bName, clean);
            char ts[32]; FormatTime(ts, sizeof(ts), "%H:%M:%S");
            PrintToServer("[BOT_CHAT] [%s] ✅ Cached: [BOT %s] %s", ts, bName, clean);
            RecordEvent(ev.description);
            return;
        }
    }

    if (StrEqual(type, "enemies_left")) {
        char historyBlock[1024];
        BuildHistoryBlock(historyBlock, sizeof(historyBlock), catchphrase);
        g_LastEnemies[bot] = ev.enemies;
        g_LastAllies[bot] = ev.allies;
        NVD_AskAI("", "", CacheOnlyResponse, bot, historyBlock, 1, g_CvarTimeout.FloatValue, "", contextJSON);
        strcopy(g_LastEventType[bot], 32, type); g_LastAskTime[bot] = GetGameTime();
        RecordEvent(ev.description);
        return;
    }

    char historyBlock[1024];
    BuildHistoryBlock(historyBlock, sizeof(historyBlock), catchphrase);

    g_LastEnemies[bot] = ev.enemies;
    g_LastAllies[bot] = ev.allies;
    NVD_AskAI("", "", INVALID_FUNCTION, bot, historyBlock, 1, g_CvarTimeout.FloatValue, "", contextJSON);
    strcopy(g_LastEventType[bot], 32, type); g_LastAskTime[bot] = GetGameTime();
    RecordEvent(ev.description);
}

public void CacheOnlyResponse(const char[] reply, any bot)
{
    if (bot < 1 || bot > MaxClients || !IsClientInGame(bot) || !IsFakeClient(bot)) return;
    if (StrContains(reply, "ERROR_") != -1 || !reply[0]) return;
    char clean[320]; strcopy(clean, sizeof(clean), reply);
    ReplaceString(clean, sizeof(clean), "\"", ""); ReplaceString(clean, sizeof(clean), "[", ""); ReplaceString(clean, sizeof(clean), "]", ""); TrimString(clean);
    if (!clean[0]) return;
    if (g_BotCache[bot].count < 30) {
        int ci = g_BotCache[bot].count;
        strcopy(g_BotCache[bot].entries[ci].response, sizeof(g_BotCache[bot].entries[ci].response), clean);
        g_BotCache[bot].entries[ci].enemies = g_LastEnemies[bot];
        g_BotCache[bot].entries[ci].allies = g_LastAllies[bot];
        g_BotCache[bot].entries[ci].valid = true;
        g_BotCache[bot].count++;
    }
    char bName[32]; GetClientName(bot, bName, sizeof(bName));
    PrintToServer("[BOT_CHAT] [CACHE] Cached for bot %s: %s", bName, clean);
}

public Action Timer_PollResponses(Handle timer) { PollBotResponses(); return Plugin_Continue; }
void PollBotResponses() {
    char reply[2048]; any bot; char ts[32]; FormatTime(ts, sizeof(ts), "%H:%M:%S");
    while (NVD_PollResponse(reply, sizeof(reply), bot)) {
        if (bot == 0 || !IsClientInGame(bot) || !IsFakeClient(bot)) {
            int aB[MAXPLAYERS+1], aBC = 0;
            for (int i=1; i<=MaxClients; i++) if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) aB[aBC++] = i;
            if (!aBC) continue; bot = aB[GetRandomInt(0, aBC-1)];
        }
        if (StrContains(reply, "ERROR_") != -1 || !reply[0]) {
            if (g_BotCache[bot].count > 0) {
                int ci = g_BotCache[bot].count - 1;
                strcopy(reply, sizeof(reply), g_BotCache[bot].entries[ci].response);
            } else {
                continue;
            }
        }
        char bName[32], clean[320]; GetClientName(bot, bName, sizeof(bName)); strcopy(clean, sizeof(clean), reply);
        PrintToServer("[NVD_DEBUG] PollBotResponses: Bot %s, Reply: %s", bName, clean);
        ReplaceString(clean, 320, "\"", ""); ReplaceString(clean, 320, "[", ""); ReplaceString(clean, 320, "]", ""); TrimString(clean);
        if (!clean[0]) {
            if (g_BotCache[bot].count > 0) {
                int ci = g_BotCache[bot].count - 1;
                strcopy(clean, sizeof(clean), g_BotCache[bot].entries[ci].response);
            } else {
                continue;
            }
        }
        if (g_BotCache[bot].count < 30) {
            int ci = g_BotCache[bot].count;
            strcopy(g_BotCache[bot].entries[ci].response, sizeof(g_BotCache[bot].entries[ci].response), clean);
            g_BotCache[bot].entries[ci].enemies = g_LastEnemies[bot];
            g_BotCache[bot].entries[ci].allies = g_LastAllies[bot];
            g_BotCache[bot].entries[ci].valid = true;
            g_BotCache[bot].count++;
        }
        if (strlen(clean) > 180) clean[180] = '\0';
        FakeClientCommand(bot, "say %s", clean); g_LastBotChat = GetGameTime();
        RecordBotMessage(bName, clean);
        PrintToServer("[BOT_CHAT] [%s] ✅ Sent: [BOT %s] %s", ts, bName, clean);
    }
}

void LoadPersonalities() {
    if (g_PersonalityKV != null) delete g_PersonalityKV;
    g_PersonalityKV = new KeyValues("BotPersonalities");
    char path[PLATFORM_MAX_PATH]; BuildPath(Path_SM, path, sizeof(path), "configs/nvd_bot_personalities.txt");
    if (FileExists(path)) g_PersonalityKV.ImportFromFile(path);
}

void GetBotPersonality(const char[] name, char[] pers, int pL, char[] cat, int cL, char[] sty, int sL, char[] beh, int bL) {
    if (g_PersonalityKV == null) return;
    g_PersonalityKV.Rewind(); if (g_PersonalityKV.JumpToKey(name)) {
        g_PersonalityKV.GetString("personality", pers, pL); g_PersonalityKV.GetString("catchphrase", cat, cL);
        g_PersonalityKV.GetString("style", sty, sL); g_PersonalityKV.GetString("behavior", beh, bL);
    }
}

void LoadPromptTemplates() {
    if (g_PromptKV != null) delete g_PromptKV;
    g_PromptKV = new KeyValues("BotChatPrompts");
    char path[PLATFORM_MAX_PATH]; BuildPath(Path_SM, path, sizeof(path), "configs/nvd_bot_chat_prompts.txt");
    if (FileExists(path)) g_PromptKV.ImportFromFile(path);
}
