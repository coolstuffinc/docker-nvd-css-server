#if defined _nvd_events_included
#endinput
#endif
#define _nvd_events_included

#define MAX_EVENT_QUEUE 128

enum struct GameEvent {
    char eventType[32];
    char description[1024];
    int preferredBot;
    char weapon[32];
    char targetName[32];
    int enemies;
    int allies;

    void ToStringJSON(char[] buffer, int maxlen) {
        JSONObject ctx = new JSONObject();
        ctx.SetString("type", this.eventType);
        ctx.SetString("description", this.description);
        ctx.SetString("target", this.targetName);
        char wBuf[32];
        if (this.weapon[0]) { FriendlyWeaponName(this.weapon, wBuf, sizeof(wBuf)); int hsP = StrContains(wBuf, " HS"); if (hsP != -1) wBuf[hsP] = '\0'; }
        ctx.SetString("weapon", wBuf);
        ctx.SetInt("tScore", CS_GetTeamScore(2));
        ctx.SetInt("ctScore", CS_GetTeamScore(3));
        ctx.SetInt("enemies", this.enemies);
        ctx.SetInt("allies", this.allies);
        ctx.ToString(buffer, maxlen);
        delete ctx;
    }

    void ToStringStructured(char[] buffer, int maxlen) {
        char tag[32]; strcopy(tag, sizeof(tag), this.eventType);
        for (int i = 0; i < strlen(tag); i++) tag[i] = CharToUpper(tag[i]);
        Format(buffer, maxlen, "[EVENT: %s]", tag);
        if (this.targetName[0])
            Format(buffer, maxlen, "%s [TARGET: %s]", buffer, this.targetName);
        if (this.weapon[0]) {
            char wBuf[32]; FriendlyWeaponName(this.weapon, wBuf, sizeof(wBuf));
            int hsP = StrContains(wBuf, " HS"); if (hsP != -1) wBuf[hsP] = '\0';
            Format(buffer, maxlen, "%s [WEAPON: %s]", buffer, wBuf);
        }
        if (this.enemies > 0 || this.allies > 0)
            Format(buffer, maxlen, "%s [ENEMIES: %d] [ALLIES: %d]", buffer, this.enemies, this.allies);
    }

    void ToStringShort(char[] buffer, int maxlen) {
        char tag[32]; strcopy(tag, sizeof(tag), this.eventType);
        for (int i = 0; i < strlen(tag); i++) tag[i] = CharToUpper(tag[i]);
        if (this.targetName[0])
            Format(buffer, maxlen, "%s %s", tag, this.targetName);
        else
            strcopy(buffer, maxlen, tag);
    }
}

void PushEvent(GameEvent ev) {
    if (g_EventQueue.Length >= MAX_EVENT_QUEUE) return;
    DataPack pack = new DataPack();
    pack.WriteString(ev.eventType);
    pack.WriteString(ev.description);
    pack.WriteCell(ev.preferredBot);
    pack.WriteString(ev.weapon);
    pack.WriteString(ev.targetName);
    pack.WriteCell(ev.enemies);
    pack.WriteCell(ev.allies);
    pack.WriteFloat(GetGameTime());
    g_EventQueue.Push(pack);
}

bool PopEvent(GameEvent ev) {
    if (g_EventQueue.Length == 0) return false;
    DataPack pack = view_as<DataPack>(g_EventQueue.Get(0));
    g_EventQueue.Erase(0);
    pack.Reset();
    pack.ReadString(ev.eventType, sizeof(ev.eventType));
    pack.ReadString(ev.description, sizeof(ev.description));
    ev.preferredBot = pack.ReadCell();
    pack.ReadString(ev.weapon, sizeof(ev.weapon));
    pack.ReadString(ev.targetName, sizeof(ev.targetName));
    ev.enemies = pack.ReadCell();
    ev.allies = pack.ReadCell();
    float eventTime = pack.ReadFloat();
    delete pack;
    if (GetGameTime() - eventTime > 30.0) return false;
    return true;
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

int GetGameStateBonus() {
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
        if ((ht == 2 && tA == 1 && ctA >= 2) || (ht == 3 && ctA == 1 && tA >= 2)) { bonus += 25; break; }
    }
    return bonus;
}

