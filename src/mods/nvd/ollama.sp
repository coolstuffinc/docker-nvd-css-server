#include <sourcemod>
#include <ripext>
#include <nvd/core>
#include <nvd/strings>
#undef REQUIRE_PLUGIN
#include <nvd_bot_chat>

#pragma semicolon 1
#pragma newdecls required

// ── Polling-based response queue ──
ArrayList g_PendingResponses = null;

#define MAX_RESPONSE_QUEUE 64
#define RESPONSE_TTL 60.0

// Enfileira a resposta armazenando o nome do plugin dono
stock void QueueResponse(const char[] ownerName, const char[] reply, any cbData)
{
	char ts[32];
	FormatTime(ts, sizeof(ts), "%H:%M:%S");

	if (g_PendingResponses == null)
		g_PendingResponses = new ArrayList();

	if (g_PendingResponses.Length >= MAX_RESPONSE_QUEUE)
	{
		DataPack oldest = view_as<DataPack>(g_PendingResponses.Get(0));
		delete oldest;
		g_PendingResponses.Erase(0);
		PrintToServer("[NVD] [%s] ⚠️ Response queue full, dropped oldest", ts);
	}

	DataPack pack = new DataPack();
	pack.WriteString(ownerName);
	pack.WriteCell(cbData);
	pack.WriteFloat(GetGameTime());
	pack.WriteString(reply);
	pack.Reset();
	g_PendingResponses.Push(pack);

	PrintToServer("[NVD] [%s] 📨 Response queued (%d pending) for %s: \"%s\"", ts, g_PendingResponses.Length, ownerName, reply);
}

enum OllamaRequestState
{
	ReqState_Queued,
	ReqState_Processing,
	ReqState_Fulfilled,
	ReqState_Failed
}

enum struct OllamaRequest
{
	Function callback;
	any callbackData;
	char ownerName[128]; // Aumentado para 128
	Handle plugin;
	char playerName[64]; // Aumentado para 64
	int playerId;
	int requestId;
	float requestTime;
	float timeout;
	char retryUrl[256];
	char retryBody[4096];
	char prompt[256];
	char response[512];
	int retries;
	OllamaRequestState state;

	char origPrompt[512];
	char origSystem[2048];
	char origModel[64];
	char origEndpoint[32];
	char origHistory[2048];
	char origContext[1024];

	float duration;
}


#define MAX_REQUESTS 64
OllamaRequest g_Requests[MAX_REQUESTS];

// ── Rate Limiting ──
#define RATE_LIMIT_WINDOW 5.0
#define MAX_REQUESTS_PER_WINDOW 3
int g_PlayerRequestCount[MAXPLAYERS + 1];
float g_WindowStart[MAXPLAYERS + 1];

#define MAX_OLLAMA_HISTORY 10
OllamaRequest g_OllamaHistory[MAX_OLLAMA_HISTORY];
int g_OllamaHistoryIdx = 0;
int g_OllamaHistoryCount = 0;

ConVar g_IpCvar, g_PortCvar, g_ModelCvar, g_EndpointCvar;
ConVar g_ConcurrencyCvar, g_MaxPendingCvar, g_MaxRetriesCvar;
char g_BaseUrl[256];
bool g_WarmupDone;

// ── REQUEST QUEUE ──
ArrayList g_RequestQueue;
int g_NextRequestId = 1;

public Plugin myinfo = { name = "NVD Ollama Core", author = "OpenCode", description = "Ollama AI bridge with queue", version = "2.2.1-DEBUG" };

// Shared _meta template snippets
char g_MetaKeys[32][64];
char g_MetaValues[32][1024];
int g_MetaCount = 0;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("nvd_core");
	CreateNative("NVD_AskAI", Native_AskAI);
	CreateNative("NVD_CanRequest", Native_CanRequest);
	CreateNative("NVD_PollResponse", Native_PollResponse);
	CreateNative("NVD_SetMeta", Native_SetMeta);
	return APLRes_Success;
}

public int Native_SetMeta(Handle plugin, int numParams)
{
	char key[64], value[1024];
	GetNativeString(1, key, sizeof(key));
	GetNativeString(2, value, sizeof(value));

	for (int i = 0; i < g_MetaCount; i++) {
		if (StrEqual(g_MetaKeys[i], key)) {
			strcopy(g_MetaValues[i], sizeof(g_MetaValues[]), value);
			return 0;
		}
	}

	if (g_MetaCount < 32) {
		strcopy(g_MetaKeys[g_MetaCount], sizeof(g_MetaKeys[]), key);
		strcopy(g_MetaValues[g_MetaCount], sizeof(g_MetaValues[]), value);
		g_MetaCount++;
	}
	return 0;
}

void ProcessTemplates(char[] buffer, int maxlen)
{
	char mapName[64]; GetCurrentMap(mapName, sizeof(mapName));
	ReplaceString(buffer, maxlen, "|map|", mapName);

	char hostname[128]; ConVar hHost = FindConVar("hostname");
	if (hHost != null) hHost.GetString(hostname, sizeof(hostname));
	ReplaceString(buffer, maxlen, "|hostname|", hostname);

	char timeStr[32]; FormatTime(timeStr, sizeof(timeStr), "%H:%M:%S");
	ReplaceString(buffer, maxlen, "|time|", timeStr);

	char dateStr[32]; FormatTime(dateStr, sizeof(dateStr), "%Y-%m-%d");
	ReplaceString(buffer, maxlen, "|date|", dateStr);
    
    char lang[32], promptLang[32];
    ConVar hLang = FindConVar("nvd_language");
    ConVar hPromptLang = FindConVar("nvd_prompt_language");
    if(hLang != null) hLang.GetString(lang, sizeof(lang)); else strcopy(lang, sizeof(lang), "default");
    if(hPromptLang != null) hPromptLang.GetString(promptLang, sizeof(promptLang)); else strcopy(promptLang, sizeof(promptLang), "default");
    ReplaceString(buffer, maxlen, "|server_lang|", lang);
    ReplaceString(buffer, maxlen, "|prompt_lang|", promptLang);

	for (int i = 0; i < g_MetaCount; i++) {
		char placeholder[68], fullPath[128], val[1024]; Format(placeholder, sizeof(placeholder), "|%s|", g_MetaKeys[i]);
        Format(fullPath, sizeof(fullPath), "nvd.bot_chat.behavior.%s", g_MetaKeys[i]);
        if (NVD_HasStr(fullPath)) {
            NVD_GetStr(fullPath, val, sizeof(val));
            ReplaceString(buffer, maxlen, placeholder, val);
        }
	}
}

