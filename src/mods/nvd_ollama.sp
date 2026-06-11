#include <sourcemod>
#include <ripext>
#include <nvd_core>

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

enum struct PendingRequest
{
	Function callback;
	any callbackData;
	char ownerName[64];
	Handle plugin;
	char playerName[32];
	int playerId;
	float requestTime;
	float timeout;
	char retryUrl[256];
	char retryBody[4096];
	char prompt[256];
	char response[512];
	int retries;
	bool inUse;

	char origPrompt[512];
	char origSystem[2048];
	char origModel[64];
	char origEndpoint[32];
	char origHistory[2048];
}

#define MAX_PENDING 64
PendingRequest g_PendingRequests[MAX_PENDING];

// ── Rate Limiting ──
#define RATE_LIMIT_WINDOW 5.0
#define MAX_REQUESTS_PER_WINDOW 3
float g_PlayerLastRequest[MAXPLAYERS + 1];
int g_PlayerRequestCount[MAXPLAYERS + 1];
float g_WindowStart[MAXPLAYERS + 1];

#define MAX_OLLAMA_HISTORY 10
enum struct OllamaHistoryEntry
{
	char prompt[256];
	char response[512];
	char owner[64];
	float duration;
	bool success;
}
OllamaHistoryEntry g_OllamaHistory[MAX_OLLAMA_HISTORY];
int g_OllamaHistoryIdx = 0;
int g_OllamaHistoryCount = 0;

HTTPClient g_HttpClient;
ConVar g_IpCvar, g_PortCvar, g_ModelCvar, g_EndpointCvar, g_DebugCvar, g_DumpCvar;
ConVar g_ConcurrencyCvar, g_MaxPendingCvar, g_MaxRetriesCvar;
char g_BaseUrl[256];

// ── NOVA FILA DE REQUISIÇÕES ──
ArrayList g_RequestQueue;

public Plugin myinfo = { name = "NVD Ollama", author = "OpenCode", description = "Ollama AI bridge with queue", version = "2.1.0" };

// Shared _meta template snippets
char g_MetaKeys[32][64];
char g_MetaValues[32][1024];
int g_MetaCount = 0;

// Gerenciador de Strings Centralizado
enum struct PluginStrings
{
	char prefix[64];
	KeyValues kvDefault;
	KeyValues kvLang;
	bool registered;
}

PluginStrings g_RegisteredPlugins[16];
int g_RegisteredCount = 0;
ConVar g_LangCvar;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("NVD_AskAI", Native_AskAI);
	CreateNative("NVD_CanRequest", Native_CanRequest);
	CreateNative("NVD_PollResponse", Native_PollResponse);
	CreateNative("NVD_SetMeta", Native_SetMeta);
	CreateNative("NVD_RegisterStrings", Native_RegisterStrings);
	CreateNative("NVD_GetStr", Native_GetStr);
	RegPluginLibrary("nvd_core");
	return APLRes_Success;
}

public int Native_SetMeta(Handle plugin, int numParams)
{
	char key[64], value[1024];
	GetNativeString(1, key, sizeof(key));
	GetNativeString(2, value, sizeof(value));

	// Update existing if found
	for (int i = 0; i < g_MetaCount; i++) {
		if (StrEqual(g_MetaKeys[i], key)) {
			strcopy(g_MetaValues[i], sizeof(g_MetaValues[]), value);
			return 0;
		}
	}

	// Add new
	if (g_MetaCount < 32) {
		strcopy(g_MetaKeys[g_MetaCount], sizeof(g_MetaKeys[]), key);
		strcopy(g_MetaValues[g_MetaCount], sizeof(g_MetaValues[]), value);
		g_MetaCount++;
	}
	return 0;
}

public int Native_RegisterStrings(Handle plugin, int numParams)
{
	char prefix[64];
	GetNativeString(1, prefix, sizeof(prefix));

	for (int i = 0; i < g_RegisteredCount; i++) {
		if (StrEqual(g_RegisteredPlugins[i].prefix, prefix)) {
			LoadPluginStrings(i);
			return 0;
		}
	}

	if (g_RegisteredCount < 16) {
		strcopy(g_RegisteredPlugins[g_RegisteredCount].prefix, 64, prefix);
		g_RegisteredPlugins[g_RegisteredCount].registered = true;
		LoadPluginStrings(g_RegisteredCount);
		g_RegisteredCount++;
	}
	return 0;
}

public int Native_GetStr(Handle plugin, int numParams)
{
	char prefix[64], section[64], key[64], fallback[1024];
	GetNativeString(1, prefix, sizeof(prefix));
	GetNativeString(2, section, sizeof(section));
	GetNativeString(3, key, sizeof(key));
	int maxlen = GetNativeCell(5);
	GetNativeString(6, fallback, sizeof(fallback));

	for (int i = 0; i < g_RegisteredCount; i++) {
		if (StrEqual(g_RegisteredPlugins[i].prefix, prefix)) {
			char buffer[1024];
			if (g_RegisteredPlugins[i].kvLang != null) {
				g_RegisteredPlugins[i].kvLang.Rewind();
				if (g_RegisteredPlugins[i].kvLang.JumpToKey(section)) {
					g_RegisteredPlugins[i].kvLang.GetString(key, buffer, sizeof(buffer));
					if (buffer[0] != '\0') {
						SetNativeString(4, buffer, maxlen);
						return 0;
					}
				}
			}
			if (g_RegisteredPlugins[i].kvDefault != null) {
				g_RegisteredPlugins[i].kvDefault.Rewind();
				if (g_RegisteredPlugins[i].kvDefault.JumpToKey(section)) {
					g_RegisteredPlugins[i].kvDefault.GetString(key, buffer, sizeof(buffer));
					if (buffer[0] != '\0') {
						SetNativeString(4, buffer, maxlen);
						return 0;
					}
				}
			}
			break;
		}
	}
	SetNativeString(4, fallback, maxlen);
	return 0;
}

