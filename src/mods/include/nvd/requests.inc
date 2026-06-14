#if defined _nvd_requests_included
#endinput
#endif
#define _nvd_requests_included

void RecordEvent(const char[] description) {
    if (description[0] == '\0') return;
    strcopy(g_History[g_HistIdx].role, 32, "system");
    strcopy(g_History[g_HistIdx].content, HISTORY_CONTENT_LEN, description);
    g_HistIdx = (g_HistIdx + 1) % MAX_HISTORY_ENTRIES;
    if (g_HistCount < MAX_HISTORY_ENTRIES) g_HistCount++;
}

void RecordBotMessage(const char[] botName, const char[] message) {
    if (message[0] == '\0') return;
    int insertAfter = -1;
    int idx = (g_HistIdx - 1 + MAX_HISTORY_ENTRIES) % MAX_HISTORY_ENTRIES;
    for (int i = 0; i < g_HistCount && i < MAX_HISTORY_ENTRIES; i++) {
        if (StrEqual(g_History[idx].role, "system")) {
            int nidx = (idx + 1) % MAX_HISTORY_ENTRIES;
            if (g_History[nidx].content[0] == '\0' || StrEqual(g_History[nidx].role, "system")) {
                insertAfter = idx;
                break;
            }
        }
        idx = (idx - 1 + MAX_HISTORY_ENTRIES) % MAX_HISTORY_ENTRIES;
    }
    if (insertAfter == -1) {
        strcopy(g_History[g_HistIdx].role, 32, botName);
        strcopy(g_History[g_HistIdx].content, HISTORY_CONTENT_LEN, message);
        g_HistIdx = (g_HistIdx + 1) % MAX_HISTORY_ENTRIES;
        if (g_HistCount < MAX_HISTORY_ENTRIES) g_HistCount++;
        return;
    }
    HistoryEntry temp[MAX_HISTORY_ENTRIES];
    int tCount = 0;
    int oldest = (g_HistIdx - g_HistCount + MAX_HISTORY_ENTRIES) % MAX_HISTORY_ENTRIES;
    for (int i = 0; i < g_HistCount && i < MAX_HISTORY_ENTRIES; i++) {
        int srcIdx = (oldest + i) % MAX_HISTORY_ENTRIES;
        if (g_History[srcIdx].content[0] != '\0') { temp[tCount] = g_History[srcIdx]; tCount++; }
    }
    int tempInsert = -1;
    for (int i = 0; i < tCount; i++) {
        if (StrEqual(temp[i].role, "system") && (i + 1 >= tCount || !StrEqual(temp[i+1].role, "system")))
            { tempInsert = i; break; }
    }
    if (tempInsert == -1) { tempInsert = tCount; }
    for (int i = tCount; i > tempInsert + 1; i--) temp[i] = temp[i - 1];
    tempInsert++;
    strcopy(temp[tempInsert].role, 32, botName);
    strcopy(temp[tempInsert].content, HISTORY_CONTENT_LEN, message);
    tCount++; if (tCount > MAX_HISTORY_ENTRIES) tCount = MAX_HISTORY_ENTRIES;
    for (int i = 0; i < tCount; i++) g_History[i] = temp[i];
    for (int i = tCount; i < MAX_HISTORY_ENTRIES; i++) g_History[i].content[0] = '\0';
    g_HistIdx = tCount % MAX_HISTORY_ENTRIES;
    g_HistCount = tCount;
}

void EscapeJSON(const char[] input, char[] output, int maxlen) {
    int ep = 0;
    for (int c = 0; input[c] != '\0' && ep < maxlen - 4; c++) {
        if (input[c] == '"') { output[ep++] = '\\'; output[ep++] = '"'; }
        else if (input[c] == '\\') { output[ep++] = '\\'; output[ep++] = '\\'; }
        else output[ep++] = input[c];
    }
    output[ep] = '\0';
}

void BuildHistoryBlock(char[] buffer, int maxlen, const char[] catchphrase = "") {
    buffer[0] = '\0';
    int pos = 0;
    pos += Format(buffer[pos], maxlen - pos, "[");
    bool first = true;
    static const int MAX_REAL_HISTORY = 3;
    if (g_HistCount > 0) {
        int take = g_HistCount > MAX_REAL_HISTORY ? MAX_REAL_HISTORY : g_HistCount;
        int start = (g_HistIdx - take + MAX_HISTORY_ENTRIES) % MAX_HISTORY_ENTRIES;
        for (int i = 0; i < take; i++) {
            int idx = (start + i) % MAX_HISTORY_ENTRIES;
            if (g_History[idx].content[0] == '\0') continue;
            char escaped[512], role[32], content[HISTORY_CONTENT_LEN + 64];
            EscapeJSON(g_History[idx].content, escaped, sizeof(escaped));
            if (StrEqual(g_History[idx].role, "system")) {
                Format(content, sizeof(content), "Event: %s", escaped);
                strcopy(role, sizeof(role), "system");
            } else {
                strcopy(role, sizeof(role), "assistant");
                Format(content, sizeof(content), "@%s: %s", g_History[idx].role, escaped);
            }
            if (!first) pos += Format(buffer[pos], maxlen - pos, ",");
            pos += Format(buffer[pos], maxlen - pos, "{\"role\":\"%s\",\"content\":\"%s\"}", role, content);
            first = false;
        }
    } else {
        char phrases[3][64]; int pCount = 0;
        if (catchphrase[0]) pCount = ExplodeString(catchphrase, ";", phrases, 3, 64);
        if (pCount == 0) { strcopy(phrases[0], sizeof(phrases[]), "ez"); pCount = 1; }
        pos += Format(buffer[pos], maxlen - pos, "{\"role\":\"user\",\"content\":\"Round start.\"},{\"role\":\"assistant\",\"content\":\"%s\"}", phrases[0]);
    }
    pos += Format(buffer[pos], maxlen - pos, "]");
}