public void OnPluginStart()
{
	g_IpCvar = CreateConVar("nvd_ollama_ip", "172.17.0.1");
	g_PortCvar = CreateConVar("nvd_ollama_port", "11433");
	g_ModelCvar = CreateConVar("nvd_ollama_model", "qwen2.5:1.5b");
	g_EndpointCvar = CreateConVar("nvd_ollama_endpoint", "chat");
	g_ConcurrencyCvar = CreateConVar("nvd_ollama_concurrency", "3");
	g_MaxPendingCvar = CreateConVar("nvd_ollama_max_pending", "16");
	g_MaxRetriesCvar = CreateConVar("nvd_ollama_max_retries", "3");

	RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK);
	RegAdminCmd("sm_ollama_status", Command_OllamaStatus, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ollama_reload", Command_OllamaReload, ADMFLAG_KICK);
	RegAdminCmd("sm_ollama_history", Command_OllamaHistory, ADMFLAG_GENERIC);

	for (int i = 0; i < MAX_REQUESTS; i++) g_Requests[i].state = ReqState_Queued;
	g_RequestQueue = new ArrayList();

	CreateTimer(15.0, Timer_CleanupQueue, _, TIMER_REPEAT);
	CreateTimer(5.0, Timer_CleanupStaleSlots, _, TIMER_REPEAT);

	InitBaseUrl();
}

void InitBaseUrl()
{
	char ip[64], port[16];
	if (g_IpCvar == null) return;
	g_IpCvar.GetString(ip, sizeof(ip)); g_PortCvar.GetString(port, sizeof(port));
	Format(g_BaseUrl, sizeof(g_BaseUrl), "http://%s:%s", ip, port);
	g_WarmupDone = false;
	WarmupModel();
}

int GetMaxPending()
{
	int v = g_MaxPendingCvar.IntValue;
	return (v < 4) ? 4 : (v > MAX_REQUESTS ? MAX_REQUESTS : v);
}

public Action Timer_CleanupStaleSlots(Handle timer)
{
	int maxSlots = GetMaxPending();
	for (int i = 0; i < maxSlots; i++) {
		if (g_Requests[i].state != ReqState_Processing) continue;
		float elapsed = GetGameTime() - g_Requests[i].requestTime;
		if (elapsed > 300.0 || (g_Requests[i].timeout > 0.0 && elapsed >= g_Requests[i].timeout)) {
			g_Requests[i].state = ReqState_Failed;
			RecordOllamaHistory(i);
			Function cb; any data; Handle plugin; char ownerName[64];
			FreeSlot(i, cb, data, plugin, ownerName);
			QueueResponse(ownerName, "ERROR_TIMEOUT", data);
		}
	}
	return Plugin_Continue;
}

public void OnMapEnd()
{
	if (g_RequestQueue != null) {
		for (int i = 0; i < g_RequestQueue.Length; i++) {
			DataPack pack = view_as<DataPack>(g_RequestQueue.Get(i)); delete pack;
		}
		g_RequestQueue.Clear();
	}
	if (g_PendingResponses != null) {
		for (int i = 0; i < g_PendingResponses.Length; i++) {
			DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i)); delete pack;
		}
		g_PendingResponses.Clear();
	}
	for (int i = 0; i < GetMaxPending(); i++) {
		if (g_Requests[i].state == ReqState_Processing) {
			g_Requests[i].state = ReqState_Failed;
			RecordOllamaHistory(i);
			g_Requests[i].state = ReqState_Queued;
		}
	}
}

public Action Timer_CleanupQueue(Handle timer)
{
	if (g_PendingResponses == null || g_PendingResponses.Length == 0) return Plugin_Continue;
	float now = GetGameTime();
	char dummy[64];
	for (int i = g_PendingResponses.Length - 1; i >= 0; i--) {
		DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i)); pack.Reset();
		pack.ReadString(dummy, 64); pack.ReadCell();
		if (now - pack.ReadFloat() > RESPONSE_TTL) { g_PendingResponses.Erase(i); delete pack; }
	}
	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
	InitBaseUrl();
}

void BuildApiUrl(char[] url, int maxlen)
{
    char endpoint[32]; g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    if (StrContains(endpoint, "/") != -1) Format(url, maxlen, "%s", endpoint);
    else Format(url, maxlen, "/api/%s", endpoint);
}

void WarmupModel()
{
	char model[64]; g_ModelCvar.GetString(model, sizeof(model));
	JSONObject payload = new JSONObject(); payload.SetString("model", model); payload.SetBool("stream", false);
	JSONArray msgs = new JSONArray();
	JSONObject sys = new JSONObject(); sys.SetString("role", "system"); sys.SetString("content", "Be brief."); msgs.Push(sys); delete sys;
	JSONObject usr = new JSONObject(); usr.SetString("role", "user"); usr.SetString("content", "ping"); msgs.Push(usr); delete usr;
	payload.Set("messages", msgs); delete msgs;
	JSONObject warmupOpts = new JSONObject(); warmupOpts.SetString("keep_alive", "10m");
	payload.Set("options", warmupOpts); delete warmupOpts;
	char ep[32]; BuildApiUrl(ep, sizeof(ep));
	char fullUrl[256]; Format(fullUrl, sizeof(fullUrl), "%s%s", g_BaseUrl, ep);
	PrintToServer("[NVD] 🔄 Warming up %s at %s...", model, fullUrl);
	HTTPRequest req = new HTTPRequest(fullUrl);
	req.SetHeader("Content-Type", "application/json");
	req.Timeout = 120;
	req.Post(payload, OnWarmupResponse, 0);
	delete payload;
}