void LoadPluginStrings(int idx)
{
	if (g_RegisteredPlugins[idx].kvDefault != null) delete g_RegisteredPlugins[idx].kvDefault;
	if (g_RegisteredPlugins[idx].kvLang != null) delete g_RegisteredPlugins[idx].kvLang;
	g_RegisteredPlugins[idx].kvDefault = null;
	g_RegisteredPlugins[idx].kvLang = null;

	char path[PLATFORM_MAX_PATH], prefix[64];
	strcopy(prefix, sizeof(prefix), g_RegisteredPlugins[idx].prefix);

	BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_default.txt", prefix);
	if (FileExists(path)) {
		g_RegisteredPlugins[idx].kvDefault = new KeyValues("Strings");
		g_RegisteredPlugins[idx].kvDefault.ImportFromFile(path);
	}

	char lang[32]; g_LangCvar.GetString(lang, sizeof(lang));
	if (!StrEqual(lang, "default")) {
		BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_%s.txt", prefix, lang);
		if (FileExists(path)) {
			g_RegisteredPlugins[idx].kvLang = new KeyValues("Strings");
			g_RegisteredPlugins[idx].kvLang.ImportFromFile(path);
		}
	}
}

void ReloadAllStrings()
{
	for (int i = 0; i < g_RegisteredCount; i++) LoadPluginStrings(i);
	PrintToServer("[NVD] Global language changed: Reloaded strings for %d plugins", g_RegisteredCount);
}

void ProcessTemplates(char[] buffer, int maxlen)
{
	// 1. Core placeholders
	char mapName[64]; GetCurrentMap(mapName, sizeof(mapName));
	ReplaceString(buffer, maxlen, "|map|", mapName);

	char hostname[128]; ConVar hHost = FindConVar("hostname");
	if (hHost != null) hHost.GetString(hostname, sizeof(hostname));
	ReplaceString(buffer, maxlen, "|hostname|", hostname);

	char timeStr[32]; FormatTime(timeStr, sizeof(timeStr), "%H:%M:%S");
	ReplaceString(buffer, maxlen, "|time|", timeStr);

	char dateStr[32]; FormatTime(dateStr, sizeof(dateStr), "%Y-%m-%d");
	ReplaceString(buffer, maxlen, "|date|", dateStr);

	// 2. Meta snippets
	for (int i = 0; i < g_MetaCount; i++) {
		char placeholder[68]; Format(placeholder, sizeof(placeholder), "|%s|", g_MetaKeys[i]);
		ReplaceString(buffer, maxlen, placeholder, g_MetaValues[i]);
	}
}

public void OnPluginStart()
{
	g_IpCvar = CreateConVar("nvd_ollama_ip", "172.17.0.1");
	g_PortCvar = CreateConVar("nvd_ollama_port", "11433");
	g_ModelCvar = CreateConVar("nvd_ollama_model", "qwen2.5:1.5b");
	g_EndpointCvar = CreateConVar("nvd_ollama_endpoint", "chat");
	g_DebugCvar = CreateConVar("nvd_ollama_debug", "1");
	g_DumpCvar = CreateConVar("nvd_ollama_dump", "1", "Dump full request JSON to logs/nvd_ollama_dump.jsonl");
	g_ConcurrencyCvar = CreateConVar("nvd_ollama_concurrency", "1", "Max concurrent AI requests (Set to 1 for sequential)");
	g_MaxPendingCvar = CreateConVar("nvd_ollama_max_pending", "16", "Max pending slot pool (4-64)");
	g_MaxRetriesCvar = CreateConVar("nvd_ollama_max_retries", "10", "Max retries per request for 307 errors");

	g_LangCvar = CreateConVar("nvd_language", "default", "Global language for all NVD plugins");
	g_LangCvar.AddChangeHook(OnGlobalLanguageChanged);

	RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK);
	RegAdminCmd("sm_ollama_status", Command_OllamaStatus, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ollama_reload", Command_OllamaReload, ADMFLAG_KICK);
	RegAdminCmd("sm_ollama_history", Command_OllamaHistory, ADMFLAG_GENERIC);
	RegAdminCmd("sm_llama_history", Command_OllamaHistory, ADMFLAG_GENERIC);

	for (int i = 0; i < MAX_PENDING; i++)
		g_PendingRequests[i].inUse = false;

	g_RequestQueue = new ArrayList();

	CreateTimer(15.0, Timer_CleanupQueue, _, TIMER_REPEAT);
	CreateTimer(5.0, Timer_CleanupStaleSlots, _, TIMER_REPEAT);
}

int GetMaxPending()
{
	int v = g_MaxPendingCvar.IntValue;
	return (v < 4) ? 4 : (v > MAX_PENDING ? MAX_PENDING : v);
}