int CalculateInterest(int base, const char[] weapon = "", int extra = 0) {
    int score = base + GetGameStateBonus() + extra;
    if (weapon[0]) {
        if (StrContains(weapon, "knife") != -1) score += 20;
        else if (StrContains(weapon, "awp") != -1) score += 10;
    }
    return score > 100 ? 100 : score < 0 ? 0 : score;
}

bool RollInterest(int base, const char[] weapon = "", int extra = 0) {
    return GetRandomInt(1, 100) <= CalculateInterest(base, weapon, extra);
}

void BuildFunfactContext(const char[] token, char[] buffer, int maxlen, int player, int data1, int data2) {
    char eventName[64];
    char clean[64]; strcopy(clean, sizeof(clean), token);
    if (clean[0] == '#') { int i = 0; while (clean[i + 1]) { clean[i] = clean[i + 1]; i++; } clean[i] = '\0'; }
    int start = 0;
    int under = StrContains(clean, "_");
    if (under != -1) {
        char prefix[32]; strcopy(prefix, sizeof(prefix), clean); prefix[under] = '\0';
        int j = 0; while (prefix[j]) { prefix[j] = CharToLower(prefix[j]); j++; } prefix[j] = '\0';
        if (StrEqual(prefix, "funfact")) start = under + 1;
    }
    int len = strlen(clean) - start;
    if (len >= sizeof(eventName)) len = sizeof(eventName) - 1;
    for (int i = 0; i < len; i++) eventName[i] = CharToUpper(clean[start + i]);
    eventName[len] = '\0';
    char pName[64];
    if (player > 0 && IsClientInGame(player)) GetClientName(player, pName, sizeof(pName)); else pName[0] = '\0';
    char d1Str[16], d2Str[16];
    IntToString(data1, d1Str, sizeof(d1Str));
    IntToString(data2, d2Str, sizeof(d2Str));
    if (data2 != 0) {
        if (pName[0]) Format(buffer, maxlen, "[EVENT: %s] [TARGET: %s] [VALUE1: %s] [VALUE2: %s]", eventName, pName, d1Str, d2Str);
        else Format(buffer, maxlen, "[EVENT: %s] [VALUE1: %s] [VALUE2: %s]", eventName, d1Str, d2Str);
    } else if (data1 != 0) {
        if (pName[0]) Format(buffer, maxlen, "[EVENT: %s] [TARGET: %s] [VALUE: %s]", eventName, pName, d1Str);
        else Format(buffer, maxlen, "[EVENT: %s] [VALUE: %s]", eventName, d1Str);
    } else {
        if (pName[0]) Format(buffer, maxlen, "[EVENT: %s] [TARGET: %s]", eventName, pName);
        else Format(buffer, maxlen, "[EVENT: %s]", eventName);
    }
}

void GetPlayerLocation(int client, char[] buffer, int maxlen) {
    if (client > 0 && IsClientInGame(client)) {
        char token[64]; GetEntPropString(client, Prop_Send, "m_szLastPlaceName", token, sizeof(token));
        if (token[0] != '\0') GetLocationName(token, buffer, maxlen); else buffer[0] = '\0';
    } else buffer[0] = '\0';
}

