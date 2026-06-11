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
	char ownerName[64]; // Nome do plugin para polling persistente
	Handle plugin;     // Handle original para callbacks (apenas se for a mesma instância)
	char playerName[32];
	int playerId;
	float requestTime;
	char retryUrl[256];
	char retryBody[4096];
	int retries;
	bool inUse;
}

#define MAX_PENDING 8
PendingRequest g_PendingRequests[MAX_PENDING];

// ── Rate Limiting ──
#define RATE_LIMIT_WINDOW 5.0
#define MAX_REQUESTS_PER_WINDOW 3
float g_PlayerLastRequest[MAXPLAYERS + 1];
int g_PlayerRequestCount[MAXPLAYERS + 1];
float g_WindowStart[MAXPLAYERS + 1];

HTTPClient g_HttpClient;
ConVar g_IpCvar, g_PortCvar, g_ModelCvar, g_EndpointCvar, g_DebugCvar, g_DumpCvar;
ConVar g_ConcurrencyCvar;
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
	g_ConcurrencyCvar = CreateConVar("nvd_ollama_concurrency", "2", "Max concurrent AI requests (1-8)");

	g_LangCvar = CreateConVar("nvd_language", "default", "Global language for all NVD plugins");
	g_LangCvar.AddChangeHook(OnGlobalLanguageChanged);

	RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK);
	RegAdminCmd("sm_ollama_status", Command_OllamaStatus, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ollama_reload", Command_OllamaReload, ADMFLAG_KICK);

	for (int i = 0; i < MAX_PENDING; i++)
		g_PendingRequests[i].inUse = false;

	g_RequestQueue = new ArrayList();

	CreateTimer(15.0, Timer_CleanupQueue, _, TIMER_REPEAT);
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

public Action Command_OllamaStatus(int client, int args)
{
	int used = 0;
	for (int i = 0; i < MAX_PENDING; i++)
		if (g_PendingRequests[i].inUse) used++;

	ReplyToCommand(client, "[NVD] ═══ Ollama Status ═══");
	char model[64]; g_ModelCvar.GetString(model, sizeof(model));
	ReplyToCommand(client, "[NVD] Model: %s", model);
	int respLen = (g_PendingResponses != null) ? g_PendingResponses.Length : 0;
	ReplyToCommand(client, "[NVD] Queue: %d/%d active | %d waiting | %d pending", used, g_ConcurrencyCvar.IntValue, g_RequestQueue.Length, respLen);
	return Plugin_Handled;
}

public Action Command_OllamaReload(int client, int args)
{
	for (int i = 0; i < MAX_PENDING; i++)
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
		g_RequestQueue.Push(pack);
		return 1;
	}

	int slot = AllocateSlot(cb, cbData, plugin, ownerName);
	if (slot == -1) return 0;
	SendRequest(slot, prompt, system, model, endpoint, historyJSON);
	return 1;
}

void SendRequest(int slot, const char[] prompt, const char[] system, const char[] model, const char[] endpoint, const char[] historyJSON = "")
{
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
	for (int i = 0; i < MAX_PENDING; i++) if (!g_PendingRequests[i].inUse) {
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
	if (id < 0 || id >= MAX_PENDING || !g_PendingRequests[id].inUse) return false;
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
	int active = 0; for (int i = 0; i < MAX_PENDING; i++) if (g_PendingRequests[i].inUse) active++;
	if (active < g_ConcurrencyCvar.IntValue) {
		DataPack pack = view_as<DataPack>(g_RequestQueue.Get(0)); g_RequestQueue.Erase(0); pack.Reset();
		Handle ownerPlugin = view_as<Handle>(pack.ReadCell()); Function cb = pack.ReadFunction(); any cbData = pack.ReadCell();
		char prompt[512], system[2048], model[64], endpoint[32], ownerName[64], historyJSON[2048];
		pack.ReadString(prompt, sizeof(prompt)); pack.ReadString(system, sizeof(system));
		pack.ReadString(model, sizeof(model)); pack.ReadString(endpoint, sizeof(endpoint));
		pack.ReadString(ownerName, sizeof(ownerName));
		pack.ReadString(historyJSON, sizeof(historyJSON));
		delete pack;
		int slot = AllocateSlot(cb, cbData, ownerPlugin, ownerName);
		if (slot != -1) SendRequest(slot, prompt, system, model, endpoint, historyJSON);
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

public void OnOllamaResponse(HTTPResponse response, any slotId)
{
	if (slotId < 0 || slotId >= MAX_PENDING || !g_PendingRequests[slotId].inUse) return;

	float latency = GetGameTime() - g_PendingRequests[slotId].requestTime;
	PrintToServer("[NVD] Latency: %.2fs", latency);

	if (view_as<int>(response.Status) == 307) {
		if (g_PendingRequests[slotId].retries < 10) {
			g_PendingRequests[slotId].retries++;
			float delay = 6.0;
			PrintToServer("[NVD] ⏳ Model loading (307), retry %d in %.0fs...", g_PendingRequests[slotId].retries, delay);
			DataPack retryPack = new DataPack();
			retryPack.WriteCell(slotId);
			CreateTimer(delay, Timer_RetryRequest, retryPack);
		} else {
			PrintToServer("[NVD] ❌ Model loading failed after 10 retries (Slot %d)", slotId);
			Function cb; any data; Handle plugin; char ownerName[64];
			FreeSlot(slotId, cb, data, plugin, ownerName);
			QueueResponse(ownerName, "ERROR_TIMEOUT", data);
		}
		return;
	}

	Function cb; any data; Handle plugin; char ownerName[64];
	if (!FreeSlot(slotId, cb, data, plugin, ownerName)) return;

	if (response.Status != HTTPStatus_OK) { 
		PrintToServer("[NVD] ❌ Ollama HTTP Error: %d (Slot %d, Plugin %s)", response.Status, slotId, ownerName);
		QueueResponse(ownerName, "ERROR_HTTP", data); 
		return; 
	}
	JSONObject json = view_as<JSONObject>(response.Data);
	if (json == null) {
		PrintToServer("[NVD] ❌ Ollama Error: Invalid JSON response (Plugin %s)", ownerName);
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