public Action Timer_CleanupStaleSlots(Handle timer)
{
	int maxSlots = GetMaxPending();
	for (int i = 0; i < maxSlots; i++) {
		if (!g_PendingRequests[i].inUse) continue;
		float elapsed = GetGameTime() - g_PendingRequests[i].requestTime;
		
		// Global safety timeout (5 minutes) or per-request timeout
		if (elapsed > 300.0 || (g_PendingRequests[i].timeout > 0.0 && elapsed >= g_PendingRequests[i].timeout)) {
			PrintToServer("[NVD] ⏰ Slot %d timed out (%.0fs), freeing", i, elapsed);
			strcopy(g_PendingRequests[i].response, 512, "TIMEOUT");
			RecordOllamaHistory(i, false);
			Function cb; any data; Handle plugin; char ownerName[64];
			FreeSlot(i, cb, data, plugin, ownerName);
			QueueResponse(ownerName, "ERROR_TIMEOUT", data);
		}
	}
	return Plugin_Continue;
}

public void OnGlobalLanguageChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
	ReloadAllStrings();
}

public void OnMapEnd()
{
	if (g_RequestQueue != null)
	{
		for (int i = 0; i < g_RequestQueue.Length; i++)
		{
			DataPack pack = view_as<DataPack>(g_RequestQueue.Get(i));
			delete pack;
		}
		g_RequestQueue.Clear();
	}
	if (g_PendingResponses != null)
	{
		for (int i = 0; i < g_PendingResponses.Length; i++)
		{
			DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i));
			delete pack;
		}
		g_PendingResponses.Clear();
	}
}

public Action Timer_CleanupQueue(Handle timer)
{
	if (g_PendingResponses == null || g_PendingResponses.Length == 0)
		return Plugin_Continue;

	float now = GetGameTime();
	int cleaned = 0;
	for (int i = g_PendingResponses.Length - 1; i >= 0; i--)
	{
		DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i));
		pack.Reset();
		char dummy[64];
		pack.ReadString(dummy, sizeof(dummy)); // skip plugin name (string)
		pack.ReadCell();                       // skip cbData (cell)
		float queuedAt = pack.ReadFloat();
		if (now - queuedAt > RESPONSE_TTL)
		{
			g_PendingResponses.Erase(i);
			delete pack;
			cleaned++;
		}
	}
	if (cleaned > 0)
		PrintToServer("[NVD] 🧹 Cleaned %d stale responses (%d remaining)", cleaned, g_PendingResponses.Length);
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	g_PlayerLastRequest[client] = 0.0;
	g_PlayerRequestCount[client] = 0;
	g_WindowStart[client] = 0.0;
}

public void OnConfigsExecuted()
{
	char ip[64], port[16];
	g_IpCvar.GetString(ip, sizeof(ip));
	g_PortCvar.GetString(port, sizeof(port));
	Format(g_BaseUrl, sizeof(g_BaseUrl), "http://%s:%s", ip, port);
	
	if (g_HttpClient != null) delete g_HttpClient;
	g_HttpClient = new HTTPClient(g_BaseUrl);
	g_HttpClient.FollowLocation = true;
	g_HttpClient.SetHeader("Content-Type", "application/json");

	if (g_DebugCvar.BoolValue)
		PrintToServer("[NVD] Ollama v2.1 loaded -> Ollama at %s", g_BaseUrl);

	WarmupModel();
}

void BuildApiUrl(char[] url, int maxlen)
{
    char endpoint[32];
    g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    if (StrContains(endpoint, "/") != -1)
        Format(url, maxlen, "/%s", endpoint);
    else
        Format(url, maxlen, "/api/%s/", endpoint);
}

void WarmupModel()
{
	char model[64];
	g_ModelCvar.GetString(model, sizeof(model));

	JSONObject payload = new JSONObject();
	payload.SetString("model", model);
	payload.SetBool("stream", false);
	JSONObject sys = new JSONObject();
	sys.SetString("role", "system");
	sys.SetString("content", "Be brief.");
	JSONArray msgs = new JSONArray();
	msgs.Push(sys);
	delete sys;
	JSONObject usr = new JSONObject();
	usr.SetString("role", "user");
	usr.SetString("content", "ping");
	msgs.Push(usr);
	delete usr;
	payload.Set("messages", msgs);
	delete msgs;

	JSONObject warmupOpts = new JSONObject(); warmupOpts.SetString("keep_alive", "10m");
	payload.Set("options", warmupOpts); delete warmupOpts;
	char url[64]; BuildApiUrl(url, sizeof(url));
	g_HttpClient.Post(url, payload, OnWarmupResponse, 0);
	delete payload;
}

public void OnWarmupResponse(HTTPResponse response, any data)
{
	if (response.Status == HTTPStatus_OK)
		PrintToServer("[NVD] ✅ Warmup OK (keep_alive set)");
	else
		PrintToServer("[NVD] ⚠️ Warmup HTTP %d", response.Status);
}

public Action Command_OllamaTest(int client, int args)
{
	ReplyToCommand(client, "[NVD] Testing Ollama connection...");
	TestConnection(client);
	return Plugin_Handled;
}

void RecordOllamaHistory(int slot, bool success)
{
	int idx = g_OllamaHistoryIdx;
	strcopy(g_OllamaHistory[idx].prompt, sizeof(g_OllamaHistory[].prompt), g_PendingRequests[slot].prompt);
	strcopy(g_OllamaHistory[idx].response, sizeof(g_OllamaHistory[].response), g_PendingRequests[slot].response);
	strcopy(g_OllamaHistory[idx].owner, sizeof(g_OllamaHistory[].owner), g_PendingRequests[slot].ownerName);
	g_OllamaHistory[idx].duration = GetGameTime() - g_PendingRequests[slot].requestTime;
	g_OllamaHistory[idx].success = success;

	g_OllamaHistoryIdx = (g_OllamaHistoryIdx + 1) % MAX_OLLAMA_HISTORY;
	if (g_OllamaHistoryCount < MAX_OLLAMA_HISTORY) g_OllamaHistoryCount++;
}