void AskBotChat(GameEvent ev) {
    int bot;
    if (ev.preferredBot >= 1 && ev.preferredBot <= MaxClients && IsClientInGame(ev.preferredBot) && IsFakeClient(ev.preferredBot))
        bot = ev.preferredBot;
    else {
        int bots[MAXPLAYERS+1], bCnt = 0;
        for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) bots[bCnt++] = i;
        if (!bCnt) return; bot = bots[GetRandomInt(0, bCnt - 1)];
    }

    char type[32]; strcopy(type, sizeof(type), ev.eventType);
    if (StrEqual(type, "default")) {
        if (StrContains(ev.description, "eliminated") != -1 || StrContains(ev.description, "eliminou") != -1) strcopy(type, sizeof(type), "kill");
        else if (StrContains(ev.description, "was eliminated") != -1 || StrContains(ev.description, "foi eliminado") != -1) strcopy(type, sizeof(type), "death");
    }

    char target[32];
    if (ev.targetName[0]) strcopy(target, sizeof(target), ev.targetName);
    else target[0] = '\0';

    char wBuf[32];
    if (ev.weapon[0]) { FriendlyWeaponName(ev.weapon, wBuf, sizeof(wBuf)); int hsP = StrContains(wBuf, " HS"); if (hsP != -1) wBuf[hsP] = '\0'; }
    else GetStr("misc", "unknown_weapon", wBuf, sizeof(wBuf));

    int tS = CS_GetTeamScore(2), ctS = CS_GetTeamScore(3);
    char catchphrase[64], pers[8], sty[8], beh[8];
    char bName[32]; GetClientName(bot, bName, sizeof(bName));
    GetBotPersonality(bName, pers, sizeof(pers), catchphrase, sizeof(catchphrase), sty, sizeof(sty), beh, sizeof(beh));
    char cpFormatted[128];
    char parts[3][32]; int n = ExplodeString(catchphrase, ";", parts, 3, 32);
    for (int i = 0; i < n; i++) { TrimString(parts[i]); if (parts[i][0]) { if (i > 0) StrCat(cpFormatted, sizeof(cpFormatted), " "); Format(cpFormatted, sizeof(cpFormatted), "%s\"%s\"", cpFormatted, parts[i]); } }

    JSONObject ctx = new JSONObject();
    ctx.SetString("type", type);
    ctx.SetString("description", ev.description);
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
    if (GetRandomInt(1, 100) > 30) {
        for (int i = 0; i < g_BotCache[bot].count; i++) {
            if (g_BotCache[bot].entries[i].enemies == ev.enemies && g_BotCache[bot].entries[i].allies == ev.allies) {
                cachedIdx = i;
                break;
            }
        }
    }
    if (cachedIdx != -1) {
        char clean[320];
        strcopy(clean, sizeof(clean), g_BotCache[bot].entries[cachedIdx].response);
        ReplaceString(clean, 320, "\"", ""); ReplaceString(clean, 320, "[", ""); ReplaceString(clean, 320, "]", ""); TrimString(clean);
        if (clean[0]) {
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

public void CacheOnlyResponse(const char[] reply, any bot) {
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

void PollBotResponses() {
    char reply[2048]; any bot; char ts[32]; FormatTime(ts, sizeof(ts), "%H:%M:%S");
    while (NVD_PollResponse(reply, sizeof(reply), bot)) {
        if (bot == 0 || !IsClientInGame(bot) || !IsFakeClient(bot)) {
            int aB[MAXPLAYERS+1], aBC = 0;
            for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i)) aB[aBC++] = i;
            if (!aBC) continue; bot = aB[GetRandomInt(0, aBC-1)];
        }
        if (StrContains(reply, "ERROR_") != -1 || !reply[0]) {
            if (g_BotCache[bot].count > 0) {
                int ci = g_BotCache[bot].count - 1;
                strcopy(reply, sizeof(reply), g_BotCache[bot].entries[ci].response);
            } else { continue; }
        }
        char bName[32], clean[320]; GetClientName(bot, bName, sizeof(bName)); strcopy(clean, sizeof(clean), reply);
        ReplaceString(clean, 320, "\"", ""); ReplaceString(clean, 320, "[", ""); ReplaceString(clean, 320, "]", ""); TrimString(clean);
        if (!clean[0]) {
            if (g_BotCache[bot].count > 0) {
                int ci = g_BotCache[bot].count - 1;
                strcopy(clean, sizeof(clean), g_BotCache[bot].entries[ci].response);
            } else { continue; }
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