public void OnWarmupResponse(HTTPResponse response, any data) {
	g_WarmupDone = true;
	if (response.Status == HTTPStatus_OK) PrintToServer("[NVD] ✅ Warmup OK");
	else PrintToServer("[NVD] ❌ Warmup HTTP %d", response.Status);
	ProcessQueue();
}

public Action Command_OllamaTest(int client, int args) { TestConnection(client); return Plugin_Handled; }

void TestConnection(int client)
{
	char model[64]; g_ModelCvar.GetString(model, sizeof(model));
	JSONObject payload = new JSONObject(); payload.SetString("model", model); payload.SetBool("stream", false);
	JSONArray messages = new JSONArray();
	JSONObject userMsg = new JSONObject(); userMsg.SetString("role", "user"); userMsg.SetString("content", "ping"); messages.Push(userMsg); delete userMsg;
	payload.Set("messages", messages); delete messages;
	DataPack pack = new DataPack(); pack.WriteCell(client);
	char ep[32]; BuildApiUrl(ep, sizeof(ep));
	char fullUrl[256]; Format(fullUrl, sizeof(fullUrl), "%s%s", g_BaseUrl, ep);
	HTTPRequest req = new HTTPRequest(fullUrl);
	req.SetHeader("Content-Type", "application/json");
	req.Timeout = 30;
	req.Post(payload, OnTestResponse, pack);
	delete payload;
}

public void OnTestResponse(HTTPResponse response, DataPack pack)
{
	pack.Reset(); int client = pack.ReadCell(); delete pack;
	if (client > 0 && !IsClientInGame(client)) return;
	if (response.Status == HTTPStatus_OK) ReplyToCommand(client, "[NVD] ✅ Ollama OK");
	else ReplyToCommand(client, "[NVD] ❌ Ollama error: HTTP %d", response.Status);
}

void RecordOllamaHistory(int slot)
{
	int idx = g_OllamaHistoryIdx;
	g_OllamaHistory[idx] = g_Requests[slot];
	g_OllamaHistory[idx].duration = GetGameTime() - g_Requests[slot].requestTime;
	g_OllamaHistory[idx].state = g_Requests[slot].state;
	g_OllamaHistoryIdx = (g_OllamaHistoryIdx + 1) % MAX_OLLAMA_HISTORY;
	if (g_OllamaHistoryCount < MAX_OLLAMA_HISTORY) g_OllamaHistoryCount++;
}

	public Action Command_OllamaHistory(int client, int args)
	{
		ReplyToCommand(client, "[NVD] ═══ History (Last %d) ═══", g_OllamaHistoryCount);
		for (int i = 0; i < g_OllamaHistoryCount; i++) {
			int idx = (g_OllamaHistoryIdx - g_OllamaHistoryCount + i + MAX_OLLAMA_HISTORY) % MAX_OLLAMA_HISTORY;
			char pBuf[256];
			strcopy(pBuf, sizeof(pBuf), g_OllamaHistory[idx].prompt[0] ? g_OllamaHistory[idx].prompt : g_OllamaHistory[idx].origPrompt);
			ReplyToCommand(client, "[NVD] #%d | %s | %s | %s", i + 1, g_OllamaHistory[idx].state == ReqState_Fulfilled ? "✅" : "❌", g_OllamaHistory[idx].ownerName, pBuf);
			if (g_OllamaHistory[idx].state == ReqState_Fulfilled) {
				ReplyToCommand(client, "[NVD]     Res: %s", g_OllamaHistory[idx].response);
			}
		}
		return Plugin_Handled;
	}