public Action Command_OllamaHistory(int client, int args)
{
	ReplyToCommand(client, "[NVD] ═══ Ollama Request History (Last %d) ═══", g_OllamaHistoryCount);
	if (g_OllamaHistoryCount == 0) {
		ReplyToCommand(client, "[NVD] (empty)");
		return Plugin_Handled;
	}

	for (int i = 0; i < g_OllamaHistoryCount; i++) {
		int idx = (g_OllamaHistoryIdx - g_OllamaHistoryCount + i + MAX_OLLAMA_HISTORY) % MAX_OLLAMA_HISTORY;
		ReplyToCommand(client, "[NVD] #%d | %s | %s | %s", i + 1, g_OllamaHistory[idx].success ? "✅" : "❌", g_OllamaHistory[idx].owner, g_OllamaHistory[idx].prompt);
		ReplyToCommand(client, "[NVD]     Res: %s", g_OllamaHistory[idx].response[0] ? g_OllamaHistory[idx].response : "(no response)");
	}
	return Plugin_Handled;
}

public Action Command_OllamaStatus(int client, int args)
{
	int maxSlots = GetMaxPending();
	int used = 0;
	for (int i = 0; i < maxSlots; i++)
		if (g_PendingRequests[i].inUse) used++;

	ReplyToCommand(client, "[NVD] ═══ Ollama Status ═══");
	char model[64]; g_ModelCvar.GetString(model, sizeof(model));
	ReplyToCommand(client, "[NVD] Model: %s", model);
	int respLen = (g_PendingResponses != null) ? g_PendingResponses.Length : 0;
	ReplyToCommand(client, "[NVD] Queue: %d active (concurrency %d) | %d waiting | %d pending | pool %d/%d", used, g_ConcurrencyCvar.IntValue, g_RequestQueue.Length, respLen, maxSlots, MAX_PENDING);
	for (int i = 0; i < maxSlots; i++) {
		if (!g_PendingRequests[i].inUse) continue;
		float elapsed = GetGameTime() - g_PendingRequests[i].requestTime;
		char timeoutStr[8]; Format(timeoutStr, sizeof(timeoutStr), "%.0f", g_PendingRequests[i].timeout);
		if (g_PendingRequests[i].timeout == 0.0) strcopy(timeoutStr, sizeof(timeoutStr), "∞");
		ReplyToCommand(client, "[NVD] Slot %d: %s | retry %d | %.0fs/%s | prompt: %s | response: %s", i, g_PendingRequests[i].ownerName, g_PendingRequests[i].retries, elapsed, timeoutStr, g_PendingRequests[i].prompt, g_PendingRequests[i].response);
	}
	return Plugin_Handled;
}

public Action Command_OllamaReload(int client, int args)
{
	int maxSlots = GetMaxPending();
	for (int i = 0; i < maxSlots; i++)
	{
		if (g_PendingRequests[i].inUse)
		{
			Function cb; any data; Handle plugin; char ownerName[64];
			FreeSlot(i, cb, data, plugin, ownerName);
		}
	}
	if (g_RequestQueue != null)
	{
		for (int i = 0; i < g_RequestQueue.Length; i++)
		{
			DataPack pack = view_as<DataPack>(g_RequestQueue.Get(i));
			delete pack;
		}
		g_RequestQueue.Clear();
	}
	if (g_PendingResponses != null)
	{
		for (int i = 0; i < g_PendingResponses.Length; i++)
		{
			DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i));
			delete pack;
		}
		g_PendingResponses.Clear();
	}
	WarmupModel();
	ReplyToCommand(client, "[NVD] ✅ All queues flushed, model warming up");
	return Plugin_Handled;
}

void TestConnection(int client)
{
	char model[64]; g_ModelCvar.GetString(model, sizeof(model));
	JSONObject payload = new JSONObject();
	payload.SetString("model", model);
	payload.SetBool("stream", false);
	JSONObject userMsg = new JSONObject();
	userMsg.SetString("role", "user");
	userMsg.SetString("content", "ping");
	JSONArray messages = new JSONArray();
	messages.Push(userMsg);
	payload.Set("messages", messages);
	delete userMsg; delete messages;
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	char url[64]; BuildApiUrl(url, sizeof(url));
	g_HttpClient.Post(url, payload, OnTestResponse, pack);
	delete payload;
}

public void OnTestResponse(HTTPResponse response, DataPack pack)
{
	pack.Reset(); int client = pack.ReadCell(); delete pack;
	if (client > 0 && !IsClientInGame(client)) return;
	if (response.Status == HTTPStatus_OK)
	{
		JSONObject json = view_as<JSONObject>(response.Data);
		JSONObject msg = view_as<JSONObject>(json.Get("message"));
		char reply[256]; msg.GetString("content", reply, sizeof(reply));
		ReplyToCommand(client, "[NVD] ✅ Ollama OK: \"%s\"", reply);
		delete msg; delete json;
	} else ReplyToCommand(client, "[NVD] ❌ Ollama error: HTTP %d", response.Status);
}