// ── Event Handlers ──
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    g_CurrentRound++; g_BombPlanted = 0.0;
    delete g_RoundStartTimer;
    g_RoundStartTimer = CreateTimer(3.0, Timer_RoundStartMsg, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundStartMsg(Handle timer) {
    g_RoundStartTimer = null;
    if (!RollInterest(IntBase_RoundStart)) return Plugin_Stop;
    GameEvent ev; ev.preferredBot = -1; strcopy(ev.eventType, sizeof(ev.eventType), "round_start");
    GetStr("events", g_CurrentRound > 1 ? "round_start" : "match_start", ev.description, sizeof(ev.description));
    PushEvent(ev);
    return Plugin_Stop;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    delete g_RoundStartTimer;
    int winner = event.GetInt("winner");
    if (!RollInterest(IntBase_RoundEnd)) return;
    GameEvent ev; ev.preferredBot = -1; strcopy(ev.eventType, sizeof(ev.eventType), "round_end");
    if (winner == 2) GetStr("events", "tr_win", ev.description, sizeof(ev.description));
    else if (winner == 3) GetStr("events", "ct_win", ev.description, sizeof(ev.description));
    else return;
    PushEvent(ev);
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast) {
    g_BombPlanted = GetGameTime();
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsFakeClient(client) && RollInterest(IntBase_BombPlant)) {
        char bp[64], ls[64], ctx[1024], loc[64];
        GetStr("events", "bomb_plant", bp, sizeof(bp));
        GetStr("events", "location_suffix", ls, sizeof(ls));
        GameEvent ev; strcopy(ev.eventType, sizeof(ev.eventType), "bomb_planted"); ev.preferredBot = client;
        GetPlayerLocation(client, loc, sizeof(loc));
        Format(ctx, sizeof(ctx), "[EVENT: BOMB_PLANTED]");
        if (loc[0]) Format(ctx, sizeof(ctx), "%s [LOCATION: %s]", ctx, loc);
        strcopy(ev.description, sizeof(ev.description), ctx);
        PushEvent(ev);
    }
}

public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast) {
    g_BombPlanted = 0.0;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsFakeClient(client) && RollInterest(IntBase_BombDefuse)) {
        char loc[64]; GameEvent ev; strcopy(ev.eventType, sizeof(ev.eventType), "bomb_defused"); ev.preferredBot = client;
        GetPlayerLocation(client, loc, sizeof(loc));
        Format(ev.description, sizeof(ev.description), "[EVENT: BOMB_DEFUSED]");
        if (loc[0]) Format(ev.description, sizeof(ev.description), "%s [LOCATION: %s]", ev.description, loc);
        PushEvent(ev);
    }
}

public void Event_WinPanel(Event event, const char[] name, bool dontBroadcast) {
    if (!RollInterest(IntBase_WinPanel)) return;
    char ff[128]; event.GetString("funfact_token", ff, sizeof(ff)); if (!ff[0]) return;
    int player = event.GetInt("funfact_player"), d1 = event.GetInt("funfact_data1"), d2 = event.GetInt("funfact_data2");
    char ctx[1024]; BuildFunfactContext(ff, ctx, sizeof(ctx), player, d1, d2);
    char pName[64];
    if (player > 0 && IsClientInGame(player)) GetClientName(player, pName, sizeof(pName)); else pName[0] = '\0';
    GameEvent ev; strcopy(ev.description, sizeof(ev.description), ctx); ev.preferredBot = (player > 0 && IsFakeClient(player)) ? player : -1; strcopy(ev.eventType, sizeof(ev.eventType), "funfact"); strcopy(ev.targetName, sizeof(ev.targetName), pName);
    PushEvent(ev);
}