public Action Command_OllamaStatus(int client, int args)
{
	char argId[32]; int targetId = -1;
	if (args >= 1) {
		GetCmdArg(1, argId, sizeof(argId));
		if (argId[0] == 'H' || argId[0] == 'h') {
			targetId = StringToInt(argId[1]);
		} else if (argId[0] == 'T' || argId[0] == 't') {
			targetId = StringToInt(argId[1]);
		} else if (argId[0] == '#') {
			targetId = StringToInt(argId[1]);
		} else if (argId[0] == '@') {
			targetId = StringToInt(argId[1]);
		} else if (argId[0] == '~') {
			targetId = StringToInt(argId[1]);
		}
	}

	if (targetId >= 0) {
		// Lookup entry by ID
		char prefix = argId[0];
		bool isHistory = (prefix == 'H' || prefix == 'h');

		// Active slots and waiting queue (T/#/@/~ prefix or bare int)
		if (!isHistory) {
			int maxSlots = GetMaxPending();
			for (int i = 0; i < maxSlots; i++) {
				if (g_Requests[i].state != ReqState_Processing) continue;
				if (g_Requests[i].requestId == targetId) {
					ReplyToCommand(client, "[NVD] ═══ Entry T%d (active slot %d) ═══", targetId, i);
					ReplyToCommand(client, "[NVD] Owner: %s", g_Requests[i].ownerName);
					ReplyToCommand(client, "[NVD] Bot: %s", g_Requests[i].playerName[0] ? g_Requests[i].playerName : "none");
					float elapsed = GetGameTime() - g_Requests[i].requestTime;
					ReplyToCommand(client, "[NVD] Elapsed: %.1fs / Timeout: %.0fs", elapsed, g_Requests[i].timeout);
					ReplyToCommand(client, "[NVD] Retries: %d", g_Requests[i].retries);
					ReplyToCommand(client, "[NVD] Prompt: %s", g_Requests[i].prompt[0] ? g_Requests[i].prompt : "(lazy-built from template)");
					ReplyToCommand(client, "[NVD] System: %s", g_Requests[i].origSystem[0] ? g_Requests[i].origSystem : "(lazy-built from template)");
					if (g_Requests[i].response[0])
						ReplyToCommand(client, "[NVD] Response: %s", g_Requests[i].response);
					if (g_Requests[i].origHistory[0])
						ReplyToCommand(client, "[NVD] History: %s", g_Requests[i].origHistory);
					return Plugin_Handled;
				}
			}
			for (int i = 0; i < g_RequestQueue.Length; i++) {
				DataPack pack = view_as<DataPack>(g_RequestQueue.Get(i)); pack.Reset();
				Handle ownerPlugin; Function cb; any cbData;
				char prompt[512], system[2048], model[64], endpoint[32], ownerName[64], historyJSON[2048], playerName[32], contextJSON[1024];
				float timeout, startTime; int retries, id, pid;
				UnpackRequest(pack, ownerPlugin, cb, cbData, prompt, sizeof(prompt), system, sizeof(system), model, sizeof(model), endpoint, sizeof(endpoint), ownerName, sizeof(ownerName), historyJSON, sizeof(historyJSON), playerName, sizeof(playerName), timeout, retries, startTime, id, pid, contextJSON, 1024);
				if (id == targetId) {
					ReplyToCommand(client, "[NVD] ═══ Entry T%d (queue #%d) ═══", id, i+1);
					ReplyToCommand(client, "[NVD] Owner: %s", ownerName);
					if (playerName[0]) ReplyToCommand(client, "[NVD] Bot: %s", playerName);
					// Show display version from context if available
					if (contextJSON[0] != '\0' && GetFeatureStatus(FeatureType_Native, "NVD_BuildPrompts") == FeatureStatus_Available) {
						char sysP[2048], fullP[1024];
						NVD_BuildPrompts(contextJSON, "user", pid, sysP, sizeof(sysP), fullP, sizeof(fullP));
						ReplyToCommand(client, "[NVD] Prompt: %s", fullP);
					} else {
						ReplyToCommand(client, "[NVD] Prompt: %s", prompt);
					}
					ReplyToCommand(client, "[NVD] System: %s", system);
					ReplyToCommand(client, "[NVD] Timeout: %.0f", timeout);
					if (historyJSON[0]) ReplyToCommand(client, "[NVD] History: %s", historyJSON);
					return Plugin_Handled;
				}
			}
		}

		// History (H prefix)
		for (int i = 0; i < g_OllamaHistoryCount; i++) {
			int idx = (g_OllamaHistoryIdx - g_OllamaHistoryCount + i + MAX_OLLAMA_HISTORY) % MAX_OLLAMA_HISTORY;
			if (i == targetId) {
				ReplyToCommand(client, "[NVD] ═══ History H%d ═══", i);
				ReplyToCommand(client, "[NVD] Owner: %s", g_OllamaHistory[idx].ownerName);
				if (g_OllamaHistory[idx].playerName[0])
					ReplyToCommand(client, "[NVD] Bot: %s", g_OllamaHistory[idx].playerName);
				ReplyToCommand(client, "[NVD] Duration: %.1fs / Timeout: %.0fs", g_OllamaHistory[idx].duration, g_OllamaHistory[idx].timeout);
				ReplyToCommand(client, "[NVD] Retries: %d", g_OllamaHistory[idx].retries);
				ReplyToCommand(client, "[NVD] %s", g_OllamaHistory[idx].state == ReqState_Fulfilled ? "✅ Success" : "❌ Failed");
				char pBuf[512];
				strcopy(pBuf, sizeof(pBuf), g_OllamaHistory[idx].prompt[0] ? g_OllamaHistory[idx].prompt : g_OllamaHistory[idx].origPrompt);
				ReplyToCommand(client, "[NVD] Prompt: %s", pBuf);
				ReplyToCommand(client, "[NVD] System: %s", g_OllamaHistory[idx].origSystem[0] ? g_OllamaHistory[idx].origSystem : "(lazy)");
				if (g_OllamaHistory[idx].state == ReqState_Fulfilled)
					ReplyToCommand(client, "[NVD] Response: %s", g_OllamaHistory[idx].response);
				return Plugin_Handled;
			}
		}
		ReplyToCommand(client, "[NVD] ❌ Entry %c%d not found", prefix, targetId);
		return Plugin_Handled;
	}

	ReplyToCommand(client, "[NVD] ═══ Status ═══");
	int used = 0; for (int i = 0; i < GetMaxPending(); i++) if (g_Requests[i].state == ReqState_Processing) used++;
	ReplyToCommand(client, "[NVD] Active: %d | Waiting: %d", used, g_RequestQueue.Length);

	if (used > 0) {
		char payloadSize[16];
		for (int i = 0; i < GetMaxPending(); i++) {
			if (g_Requests[i].state != ReqState_Processing) continue;
			float elapsed = GetGameTime() - g_Requests[i].requestTime;
			int id = g_Requests[i].requestId;
			int pSize = strlen(g_Requests[i].retryBody);
			if (pSize > 1024) Format(payloadSize, sizeof(payloadSize), "%.1fkb", pSize / 1024.0); else Format(payloadSize, sizeof(payloadSize), "%db", pSize);
			char cleanOwner[64]; strcopy(cleanOwner, sizeof(cleanOwner), g_Requests[i].ownerName);
			ReplaceString(cleanOwner, sizeof(cleanOwner), ".smx", "");
			
			char dispBuf[512];
			if (g_Requests[i].origContext[0] != '\0' && 
			    GetFeatureStatus(FeatureType_Native, "NVD_BuildPrompts") == FeatureStatus_Available) {
				char sysP[2048], fullP[1024];
				NVD_BuildPrompts(g_Requests[i].origContext, "user", g_Requests[i].playerId,
				    sysP, sizeof(sysP), fullP, sizeof(fullP));
				strcopy(dispBuf, sizeof(dispBuf), fullP);
			} else {
				strcopy(dispBuf, sizeof(dispBuf), g_Requests[i].prompt[0] ? g_Requests[i].prompt : g_Requests[i].origPrompt);
			}
			
			if (strlen(dispBuf) > 60) {
                int cut = 60;
                // Se o byte em 'cut' for um byte de continuação UTF-8 (10xxxxxx), recua até achar o início
                while (cut > 0 && (dispBuf[cut] & 0xC0) == 0x80) cut--;
                
                dispBuf[cut] = '\0';
                strcopy(dispBuf[cut-3], 4, "...");
            }
			ReplaceString(dispBuf, sizeof(dispBuf), "\n", " ");
			
			if (g_Requests[i].playerName[0])
				ReplyToCommand(client, "[NVD]   T%d Slot %d [%s](%s) %.1fs/%.0fs %s | %s", id, i, cleanOwner, g_Requests[i].playerName, elapsed, g_Requests[i].timeout, payloadSize, dispBuf);
			else
				ReplyToCommand(client, "[NVD]   T%d Slot %d [%s] %.1fs/%.0fs %s | %s", id, i, cleanOwner, elapsed, g_Requests[i].timeout, payloadSize, dispBuf);
		}
	}

	if (g_OllamaHistoryCount > 0) {
		ReplyToCommand(client, "[NVD] ── Recent History ──");
		int show = g_OllamaHistoryCount < 5 ? g_OllamaHistoryCount : 5;
		char truncPrompt[128], truncRes[128];
		for (int i = 0; i < show; i++) {
			int idx = (g_OllamaHistoryIdx - g_OllamaHistoryCount + i + MAX_OLLAMA_HISTORY) % MAX_OLLAMA_HISTORY;
			strcopy(truncPrompt, sizeof(truncPrompt), g_OllamaHistory[idx].prompt[0] ? g_OllamaHistory[idx].prompt : g_OllamaHistory[idx].origPrompt);
			if (strlen(truncPrompt) > 80) { truncPrompt[80] = '\0'; strcopy(truncPrompt[77], 4, "..."); }
			ReplaceString(truncPrompt, sizeof(truncPrompt), "\n", " ");
			if (g_OllamaHistory[idx].state == ReqState_Fulfilled) {
				strcopy(truncRes, sizeof(truncRes), g_OllamaHistory[idx].response);
				if (strlen(truncRes) > 60) { truncRes[60] = '\0'; strcopy(truncRes[57], 4, "..."); }
				ReplaceString(truncRes, sizeof(truncRes), "\n", " ");
				if (g_OllamaHistory[idx].playerName[0])
					ReplyToCommand(client, "[NVD]   H%d ✅ %.1fs [%s](%s) %s → \"%s\"", i, g_OllamaHistory[idx].duration, g_OllamaHistory[idx].ownerName, g_OllamaHistory[idx].playerName, truncPrompt, truncRes);
				else
					ReplyToCommand(client, "[NVD]   H%d ✅ %.1fs [%s] %s → \"%s\"", i, g_OllamaHistory[idx].duration, g_OllamaHistory[idx].ownerName, truncPrompt, truncRes);
			} else {
				if (g_OllamaHistory[idx].playerName[0])
					ReplyToCommand(client, "[NVD]   H%d ❌ %.1fs [%s](%s) %s", i, g_OllamaHistory[idx].duration, g_OllamaHistory[idx].ownerName, g_OllamaHistory[idx].playerName, truncPrompt);
				else
					ReplyToCommand(client, "[NVD]   H%d ❌ %.1fs [%s] %s", i, g_OllamaHistory[idx].duration, g_OllamaHistory[idx].ownerName, truncPrompt);
			}
		}
	} else {
        ReplyToCommand(client, "[NVD] ── Recent History (Empty) ──");
    }

	if (g_RequestQueue.Length > 0) {
		ReplyToCommand(client, "[NVD] ── Waiting Queue ──");
		for (int i = 0; i < g_RequestQueue.Length; i++) {
			DataPack pack = view_as<DataPack>(g_RequestQueue.Get(i));
			pack.Reset();
			Handle _pl; Function _cb; any _data; float _to, _st; int _ret, id, _pid;
			char prompt[512], _sys[2048], _mdl[64], _ep[32], ownerName[64], hist[2048], playerName[32], contextJSON[1024];
			UnpackRequest(pack, _pl, _cb, _data, prompt, sizeof(prompt), _sys, sizeof(_sys), _mdl, sizeof(_mdl), _ep, sizeof(_ep), ownerName, sizeof(ownerName), hist, sizeof(hist), playerName, sizeof(playerName), _to, _ret, _st, id, _pid, contextJSON, 1024);
			char displayBuf[512];
			if (contextJSON[0] != '\0' && GetFeatureStatus(FeatureType_Native, "NVD_BuildPrompts") == FeatureStatus_Available) {
				char sysP[2048], fullP[1024];
				NVD_BuildPrompts(contextJSON, "user", _pid, sysP, sizeof(sysP), fullP, sizeof(fullP));
				strcopy(displayBuf, sizeof(displayBuf), fullP);
			} else {
				strcopy(displayBuf, sizeof(displayBuf), prompt);
			}
			if (strlen(displayBuf) > 60) { displayBuf[60] = '\0'; strcopy(displayBuf[57], 4, "..."); }
			if (strlen(prompt) > 60) { prompt[60] = '\0'; strcopy(prompt[57], 4, "..."); }
			float waitTime = GetGameTime() - _st;
			if (playerName[0])
				ReplyToCommand(client, "[NVD]   T%d #%d: [%s](%s) %.1fs %s", id, i+1, ownerName, playerName, waitTime, displayBuf);
			else
				ReplyToCommand(client, "[NVD]   T%d #%d: [%s] %.1fs %s", id, i+1, ownerName, waitTime, displayBuf);
		}
	} else {
        ReplyToCommand(client, "[NVD] ── Waiting Queue (Empty) ──");
    }
	ReplyToCommand(client, "[NVD] Use T<id> to inspect an entry: sm_ollama_status T123");
	return Plugin_Handled;
}