public int Native_AskAI(Handle plugin, int numParams)
{
	char prompt[512], system[2048], historyJSON[2048] = "";
	GetNativeString(1, prompt, sizeof(prompt));
	GetNativeString(2, system, sizeof(system));
	Function cb = GetNativeFunction(3);
	any cbData = GetNativeCell(4);
	if (numParams >= 5) GetNativeString(5, historyJSON, sizeof(historyJSON));
	int priority = (numParams >= 6) ? GetNativeCell(6) : 0;
	float timeout = (numParams >= 7) ? GetNativeCell(7) : 120.0;

	char model[64], endpoint[32], ownerName[64];
	g_ModelCvar.GetString(model, sizeof(model));
	g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
	GetPluginFilename(plugin, ownerName, sizeof(ownerName));

	int active = 0;
	for (int i = 0; i < MAX_PENDING; i++) if (g_PendingRequests[i].inUse) active++;

	int maxConcurrent = g_ConcurrencyCvar.IntValue;
	if (active >= maxConcurrent)
	{
		DataPack pack = new DataPack();
		pack.WriteCell(plugin);
		pack.WriteFunction(cb);
		pack.WriteCell(cbData);
		pack.WriteString(prompt);
		pack.WriteString(system);
		pack.WriteString(model);
		pack.WriteString(endpoint);
		pack.WriteString(ownerName);
		pack.WriteString(historyJSON);
		pack.WriteCell(priority);
		pack.WriteFloat(timeout);
		pack.WriteCell(0); // retries
		pack.WriteFloat(GetGameTime()); // startTime
		g_RequestQueue.Push(pack);
		return 1;
	}

	int slot = AllocateSlot(cb, cbData, plugin, ownerName);
	if (slot == -1) return 0;
	g_PendingRequests[slot].retries = 0;
	g_PendingRequests[slot].requestTime = GetGameTime();
	SendRequest(slot, prompt, system, model, endpoint, historyJSON, timeout);
	return 1;
}

void SendRequest(int slot, const char[] prompt, const char[] system, const char[] model, const char[] endpoint, const char[] historyJSON = "", float timeout = 120.0)
{
	strcopy(g_PendingRequests[slot].origPrompt, 512, prompt);
	strcopy(g_PendingRequests[slot].origSystem, 2048, system);
	strcopy(g_PendingRequests[slot].origModel, 64, model);
	strcopy(g_PendingRequests[slot].origEndpoint, 32, endpoint);
	strcopy(g_PendingRequests[slot].origHistory, 2048, historyJSON);

	char finalPrompt[1024], finalSystem[3072];
	strcopy(finalPrompt, sizeof(finalPrompt), prompt);
	strcopy(finalSystem, sizeof(finalSystem), system);

	ProcessTemplates(finalPrompt, sizeof(finalPrompt));
	ProcessTemplates(finalSystem, sizeof(finalSystem));

	char lang[16]; g_LangCvar.GetString(lang, sizeof(lang));
	if (!StrEqual(lang, "default")) {
		char langName[32];
		if (StrEqual(lang, "pt")) strcopy(langName, sizeof(langName), "Portuguese");
		else if (StrEqual(lang, "es")) strcopy(langName, sizeof(langName), "Spanish");
		else if (StrEqual(lang, "fr")) strcopy(langName, sizeof(langName), "French");
		else if (StrEqual(lang, "de")) strcopy(langName, sizeof(langName), "German");
		else if (StrEqual(lang, "ru")) strcopy(langName, sizeof(langName), "Russian");
		else if (StrEqual(lang, "zh")) strcopy(langName, sizeof(langName), "Chinese");
		else strcopy(langName, sizeof(langName), lang);
		Format(finalSystem, sizeof(finalSystem), "%s Answer in %s.", finalSystem, langName);
	}

	if (g_DebugCvar.BoolValue) {
		char dbg[1024]; int dp = 0;
		dp += Format(dbg[dp], sizeof(dbg)-dp, "[sys] \"%s\"", finalSystem);
		if (historyJSON[0]) {
			JSONArray histDbg = JSONArray.FromString(historyJSON);
			if (histDbg != null) {
				for (int i = 0; i < histDbg.Length && dp < 800; i++) {
					JSONObject hm = view_as<JSONObject>(histDbg.Get(i));
					if (hm != null) {
						char role[32], content[128];
						hm.GetString("role", role, sizeof(role));
						hm.GetString("content", content, sizeof(content));
						int cl = strlen(content); if (cl > 120) { content[120] = '\0'; }
						dp += Format(dbg[dp], sizeof(dbg)-dp, " [%s] \"%s\"", role, content);
						delete hm;
					}
				}
				delete histDbg;
			}
		}
		dp += Format(dbg[dp], sizeof(dbg)-dp, " [usr] \"%s\"", finalPrompt);
		PrintToServer("[NVD] 📝 %s", dbg);
	}

	char url[64]; Format(url, sizeof(url), "/api/%s/", endpoint);
	JSONObject payload = new JSONObject();
	payload.SetString("model", model);
	payload.SetBool("stream", false);
	if (StrEqual(endpoint, "chat")) {
		JSONArray msgs = new JSONArray();
		JSONObject sys = new JSONObject(); sys.SetString("role", "system"); sys.SetString("content", finalSystem); msgs.Push(sys); delete sys;
		
		// Inject history as separate messages (JSON array: [{"role":"fnx","content":"msg"},...])
		if (historyJSON[0]) {
			JSONArray history = JSONArray.FromString(historyJSON);
			if (history != null) {
				for (int i = 0; i < history.Length; i++) {
					JSONObject histMsg = view_as<JSONObject>(history.Get(i));
					if (histMsg != null) {
						msgs.Push(histMsg);
						delete histMsg;
					}
				}
				delete history;
			}
		}
		
		bool merged = false;
		if (msgs.Length > 0) {
			JSONObject last = view_as<JSONObject>(msgs.Get(msgs.Length - 1));
			char lastRole[32]; last.GetString("role", lastRole, sizeof(lastRole));
			if (StrEqual(lastRole, "user")) {
				char lastContent[2048], newContent[3072];
				last.GetString("content", lastContent, sizeof(lastContent));
				Format(newContent, sizeof(newContent), "%s\n%s", lastContent, finalPrompt);
				last.SetString("content", newContent);
				merged = true;
			}
			delete last;
		}

		if (!merged) {
			JSONObject usr = new JSONObject(); usr.SetString("role", "user"); usr.SetString("content", finalPrompt); msgs.Push(usr); delete usr;
		}
		payload.Set("messages", msgs); delete msgs;
	} else {
		payload.SetString("prompt", finalPrompt); payload.SetString("system", finalSystem);
	}
	JSONObject options = new JSONObject(); options.SetFloat("temperature", 0.8);
	options.SetString("keep_alive", "10m");
	payload.Set("options", options); delete options;

	PrintToServer("[NVD_DEBUG] SendRequest called for slot %d", slot);
	if (g_DumpCvar.BoolValue) {
		char dumpPath[PLATFORM_MAX_PATH], ts[32], line[8192];
		BuildPath(Path_SM, dumpPath, sizeof(dumpPath), "logs/nvd_ollama_dump.jsonl");
		PrintToServer("[NVD_DUMP] Writing to: %s", dumpPath);
		FormatTime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%S");

		char sysEsc[2048], usrEsc[1024];
		strcopy(sysEsc, sizeof(sysEsc), finalSystem); ReplaceString(sysEsc, sizeof(sysEsc), "\"", "\\\"");
		strcopy(usrEsc, sizeof(usrEsc), finalPrompt); ReplaceString(usrEsc, sizeof(usrEsc), "\"", "\\\"");

		Format(line, sizeof(line), "{\"ts\":\"%s\",\"model\":\"%s\",\"system\":\"%s\",\"history\":%s,\"user\":\"%s\"}",
			ts, model, sysEsc, historyJSON[0] ? historyJSON : "[]", usrEsc);
		
		File f = OpenFile(dumpPath, "a");
		if (f != null) {
			f.WriteLine(line);
			delete f;
		}
	}

	PrintToServer("[NVD_DEBUG] Sending POST to %s", url);
	
	// Store retry data
	payload.ToString(g_PendingRequests[slot].retryBody, sizeof(g_PendingRequests[slot].retryBody));
	strcopy(g_PendingRequests[slot].retryUrl, sizeof(g_PendingRequests[slot].retryUrl), url);
	g_PendingRequests[slot].retries = 0;
	g_PendingRequests[slot].timeout = timeout;
	g_PendingRequests[slot].requestTime = GetGameTime();
	strcopy(g_PendingRequests[slot].prompt, sizeof(g_PendingRequests[slot].prompt), finalPrompt);
	g_PendingRequests[slot].response[0] = '\0';

	g_HttpClient.Post(url, payload, OnOllamaResponse, slot);
	delete payload;
}

