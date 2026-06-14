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
#define MAX_HISTORY_ENTRIES 8
#define HISTORY_CONTENT_LEN 256
#define MAX_CATCHPHRASES 3

// ── Globals (declared here before includes) ──
ConVar g_CvarEnabled;
ConVar g_CvarCooldown;
ConVar g_CvarTimeout;
ConVar g_CvarEventInterval;
ConVar g_CvarPollInterval;
KeyValues g_PromptKV = null;
KeyValues g_PersonalityKV = null;

ArrayList g_EventQueue;

int g_CurrentRound;
float g_BombPlanted;
Handle g_RoundStartTimer;

float g_LastBotChat;

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
int g_BotKills[MAXPLAYERS + 1];
int g_BotDeaths[MAXPLAYERS + 1];
char g_LastEventType[MAXPLAYERS + 1][32];
float g_LastAskTime[MAXPLAYERS + 1];

enum struct HistoryEntry {
    char role[32];
    char content[HISTORY_CONTENT_LEN];
}
HistoryEntry g_History[MAX_HISTORY_ENTRIES];
int g_HistIdx;
int g_HistCount;

// ── Includes ──
#include <nvd/events>
#include <nvd/requests>

// ── Natives ──
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    RegPluginLibrary("nvd_bot_chat");
    CreateNative("NVD_BuildPrompts", Native_BuildPrompts);
    CreateNative("NVD_SubmitChatEvent", Native_SubmitChatEvent);
    CreateNative("NVD_GetCachedResponse", Native_GetCachedResponse);
    return APLRes_Success;
}

// ── Plugin Info ──
public Plugin myinfo = {
    name = "NVD Bot Chat",
    author = "OpenCode",
    description = "AI-powered bot chat with structured events",
    version = "3.1.0",
    url = "https://opencode.ai"
};