public Action Command_OllamaReload(int client, int args)
{
	OnMapEnd(); g_WarmupDone = false; WarmupModel(); ReplyToCommand(client, "[NVD] ✅ Queues flushed"); return Plugin_Handled;
}

void PackRequest(DataPack pack, Handle plugin, Function cb, any cbData,
    const char[] prompt, const char[] system, const char[] model, const char[] endpoint,
    const char[] ownerName, const char[] historyJSON, const char[] playerName,
    float timeout, int retries, float startTime, int requestId, int playerId = 0,
    const char[] contextJSON = "")
{
    pack.WriteCell(plugin); pack.WriteFunction(cb); pack.WriteCell(cbData);
    pack.WriteString(prompt); pack.WriteString(system); pack.WriteString(model);
    pack.WriteString(endpoint); pack.WriteString(ownerName); pack.WriteString(historyJSON);
    pack.WriteString(playerName); pack.WriteCell(playerId);
    pack.WriteString(contextJSON);
    pack.WriteFloat(timeout); pack.WriteCell(retries); pack.WriteFloat(startTime);
    pack.WriteCell(requestId);
}

void UnpackRequest(DataPack pack,
    Handle &plugin, Function &cb, any &cbData,
    char[] prompt, int promptLen, char[] system, int systemLen,
    char[] model, int modelLen, char[] endpoint, int endpointLen,
    char[] ownerName, int ownerNameLen, char[] historyJSON, int historyJSONLen,
    char[] playerName, int playerNameLen,
    float &timeout, int &retries, float &startTime, int &requestId, int &playerId,
    char[] contextJSON, int contextLen)
{
    plugin = view_as<Handle>(pack.ReadCell()); cb = pack.ReadFunction(); cbData = pack.ReadCell();
    pack.ReadString(prompt, promptLen); pack.ReadString(system, systemLen);
    pack.ReadString(model, modelLen); pack.ReadString(endpoint, endpointLen);
    pack.ReadString(ownerName, ownerNameLen); pack.ReadString(historyJSON, historyJSONLen);
    pack.ReadString(playerName, playerNameLen); playerId = pack.ReadCell();
    pack.ReadString(contextJSON, contextLen);
    timeout = pack.ReadFloat(); retries = pack.ReadCell(); startTime = pack.ReadFloat();
    requestId = pack.ReadCell();
}