public int Native_PollResponse(Handle plugin, int numParams)
{
	if (g_PendingResponses == null || g_PendingResponses.Length == 0) return 0;
	
	char callerName[64];
	GetPluginFilename(plugin, callerName, sizeof(callerName));
	
	float now = GetGameTime();
	int maxlen = GetNativeCell(2);
	for (int i = 0; i < g_PendingResponses.Length; i++) {
		DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i));
		pack.Reset();
		
		char ownerName[64];
		pack.ReadString(ownerName, sizeof(ownerName));
		any cbData = pack.ReadCell();
		float queuedAt = pack.ReadFloat();
		
		if (StrEqual(ownerName, callerName)) {
			g_PendingResponses.Erase(i);
			SetNativeCellRef(3, cbData);
			char[] reply = new char[maxlen]; pack.ReadString(reply, maxlen);
			SetNativeString(1, reply, maxlen);
			delete pack; return 1;
		}
		if (now - queuedAt > RESPONSE_TTL)
		{
			g_PendingResponses.Erase(i);
			delete pack;
			i--;
		}
	}
	return 0;
}

public int Native_CanRequest(Handle plugin, int numParams) { return CheckRateLimit(GetNativeCell(1)); }

bool CheckRateLimit(int client)
{
	if (client < 1 || client > MAXPLAYERS) return true;
	float now = GetGameTime();
	if (now - g_WindowStart[client] > RATE_LIMIT_WINDOW)
	{
		g_WindowStart[client] = now;
		g_PlayerRequestCount[client] = 0;
	}
	g_PlayerRequestCount[client]++;
	return g_PlayerRequestCount[client] <= MAX_REQUESTS_PER_WINDOW;
}

int AllocateSlot(Function cb, any data, Handle plugin, const char[] ownerName)
{
	int maxSlots = GetMaxPending();
	for (int i = 0; i < maxSlots; i++) if (!g_PendingRequests[i].inUse) {
		g_PendingRequests[i].callback = cb; g_PendingRequests[i].callbackData = data;
		g_PendingRequests[i].plugin = plugin; g_PendingRequests[i].inUse = true;
		strcopy(g_PendingRequests[i].ownerName, 64, ownerName);
		g_PendingRequests[i].requestTime = GetGameTime();
		return i;
	}
	return -1;
}

bool FreeSlot(int id, Function &cb, any &data, Handle &plugin, char[] ownerName)
{
	if (id < 0 || id >= GetMaxPending() || !g_PendingRequests[id].inUse) return false;
	cb = g_PendingRequests[id].callback; data = g_PendingRequests[id].callbackData; 
	plugin = g_PendingRequests[id].plugin;
	strcopy(ownerName, 64, g_PendingRequests[id].ownerName);
	g_PendingRequests[id].inUse = false;
	ProcessQueue();
	return true;
}