public void OnPluginStart()
{
    g_CvarEnabled = CreateConVar("nvd_bot_chat", "1", "Enable AI bot chat messages");
    g_CvarCooldown = CreateConVar("nvd_bot_chat_cooldown", "12.0", "Min seconds between bot messages");
    g_CvarTimeout = CreateConVar("nvd_bot_chat_timeout", "120.0", "Max seconds to wait for AI response before giving up");
    g_CvarEventInterval = CreateConVar("nvd_bot_chat_event_interval", "0.1", "Seconds between event queue processing ticks");
    g_CvarPollInterval = CreateConVar("nvd_bot_chat_poll_interval", "0.15", "Seconds between response polling ticks");

    AutoExecConfig(true, "nvd_bot_chat");

    g_EventQueue = new ArrayList();
    g_HistIdx = 0; g_HistCount = 0;

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_say", Event_PlayerSay);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombDefused);
    HookEvent("cs_win_panel_round", Event_WinPanel);

    CreateTimer(g_CvarEventInterval.FloatValue, Timer_ProcessEvents, _, TIMER_REPEAT);
    CreateTimer(g_CvarPollInterval.FloatValue, Timer_PollResponses_, _, TIMER_REPEAT);

    LoadPromptTemplates();
    LoadPersonalities();

    RegAdminCmd("sm_botchat_reload", Command_ReloadPrompts, ADMFLAG_GENERIC);
    RegAdminCmd("sm_botchat_history", Command_BotChatHistory, ADMFLAG_GENERIC);

    CreateTimer(5.0, Timer_DelayedReRegister, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart()
{
    g_BombPlanted = 0.0;
    g_LastBotChat = 0.0;
    g_HistIdx = 0; g_HistCount = 0;
    for (int i = 1; i <= MaxClients; i++) {
        g_BotKills[i] = 0; g_BotDeaths[i] = 0; g_BotCache[i].count = 0;
        g_LastEnemies[i] = 0; g_LastAllies[i] = 0;
    }
}

public void OnClientDisconnect(int client)
{
    if (client > 0 && client <= MaxClients) g_BotCache[client].count = 0;
}

public void OnPluginEnd()
{
    delete g_EventQueue;
}

public Action Timer_ProcessEvents(Handle timer)
{
    if (g_EventQueue.Length == 0) return Plugin_Continue;
    bool hasBot;
    for (int i = 1; i <= MaxClients; i++) { if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) { hasBot = true; break; } }
    if (!hasBot) { GameEvent ev; PopEvent(ev); return Plugin_Continue; }
    if (!g_CvarEnabled.BoolValue) return Plugin_Continue;
    if (GetGameTime() - g_LastBotChat < g_CvarCooldown.FloatValue) return Plugin_Continue;

    GameEvent ev;
    if (!PopEvent(ev)) return Plugin_Continue;
    AskBotChat(ev);
    return Plugin_Continue;
}

public Action Timer_PollResponses_(Handle timer)
{
    PollBotResponses();
    return Plugin_Continue;
}

// ── GetStr wrapper ──
stock void GetStr(const char[] section, const char[] key, char[] buffer, int maxlen)
{
    char fullPath[256];
    Format(fullPath, sizeof(fullPath), "nvd.bot_chat.%s.%s", section, key);
    if (!NVD_HasStr(fullPath)) { buffer[0] = '\0'; return; }
    NVD_GetStr(fullPath, buffer, maxlen);
}

// ── Prompt Templates ──
bool GetPromptTemplate(const char[] eventType, const char[] promptType,
    char[] buffer, int maxlen,
    const char[] bot = "", const char[] team = "",
    const char[] target = "", const char[] state = "",
    const char[] event = "", const char[] cpFormatted = "",
    int round = 0, int tScore = 0, int ctScore = 0)
{
    char template[2048], langKey[64];
    Format(langKey, sizeof(langKey), "%s_%s", eventType, promptType);
    GetStr("prompts", langKey, template, sizeof(template));
    if (template[0] == '\0' && StrEqual(promptType, "system"))
        GetStr("prompts", "system", template, sizeof(template));
    if (template[0] == '\0') {
        if (g_PromptKV == null) return false;
        g_PromptKV.Rewind();
        if (g_PromptKV.JumpToKey("prompts")) {
            char kvKey[64]; Format(kvKey, sizeof(kvKey), "%s_%s", eventType, promptType);
            g_PromptKV.GetString(kvKey, template, sizeof(template));
            if (template[0] == '\0' && StrEqual(promptType, "system"))
                g_PromptKV.GetString("system", template, sizeof(template));
            g_PromptKV.Rewind();
        }
    }
    if (template[0] == '\0') return false;
    ReplaceString(template, sizeof(template), "[bot]", bot);
    ReplaceString(template, sizeof(template), "[team]", team);
    ReplaceString(template, sizeof(template), "[target]", target);
    if (cpFormatted[0]) {
        char cpKey[16] = "[catchphrase]";
        if (StrContains(template, cpKey) != -1) {
            char phrases[MAX_CATCHPHRASES][64]; int pCount = ExplodeString(cpFormatted, ";", phrases, MAX_CATCHPHRASES, 64);
            if (pCount > 0) { int idx = GetRandomInt(0, pCount - 1); ReplaceString(template, sizeof(template), cpKey, phrases[idx]); }
        }
    }
    ReplaceString(template, sizeof(template), "[catchphrase]", cpFormatted);
    ReplaceString(template, sizeof(template), "[event]", event);
    ReplaceString(template, sizeof(template), "[state]", state);
    if (StrContains(template, "[mood]") != -1) {
        char moods[3][64]; int mCount = 0;
        char raw[196]; GetStr("moods", "list", raw, sizeof(raw));
        if (raw[0]) mCount = ExplodeString(raw, ";", moods, 3, 64);
        if (mCount > 0) ReplaceString(template, sizeof(template), "[mood]", moods[GetRandomInt(0, mCount - 1)]);
    }
    char rStr[16], wStr[16], lStr[16];
    IntToString(round, rStr, sizeof(rStr));
    IntToString(tScore, wStr, sizeof(wStr)); IntToString(ctScore, lStr, sizeof(lStr));
    ReplaceString(template, sizeof(template), "[round]", rStr);
    ReplaceString(template, sizeof(template), "[score]", wStr);
    ReplaceString(template, sizeof(template), "[wins]", wStr);
    ReplaceString(template, sizeof(template), "[losses]", lStr);
    ReplaceString(template, sizeof(template), "[personality]", ""); ReplaceString(template, sizeof(template), "[style]", "");
    ReplaceString(template, sizeof(template), "[behavior]", ""); ReplaceString(template, sizeof(template), "[rules]", "");
    ReplaceString(template, sizeof(template), "[critical]", "");
    strcopy(buffer, maxlen, template);
    return true;
}

void LoadPromptTemplates() {
    if (g_PromptKV != null) delete g_PromptKV;
    g_PromptKV = new KeyValues("BotChatPrompts");
    char path[PLATFORM_MAX_PATH]; BuildPath(Path_SM, path, sizeof(path), "configs/nvd_bot_chat_prompts.txt");
    if (FileExists(path)) g_PromptKV.ImportFromFile(path);
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

stock void FriendlyWeaponName(const char[] weapon, char[] buffer, int maxlen) {
    int pos = StrContains(weapon, "weapon_");
    if (pos == 0) {
        char base[32]; strcopy(base, sizeof(base), weapon[7]);
        int hsp = StrContains(base, "_hs");
        if (hsp != -1) { Format(base[hsp], 4, " HS"); }
        GetStr("weapons_fallback", base, buffer, maxlen);
    } else {
        char lower[32]; strcopy(lower, sizeof(lower), weapon);
        int len = strlen(lower);
        for (int i = 0; i < len; i++) lower[i] = CharToLower(lower[i]);
        GetStr("weapons", lower, buffer, maxlen);
    }
    if (buffer[0] == '\0' && weapon[0]) strcopy(buffer, maxlen, weapon);
}

// ── BuildPromptsFromJSON ──
stock void SubstitutePlaceholders(char[] buf, int maxlen,
    const char[] bName, const char[] bTeam, const char[] target, const char[] sS,
    const char[] mapName, const char[] wStr, const char[] lStr, const char[] tStr,
    const char[] roundStr, const char[] bombStr, const char[] wBuf,
    const char[] eStr, const char[] aStr, const char[] cpFormatted,
    bool user)
{
    ReplaceString(buf, maxlen, "|bot|", bName);
    ReplaceString(buf, maxlen, "|team|", bTeam);
    ReplaceString(buf, maxlen, "|target|", target);
    ReplaceString(buf, maxlen, "|state|", sS);
    ReplaceString(buf, maxlen, "|map|", mapName);
    ReplaceString(buf, maxlen, "|wins|", wStr);
    ReplaceString(buf, maxlen, "|losses|", lStr);
    ReplaceString(buf, maxlen, "|time|", tStr);
    ReplaceString(buf, maxlen, "|round|", roundStr);
    ReplaceString(buf, maxlen, "|bomb|", bombStr);
    ReplaceString(buf, maxlen, "|weapon|", wBuf);
    ReplaceString(buf, maxlen, "|enemies|", eStr);
    ReplaceString(buf, maxlen, "|allies|", aStr);
    ReplaceString(buf, maxlen, "|catchphrase|", cpFormatted);
    ReplaceString(buf, maxlen, "  ", " ");
    ReplaceString(buf, maxlen, ". .", ".");
    ReplaceString(buf, maxlen, " .", ".");
    ReplaceString(buf, maxlen, "..", ".");
    if (user) TrimString(buf);
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
        strcopy(bName, sizeof(bName), "Bot"); strcopy(bTeam, sizeof(bTeam), "Team");
    } else {
        GetClientName(botId, bName, sizeof(bName));
        GetStr("teams", (GetClientTeam(botId) == 2) ? "tr" : "ct", bTeam, sizeof(bTeam));
    }
    int bT = (botId >= 1 && botId <= MaxClients && IsClientInGame(botId)) ? GetClientTeam(botId) : 0;
    char sS[128];
    if ((bT == 2 && tScore > ctScore) || (bT == 3 && ctScore > tScore)) GetStr("gamestate", "winning", sS, sizeof(sS));
    else if ((bT == 2 && tScore < ctScore) || (bT == 3 && ctScore < tScore)) GetStr("gamestate", "losing", sS, sizeof(sS));
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
    char wBuf[32];
    if (weapon[0]) { FriendlyWeaponName(weapon, wBuf, sizeof(wBuf)); int hsP = StrContains(wBuf, " HS"); if (hsP != -1) wBuf[hsP] = '\0'; }
    else GetStr("misc", "unknown_weapon", wBuf, sizeof(wBuf));
    if (StrEqual(section, "system") || StrEqual(section, "both")) {
        if (!GetPromptTemplate(templateType, "system", sysP, sysPLen, bName, bTeam, target, sS, description, cpFormatted, g_CurrentRound, tScore, ctScore))
            Format(sysP, sysPLen, "Speak as %s (%s). %s", bName, bTeam, description);
        SubstitutePlaceholders(sysP, sysPLen, bName, bTeam, target, sS, mapName, wStr, lStr, tStr, roundStr, bombStr, wBuf, eStr, aStr, cpFormatted, false);
    }
    if (StrEqual(section, "user") || StrEqual(section, "both")) {
        if (!GetPromptTemplate(templateType, "user", fullP, fullPLen, bName, bTeam, target, sS, description, cpFormatted, g_CurrentRound, tScore, ctScore))
            Format(fullP, fullPLen, "Speak as %s about %s", bName, description);
        SubstitutePlaceholders(fullP, fullPLen, bName, bTeam, target, sS, mapName, wStr, lStr, tStr, roundStr, bombStr, wBuf, eStr, aStr, cpFormatted, true);
    }
}

// ── Native: BuildPrompts ──
public int Native_BuildPrompts(Handle plugin, int numParams) {
    char json[1024], section[16];
    GetNativeString(1, json, sizeof(json));
    GetNativeString(2, section, sizeof(section));
    int botId = GetNativeCell(3);
    char sysP[2048], fullP[1024];
    BuildPromptsFromJSON(json, section, sysP, sizeof(sysP), fullP, sizeof(fullP), botId);
    SetNativeString(4, sysP, GetNativeCell(5));
    SetNativeString(6, fullP, GetNativeCell(7));
    return 1;
}

// ── Commands ──
public Action Command_BotChatHistory(int client, int args) {
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

public Action Command_ReloadPrompts(int client, int args) {
    LoadPromptTemplates();
    NVD_RegisterStrings("nvd_bot_chat");
    Timer_DelayedReRegister(null);
    ReplyToCommand(client, "[BOT_CHAT] ✅ Templates reloaded");
    return Plugin_Handled;
}

void LoadMetaFromStrings() {
    char rules[1024], critical[1024];
    GetStr("behavior", "rules", rules, sizeof(rules));
    GetStr("behavior", "critical", critical, sizeof(critical));
    NVD_SetMeta("rules", rules);
    NVD_SetMeta("critical", critical);
}

public Action Timer_DelayedReRegister(Handle timer) {
    NVD_RegisterStrings("nvd_bot_chat");
    LoadMetaFromStrings();
    return Plugin_Stop;
}

// ── Natives ──
public int Native_SubmitChatEvent(Handle plugin, int numParams) {
    char context[512], eventType[32];
    GetNativeString(1, context, sizeof(context));
    int bot = GetNativeCell(2);
    int priority = GetNativeCell(3);
    GetNativeString(4, eventType, sizeof(eventType));
    int enemies = (numParams >= 5) ? GetNativeCell(5) : 0;
    int allies = (numParams >= 6) ? GetNativeCell(6) : 0;
    if (!eventType[0]) strcopy(eventType, sizeof(eventType), "default");
    if (!RollInterest(priority > 0 ? priority : IntBase_External)) return 0;
    GameEvent ev; strcopy(ev.description, sizeof(ev.description), context); ev.preferredBot = bot;
    strcopy(ev.eventType, sizeof(ev.eventType), eventType); ev.enemies = enemies; ev.allies = allies;
    PushEvent(ev);
    return 1;
}

public int Native_GetCachedResponse(Handle plugin, int numParams) {
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
    for (int i = 0; i < g_BotCache[bot].count; i++) {
        if (g_BotCache[bot].entries[i].enemies == enemies && g_BotCache[bot].entries[i].allies == 0) {
            SetNativeString(4, g_BotCache[bot].entries[i].response, GetNativeCell(5));
            return true;
        }
    }
    for (int i = 0; i < g_BotCache[bot].count; i++) {
        if (g_BotCache[bot].entries[i].enemies == 0 && g_BotCache[bot].entries[i].allies == allies) {
            SetNativeString(4, g_BotCache[bot].entries[i].response, GetNativeCell(5));
            return true;
        }
    }
    return false;
}