public int Native_AskAI(Handle plugin, int numParams)
{
    char prompt[512], system[2048], historyJSON[2048] = "";
    GetNativeString(1, prompt, sizeof(prompt)); GetNativeString(2, system, sizeof(system));
    ProcessTemplates(prompt, sizeof(prompt)); ProcessTemplates(system, sizeof(system));
    Function cb =     GetNativeFunction(3); any cbData = GetNativeCell(4);
    if (numParams >= 5) GetNativeString(5, historyJSON, sizeof(historyJSON));
    float timeout = (numParams >= 7) ? view_as<float>(GetNativeCell(7)) : 120.0;
    char contextJSON[1024] = "";
    if (numParams >= 9) GetNativeString(9, contextJSON, sizeof(contextJSON));
    char model[64], endpoint[32], ownerName[64], playerName[32];
    g_ModelCvar.GetString(model, sizeof(model)); g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    GetPluginFilename(plugin, ownerName, sizeof(ownerName));
    playerName[0] = '\0'; int playerId = 0;
    if (cbData >= 1 && cbData <= MaxClients && IsClientInGame(cbData)) {
        GetClientName(cbData, playerName, sizeof(playerName));
        playerId = cbData;
    }
	int concurrency = g_ConcurrencyCvar.IntValue; if (concurrency < 1) concurrency = 1;
	int active = 0; for (int i = 0; i < MAX_REQUESTS; i++) if (g_Requests[i].state == ReqState_Processing) active++;

	DataPack pack = new DataPack();
	PackRequest(pack, plugin, cb, cbData, prompt, system, model, endpoint, ownerName, historyJSON, playerName, timeout, 0, GetGameTime(), g_NextRequestId++, playerId, contextJSON);

	if (!g_WarmupDone || active >= concurrency || g_RequestQueue.Length > 0) {
		g_RequestQueue.Push(pack);
		ProcessQueue();
		return 1;
	}

	pack.Reset();
	Handle _pl; Function _cb; any _data;
	char _p[512], _s[2048], _m[64], _e[32], _on[64], _h[2048], _pn[32], _ctx[1024];
	float _to, _st; int _ret, _id, _pid;
	UnpackRequest(pack, _pl, _cb, _data, _p, 512, _s, 2048, _m, 64, _e, 32, _on, 64, _h, 2048, _pn, 32, _to, _ret, _st, _id, _pid, _ctx, 1024);
	delete pack;

	int slot = AllocateSlot(_cb, _data, _pl, _on);
	if (slot == -1) return 0;
	g_Requests[slot].playerId = _pid;
	g_Requests[slot].retries = _ret; g_Requests[slot].requestTime = _st; g_Requests[slot].requestId = _id;
	strcopy(g_Requests[slot].origContext, 1024, _ctx);

	SendRequest(slot, _p, _s, _m, _e, _h, _to);
	return 1;
}