void ProcessQueue()
{
	if (g_RequestQueue == null || g_RequestQueue.Length == 0) return;
	int maxSlots = GetMaxPending();
	int active = 0; for (int i = 0; i < maxSlots; i++) if (g_PendingRequests[i].inUse) active++;
	if (active < g_ConcurrencyCvar.IntValue) {
	int bestIdx = -1; int bestPrio = -1;
	for (int i = 0; i < g_RequestQueue.Length; i++) {
		DataPack dp = view_as<DataPack>(g_RequestQueue.Get(i)); dp.Reset();
		dp.ReadCell(); dp.ReadFunction(); dp.ReadCell(); // skip plugin, cb, cbData
		char dummy[16]; dp.ReadString(dummy, sizeof(dummy)); // skip prompt
		dp.ReadString(dummy, sizeof(dummy)); // skip system
		dp.ReadString(dummy, sizeof(dummy)); // skip model
		dp.ReadString(dummy, sizeof(dummy)); // skip endpoint
		dp.ReadString(dummy, sizeof(dummy)); // skip ownerName
		dp.ReadString(dummy, sizeof(dummy)); // skip historyJSON
		int prio = (dp.ReadCell() > 0) ? 1 : 0;
		if (prio > bestPrio) { bestPrio = prio; bestIdx = i; }
	}
	if (bestIdx == -1) bestIdx = 0;
	DataPack pack = view_as<DataPack>(g_RequestQueue.Get(bestIdx)); g_RequestQueue.Erase(bestIdx); pack.Reset();
	Handle ownerPlugin = view_as<Handle>(pack.ReadCell()); Function cb = pack.ReadFunction(); any cbData = pack.ReadCell();
	char prompt[512], system[2048], model[64], endpoint[32], ownerName[64], historyJSON[2048];
	pack.ReadString(prompt, sizeof(prompt)); pack.ReadString(system, sizeof(system));
	pack.ReadString(model, sizeof(model)); pack.ReadString(endpoint, sizeof(endpoint));
	pack.ReadString(ownerName, sizeof(ownerName));
	pack.ReadString(historyJSON, sizeof(historyJSON));
	pack.ReadCell(); // skip priority
	float timeout = pack.ReadFloat();
	int retries = pack.ReadCell();
	float startTime = pack.ReadFloat();
	delete pack;

	int slot = AllocateSlot(cb, cbData, ownerPlugin, ownerName);
	if (slot != -1) {
		g_PendingRequests[slot].retries = retries;
		g_PendingRequests[slot].requestTime = startTime;
		SendRequest(slot, prompt, system, model, endpoint, historyJSON, timeout);
	}
	}
}

public Action Timer_RetryRequest(Handle timer, DataPack pack)
{
	pack.Reset();
	int slotId = pack.ReadCell();
	delete pack;

	if (slotId < 0 || slotId >= MAX_PENDING || !g_PendingRequests[slotId].inUse)
		return Plugin_Stop;

	if (g_PendingRequests[slotId].retryUrl[0] == '\0')
		return Plugin_Stop;

	// Rebuild payload from stored JSON string
	JSONObject payload = JSONObject.FromString(g_PendingRequests[slotId].retryBody);
	if (payload == null) {
		PrintToServer("[NVD] ❌ Failed to rebuild retry payload (Slot %d)", slotId);
		Function cb; any data; Handle plugin; char ownerName[64];
		FreeSlot(slotId, cb, data, plugin, ownerName);
		QueueResponse(ownerName, "ERROR_JSON", data);
		return Plugin_Stop;
	}

	PrintToServer("[NVD_DEBUG] Retry POST to %s (attempt %d)", g_PendingRequests[slotId].retryUrl, g_PendingRequests[slotId].retries + 1);
	g_HttpClient.Post(g_PendingRequests[slotId].retryUrl, payload, OnOllamaResponse, slotId);
	delete payload;
	return Plugin_Stop;
}

public Action Timer_RequeueRequest(Handle timer, DataPack pack)
{
	pack.Reset();
	Handle plugin = pack.ReadCell();
	Function cb = pack.ReadFunction();
	any cbData = pack.ReadCell();
	char prompt[1024], system[3072], model[64], endpoint[32], ownerName[64], historyJSON[2048];
	pack.ReadString(prompt, sizeof(prompt));
	pack.ReadString(system, sizeof(system));
	pack.ReadString(model, sizeof(model));
	pack.ReadString(endpoint, sizeof(endpoint));
	pack.ReadString(ownerName, sizeof(ownerName));
	pack.ReadString(historyJSON, sizeof(historyJSON));
	float timeout = pack.ReadFloat();
	int retries = pack.ReadCell();
	float startTime = pack.ReadFloat();
	delete pack;

	DataPack newPack = new DataPack();
	newPack.WriteCell(plugin);
	newPack.WriteFunction(cb);
	newPack.WriteCell(cbData);
	newPack.WriteString(prompt);
	newPack.WriteString(system);
	newPack.WriteString(model);
	newPack.WriteString(endpoint);
	newPack.WriteString(ownerName);
	newPack.WriteString(historyJSON);
	newPack.WriteCell(1); // priority high for retries
	newPack.WriteFloat(timeout);
	newPack.WriteCell(retries);
	newPack.WriteFloat(startTime);
	
	g_RequestQueue.ShiftUp(0);
	g_RequestQueue.Set(0, newPack);
	ProcessQueue();
	return Plugin_Stop;
}