public void Event_PlayerSay(Event event, const char[] name, bool dontBroadcast) {
    if (!RollInterest(IntBase_PlayerSay)) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || IsFakeClient(client) || IsClientSourceTV(client)) return;
    char text[128]; event.GetString("text", text, sizeof(text)); if (text[0] == '!' || text[0] == '/') return;
    char pName[32]; GetClientName(client, pName, sizeof(pName));
    GameEvent ev; strcopy(ev.description, sizeof(ev.description), text); ev.preferredBot = -1; strcopy(ev.eventType, sizeof(ev.eventType), "chat"); strcopy(ev.targetName, sizeof(ev.targetName), pName);
    PushEvent(ev);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
    if (!RollInterest(IntBase_FriendlyFire)) return;
    int atk = GetClientOfUserId(event.GetInt("attacker")), vic = GetClientOfUserId(event.GetInt("userid"));
    if (atk < 1 || vic < 1 || GetClientTeam(atk) != GetClientTeam(vic) || atk == vic) return;
    char wpn[32]; event.GetString("weapon", wpn, sizeof(wpn));
    if (!IsFakeClient(vic) && !IsFakeClient(atk)) return;
    int bot = IsFakeClient(vic) ? vic : atk;
    int human = IsFakeClient(vic) ? atk : vic;
    char hName[64]; if (human > 0 && IsClientInGame(human)) GetClientName(human, hName, sizeof(hName)); else hName[0] = '\0';
    char wBuf[32]; FriendlyWeaponName(wpn, wBuf, sizeof(wBuf));
    int hsP = StrContains(wBuf, " HS"); if (hsP != -1) wBuf[hsP] = '\0';
    GameEvent ev; strcopy(ev.eventType, sizeof(ev.eventType), "ff"); strcopy(ev.weapon, sizeof(ev.weapon), wpn); ev.preferredBot = bot;
    char tag[32];
    if (IsFakeClient(vic)) strcopy(tag, sizeof(tag), "FF_TAKEN");
    else strcopy(tag, sizeof(tag), "FF_GIVEN");
    Format(ev.description, sizeof(ev.description), "[EVENT: %s] [TARGET: %s] [WEAPON: %s]", tag, hName, wBuf);
    strcopy(ev.targetName, sizeof(ev.targetName), hName);
    PushEvent(ev);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
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
    char wBuf[32]; FriendlyWeaponName(wpn, wBuf, sizeof(wBuf));
    int hsP = StrContains(wBuf, " HS"); if (hsP != -1) wBuf[hsP] = '\0';
    char loc[64]; GetPlayerLocation(kil, loc, sizeof(loc));
    char humanName[64];
    if (IsFakeClient(kil) && vic > 0 && IsClientInGame(vic)) GetClientName(vic, humanName, sizeof(humanName));
    else if (IsFakeClient(vic) && kil > 0 && IsClientInGame(kil)) GetClientName(kil, humanName, sizeof(humanName));
    else humanName[0] = '\0';
    char evTag[32], evType[32], ctx[1024];
    if (event.GetInt("revenge")) { strcopy(evTag, sizeof(evTag), "REVENGE"); strcopy(evType, sizeof(evType), "revenge"); }
    else if (event.GetInt("dominated")) { strcopy(evTag, sizeof(evTag), "DOMINATING"); strcopy(evType, sizeof(evType), "dominating"); }
    else if (IsFakeClient(kil)) { strcopy(evTag, sizeof(evTag), "KILLED"); strcopy(evType, sizeof(evType), "kill"); }
    else { strcopy(evTag, sizeof(evTag), "DIED"); strcopy(evType, sizeof(evType), "death"); }
    if (loc[0]) Format(ctx, sizeof(ctx), "[EVENT: %s] [TARGET: %s] [WEAPON: %s] [LOCATION: %s]", evTag, humanName, wBuf, loc);
    else Format(ctx, sizeof(ctx), "[EVENT: %s] [TARGET: %s] [WEAPON: %s]", evTag, humanName, wBuf);
    GameEvent ev; strcopy(ev.weapon, sizeof(ev.weapon), wpn); strcopy(ev.eventType, sizeof(ev.eventType), evType);
    strcopy(ev.description, sizeof(ev.description), ctx); strcopy(ev.targetName, sizeof(ev.targetName), humanName);
    ev.preferredBot = IsFakeClient(kil) ? kil : vic;
    PushEvent(ev);
}