void SendRequest(int slot, const char[] prompt, const char[] system, const char[] model, const char[] endpoint, const char[] historyJSON = "", float timeout = 120.0)
{
    // Build prompts from template
    char finalPrompt[1024], finalSystem[3072];
    if (g_Requests[slot].origContext[0] != '\0' && 
        GetFeatureStatus(FeatureType_Native, "NVD_BuildPrompts") == FeatureStatus_Available) {
        NVD_BuildPrompts(g_Requests[slot].origContext, "both", g_Requests[slot].playerId,
            finalSystem, sizeof(finalSystem), finalPrompt, sizeof(finalPrompt));
    } else {
        strcopy(finalPrompt, sizeof(finalPrompt), prompt);
        strcopy(finalSystem, sizeof(finalSystem), system);
    }
    
    // Process templates BEFORE sending to AI
    ProcessTemplates(finalPrompt, sizeof(finalPrompt)); 
    ProcessTemplates(finalSystem, sizeof(finalSystem));

    strcopy(g_Requests[slot].origPrompt, 512, finalPrompt); strcopy(g_Requests[slot].origSystem, 2048, finalSystem);
    // REMOVIDO: injeção de idioma dinâmica para evitar conflito com templates
    char url[64]; Format(url, sizeof(url), "/api/%s", endpoint);
	JSONObject payload = new JSONObject(); payload.SetString("model", model); payload.SetBool("stream", false);
	JSONArray msgs = new JSONArray();
	JSONObject sMsg = new JSONObject(); sMsg.SetString("role", "system"); sMsg.SetString("content", finalSystem); msgs.Push(sMsg); delete sMsg;
	if (historyJSON[0]) {
		JSONArray history = JSONArray.FromString(historyJSON);
		if (history != null) {
			for (int i = 0; i < history.Length; i++) {
				JSONObject hMsg = view_as<JSONObject>(history.Get(i));
				if (hMsg != null) { msgs.Push(hMsg); delete hMsg; }
			}
			delete history;
		}
	}
	JSONObject uMsg = new JSONObject(); uMsg.SetString("role", "user"); uMsg.SetString("content", finalPrompt); msgs.Push(uMsg); delete uMsg;
	payload.Set("messages", msgs); delete msgs;
	JSONObject options = new JSONObject(); options.SetFloat("temperature", 0.8); options.SetString("keep_alive", "10m");
	payload.Set("options", options); delete options;
	payload.ToString(g_Requests[slot].retryBody, sizeof(g_Requests[slot].retryBody));
	strcopy(g_Requests[slot].retryUrl, sizeof(g_Requests[slot].retryUrl), url);
	g_Requests[slot].timeout = timeout; g_Requests[slot].requestTime = GetGameTime();
	strcopy(g_Requests[slot].prompt, 256, finalPrompt);
	char ep[32]; BuildApiUrl(ep, sizeof(ep));
	char fullUrl[256]; Format(fullUrl, sizeof(fullUrl), "%s%s", g_BaseUrl, ep);
	HTTPRequest req = new HTTPRequest(fullUrl);
	req.SetHeader("Content-Type", "application/json");
	req.Timeout = RoundToCeil(timeout) + 5;
	req.Post(payload, OnOllamaResponse, slot);
	delete payload;
}

public void OnOllamaResponse(HTTPResponse response, any slotId)
{
		if (slotId < 0 || slotId >= MAX_REQUESTS || g_Requests[slotId].state != ReqState_Processing) return;
		if (view_as<int>(response.Status) == 307 && g_Requests[slotId].retries < g_MaxRetriesCvar.IntValue) {
			g_Requests[slotId].retries++;
			g_Requests[slotId].response[0] = '\0';
			g_Requests[slotId].state = ReqState_Failed; RecordOllamaHistory(slotId);
			DataPack retryPack = new DataPack();
			PackRequest(retryPack,
				g_Requests[slotId].plugin, g_Requests[slotId].callback, g_Requests[slotId].callbackData,
				g_Requests[slotId].origPrompt, g_Requests[slotId].origSystem,
				g_Requests[slotId].origModel, g_Requests[slotId].origEndpoint,
				g_Requests[slotId].ownerName, g_Requests[slotId].origHistory,
				g_Requests[slotId].playerName,
				g_Requests[slotId].timeout, g_Requests[slotId].retries,
				g_Requests[slotId].requestTime, g_Requests[slotId].requestId,
				g_Requests[slotId].playerId, g_Requests[slotId].origContext);
			CreateTimer(6.0, Timer_RequeueRequest, retryPack);
			Function cb; any data; Handle pl; char owner[64]; FreeSlot(slotId, cb, data, pl, owner);
			return;
		}
	if (response.Status != HTTPStatus_OK) {
		g_Requests[slotId].state = ReqState_Failed; RecordOllamaHistory(slotId);
		Function cb; any data; Handle pl; char owner[64]; FreeSlot(slotId, cb, data, pl, owner);
		QueueResponse(owner, "ERROR_HTTP", data); return;
	}
	JSONObject json = view_as<JSONObject>(response.Data);
	char reply[2048]; JSONObject msg = view_as<JSONObject>(json.Get("message"));
	if (msg != null) { msg.GetString("content", reply, sizeof(reply)); delete msg; }
	delete json;
	strcopy(g_Requests[slotId].response, 512, reply); g_Requests[slotId].state = (reply[0] != '\0') ? ReqState_Fulfilled : ReqState_Failed; RecordOllamaHistory(slotId);
	Function cb; any data; Handle plugin; char ownerName[64];
	if (!FreeSlot(slotId, cb, data, plugin, ownerName)) return;
	if (cb != INVALID_FUNCTION) {
		Call_StartFunction(plugin, cb); Call_PushString(reply); Call_PushCell(data); Call_Finish();
	} else QueueResponse(ownerName, reply, data);
}

public Action Timer_RequeueRequest(Handle timer, DataPack pack)
{
    pack.Reset();
    Handle plugin; Function cb; any cbData;
    char prompt[512], system[2048], model[64], endpoint[32], ownerName[64], historyJSON[2048], playerName[32], contextJSON[1024];
    float timeout, startTime; int retries, reqId, pid;
    UnpackRequest(pack, plugin, cb, cbData, prompt, sizeof(prompt), system, sizeof(system), model, sizeof(model), endpoint, sizeof(endpoint), ownerName, sizeof(ownerName), historyJSON, sizeof(historyJSON), playerName, sizeof(playerName), timeout, retries, startTime, reqId, pid, contextJSON, 1024);
    delete pack;
    DataPack newPack = new DataPack();
    PackRequest(newPack, plugin, cb, cbData, prompt, system, model, endpoint, ownerName, historyJSON, playerName, timeout, retries, startTime, reqId, pid, contextJSON);
    if (g_RequestQueue.Length == 0) g_RequestQueue.Push(newPack);
    else { g_RequestQueue.ShiftUp(0); g_RequestQueue.Set(0, newPack); }
    ProcessQueue();
    return Plugin_Stop;
}

public int Native_PollResponse(Handle plugin, int numParams)
{
	if (g_PendingResponses == null || g_PendingResponses.Length == 0) return 0;
	char callerName[64]; GetPluginFilename(plugin, callerName, sizeof(callerName));
	int maxlen = GetNativeCell(2);
	for (int i = 0; i < g_PendingResponses.Length; i++) {
		DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i)); pack.Reset();
		char ownerName[64]; pack.ReadString(ownerName, sizeof(ownerName));
		if (StrEqual(ownerName, callerName)) {
			any cbData = pack.ReadCell(); pack.ReadFloat();
			char[] reply = new char[maxlen]; pack.ReadString(reply, maxlen);
			SetNativeCellRef(3, cbData); SetNativeString(1, reply, maxlen);
			g_PendingResponses.Erase(i); delete pack; return 1;
		}
	}
	return 0;
}