public void OnOllamaResponse(HTTPResponse response, any slotId)
{
	if (slotId < 0 || slotId >= MAX_PENDING || !g_PendingRequests[slotId].inUse) return;

	float latency = GetGameTime() - g_PendingRequests[slotId].requestTime;
	PrintToServer("[NVD] Latency: %.2fs", latency);

	if (view_as<int>(response.Status) == 307) {
		float elapsed = GetGameTime() - g_PendingRequests[slotId].requestTime;
		if (g_PendingRequests[slotId].retries < g_MaxRetriesCvar.IntValue && (g_PendingRequests[slotId].timeout == 0.0 || elapsed < g_PendingRequests[slotId].timeout)) {
			int retries = g_PendingRequests[slotId].retries + 1;
			float delay = 6.0;
			PrintToServer("[NVD] ⏳ Model loading (307), retry %d in %.0fs... (re-queueing)", retries, delay);

			DataPack retryPack = new DataPack();
			retryPack.WriteString(g_PendingRequests[slotId].origPrompt);
			retryPack.WriteString(g_PendingRequests[slotId].origSystem);
			retryPack.WriteString(g_PendingRequests[slotId].origModel);
			retryPack.WriteString(g_PendingRequests[slotId].origEndpoint);
			retryPack.WriteString(g_PendingRequests[slotId].ownerName);
			retryPack.WriteString(g_PendingRequests[slotId].origHistory);
			retryPack.WriteCell(g_PendingRequests[slotId].plugin);
			retryPack.WriteFunction(g_PendingRequests[slotId].callback);
			retryPack.WriteCell(g_PendingRequests[slotId].callbackData);
			retryPack.WriteFloat(g_PendingRequests[slotId].timeout);
			retryPack.WriteCell(retries);
			retryPack.WriteFloat(g_PendingRequests[slotId].requestTime); // Preserve original start time
			
			CreateTimer(delay, Timer_RequeueRequest, retryPack);

			Function cb; any data; Handle plugin; char ownerName[64];
			FreeSlot(slotId, cb, data, plugin, ownerName); // Free slot immediately so others can use it
			return;
		} else {
			PrintToServer("[NVD] ❌ Model loading failed after maximum retries (Slot %d)", slotId);
			strcopy(g_PendingRequests[slotId].response, 512, "MAX_RETRIES_REACHED");
			RecordOllamaHistory(slotId, false);
			Function cb; any data; Handle plugin; char ownerName[64];
			FreeSlot(slotId, cb, data, plugin, ownerName);
			QueueResponse(ownerName, "ERROR_TIMEOUT", data);
			return;
		}
	}

	if (response.Status != HTTPStatus_OK) { 
		PrintToServer("[NVD] ❌ Ollama HTTP Error: %d (Slot %d, Plugin %s)", response.Status, slotId, g_PendingRequests[slotId].ownerName);
		strcopy(g_PendingRequests[slotId].response, 512, "HTTP_ERROR");
		RecordOllamaHistory(slotId, false);
		Function cb; any data; Handle plugin; char ownerName[64];
		FreeSlot(slotId, cb, data, plugin, ownerName);
		QueueResponse(ownerName, "ERROR_HTTP", data); 
		return; 
	}
	JSONObject json = view_as<JSONObject>(response.Data);
	if (json == null) {
		PrintToServer("[NVD] ❌ Ollama Error: Invalid JSON response (Plugin %s)", g_PendingRequests[slotId].ownerName);
		strcopy(g_PendingRequests[slotId].response, 512, "JSON_ERROR");
		RecordOllamaHistory(slotId, false);
		Function cb; any data; Handle plugin; char ownerName[64];
		FreeSlot(slotId, cb, data, plugin, ownerName);
		QueueResponse(ownerName, "ERROR_JSON", data);
		return;
	}
	char reply[2048];
	if (json.GetString("response", reply, sizeof(reply))) {
		// Ollama /api/generate format
	} else {
		// Determine format from raw JSON string to avoid exceptions
		char rawFmt[256];
		json.ToString(rawFmt, sizeof(rawFmt));
		bool isOpenAI = (StrContains(rawFmt, "\"choices\"") != -1);
		bool isOllamaChat = (StrContains(rawFmt, "\"done\"") != -1 || StrContains(rawFmt, "\"message\":") != -1);

		if (isOpenAI) {
			JSONArray choices = view_as<JSONArray>(json.Get("choices"));
			if (choices != null && choices.Length > 0) {
				JSONObject choice = view_as<JSONObject>(choices.Get(0));
				if (choice != null) {
					JSONObject oaiMsg = view_as<JSONObject>(choice.Get("message"));
					if (oaiMsg != null) {
						oaiMsg.GetString("content", reply, sizeof(reply));
						delete oaiMsg;
					}
					delete choice;
				}
				delete choices;
			}
		}
		if (isOllamaChat && !reply[0]) {
			JSONObject msg = view_as<JSONObject>(json.Get("message"));
			if (msg != null) {
				msg.GetString("content", reply, sizeof(reply));
				delete msg;
			}
		}
	}
	delete json;

	strcopy(g_PendingRequests[slotId].response, 512, reply);
	RecordOllamaHistory(slotId, reply[0] != '\0');

	Function cb; any data; Handle plugin; char ownerName[64];
	if (!FreeSlot(slotId, cb, data, plugin, ownerName)) return;

	if (!reply[0]) return;
	if (cb != INVALID_FUNCTION)
	{
		Call_StartFunction(plugin, cb);
		Call_PushString(reply);
		Call_PushCell(data);
		Call_Finish();
	}
	else
		QueueResponse(ownerName, reply, data);
}