public int Native_CanRequest(Handle plugin, int numParams)
{
	int client = GetNativeCell(1); if (client < 1 || client > MAXPLAYERS) return true;
	float now = GetGameTime();
	if (now - g_WindowStart[client] > RATE_LIMIT_WINDOW) { g_WindowStart[client] = now; g_PlayerRequestCount[client] = 0; }
	g_PlayerRequestCount[client]++; return g_PlayerRequestCount[client] <= MAX_REQUESTS_PER_WINDOW;
}

int AllocateSlot(Function cb, any data, Handle plugin, const char[] ownerName)
{
	for (int i = 0; i < MAX_REQUESTS; i++) {
        if (g_Requests[i].state == ReqState_Queued) {
		g_Requests[i].callback = cb; g_Requests[i].callbackData = data;
		g_Requests[i].plugin = plugin; g_Requests[i].state = ReqState_Processing;
		strcopy(g_Requests[i].ownerName, 128, ownerName); // Usando novo tamanho
		g_Requests[i].requestTime = GetGameTime(); g_Requests[i].retries = 0;
		g_Requests[i].requestId = g_NextRequestId++;
		g_Requests[i].prompt[0] = '\0';
		g_Requests[i].response[0] = '\0';
		g_Requests[i].origPrompt[0] = '\0'; g_Requests[i].origSystem[0] = '\0';
		g_Requests[i].origHistory[0] = '\0';
		g_Requests[i].origContext[0] = '\0';
		g_Requests[i].playerId = 0; g_Requests[i].playerName[0] = '\0';
		if (data >= 1 && data <= MaxClients && IsClientInGame(data)) {
			g_Requests[i].playerId = data;
			GetClientName(data, g_Requests[i].playerName, 64); // Usando novo tamanho
		}
		return i;
        }
    }
    // Debug: logar o estado de todos os slots se falhar
    char debugBuf[512];
    for (int i = 0; i < MAX_REQUESTS; i++) Format(debugBuf, sizeof(debugBuf), "%s%d:%d ", debugBuf, i, g_Requests[i].state);
    LogMessage("[NVD_DEBUG] AllocateSlot failed. States: %s", debugBuf);
	return -1;
}

bool FreeSlot(int id, Function &cb, any &data, Handle &plugin, char[] ownerName)
{
	if (id < 0 || id >= MAX_REQUESTS || g_Requests[id].state != ReqState_Processing) return false;
	cb = g_Requests[id].callback; data = g_Requests[id].callbackData;
	plugin = g_Requests[id].plugin; strcopy(ownerName, 64, g_Requests[id].ownerName);
	g_Requests[id].origContext[0] = '\0';
	g_Requests[id].state = ReqState_Queued; ProcessQueue(); return true;
}

void CleanupQueue()
{
	if (g_RequestQueue == null || g_RequestQueue.Length == 0) return;
	for (int i = g_RequestQueue.Length - 1; i >= 0; i--) {
		DataPack pack = view_as<DataPack>(g_RequestQueue.Get(i));
		pack.Reset();
        // Unpack apenas o necessário para checar o timeout
		Handle _pl; Function _cb; any _data; float _to, _st; int _ret, id, _pid;
		char prompt[512], _sys[2048], _m[64], _e[32], _on[64], _h[2048], _pn[32], _ctx[1024];
		UnpackRequest(pack, _pl, _cb, _data, prompt, sizeof(prompt), _sys, sizeof(_sys), _m, sizeof(_m), _e, sizeof(_e), _on, sizeof(_on), _h, sizeof(_h), _pn, sizeof(_pn), _to, _ret, _st, id, _pid, _ctx, 1024);
		
		if (GetGameTime() - _st > _to) {
			LogMessage("[NVD] ⚠️ Queue: Removing expired request %d", id);
			delete pack;
			g_RequestQueue.Erase(i);
		}
	}
}

void ProcessQueue()
{
	if (g_RequestQueue == null || g_RequestQueue.Length == 0) return;
    CleanupQueue();
	int concurrency = g_ConcurrencyCvar.IntValue; if (concurrency < 1) concurrency = 1;
	while (g_RequestQueue.Length > 0) {
		int active = 0; for (int i = 0; i < MAX_REQUESTS; i++) if (g_Requests[i].state == ReqState_Processing) active++;
		if (active >= concurrency) break;
		
		DataPack pack = view_as<DataPack>(g_RequestQueue.Get(0)); g_RequestQueue.Erase(0); pack.Reset();
		Handle ownerPlugin; Function cb; any cbData;
		char prompt[512], system[2048], model[64], endpoint[32], ownerName[64], historyJSON[2048], playerName[32], contextJSON[1024];
		float timeout, startTime; int retries, reqId, pid;
		UnpackRequest(pack, ownerPlugin, cb, cbData, prompt, sizeof(prompt), system, sizeof(system), model, sizeof(model), endpoint, sizeof(endpoint), ownerName, sizeof(ownerName), historyJSON, sizeof(historyJSON), playerName, sizeof(playerName), timeout, retries, startTime, reqId, pid, contextJSON, 1024);
		delete pack;
		
		int slot = AllocateSlot(cb, cbData, ownerPlugin, ownerName);
		if (slot != -1) {
			g_Requests[slot].retries = retries; g_Requests[slot].requestTime = startTime; g_Requests[slot].requestId = reqId;
			g_Requests[slot].playerId = pid;
			strcopy(g_Requests[slot].origContext, 1024, contextJSON);
			SendRequest(slot, prompt, system, model, endpoint, historyJSON, timeout);
		} else {
			LogMessage("[NVD] ⚠️ ProcessQueue: Failed to allocate slot for request %d", reqId);
		}
	}
}
