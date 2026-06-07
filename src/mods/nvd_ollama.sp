#include <sourcemod>
#include <ripext>
#include <nvd_core>

#pragma semicolon 1
#pragma newdecls required

// ── Polling-based response queue ──
ArrayList g_PendingResponses = null;

#define MAX_RESPONSE_QUEUE 64
#define RESPONSE_TTL 60.0

// Enfileira a resposta armazenando o Handle do plugin dono
stock void QueueResponse(Handle plugin, const char[] reply, any cbData)
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
	pack.WriteCell(plugin);
	pack.WriteCell(cbData);
	pack.WriteFloat(GetGameTime());
	pack.WriteString(reply);
	pack.Reset();
	g_PendingResponses.Push(pack);

	PrintToServer("[NVD] [%s] 📨 Response queued (%d pending): \"%s\"", ts, g_PendingResponses.Length, reply);
}

enum struct PendingRequest
{
	Function callback;
	any callbackData;
	Handle plugin; // Armazena o plugin para o polling
	char playerName[32];
	int playerId;
	float requestTime;
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
ConVar g_IpCvar, g_PortCvar, g_ModelCvar, g_EndpointCvar, g_DebugCvar;
ConVar g_TimeoutCvar, g_ConcurrencyCvar;
char g_BaseUrl[256];

// ── NOVA FILA DE REQUISIÇÕES ──
ArrayList g_RequestQueue;

public Plugin myinfo = { name = "NVD Ollama", author = "OpenCode", description = "Ollama AI bridge with queue", version = "2.1.0" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("NVD_AskAI", Native_AskAI);
	CreateNative("NVD_CanRequest", Native_CanRequest);
	CreateNative("NVD_PollResponse", Native_PollResponse);
	RegPluginLibrary("nvd_core");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_IpCvar = CreateConVar("nvd_ollama_ip", "172.17.0.1");
	g_PortCvar = CreateConVar("nvd_ollama_port", "11433");
	g_ModelCvar = CreateConVar("nvd_ollama_model", "qwen2.5:1.5b");
	g_EndpointCvar = CreateConVar("nvd_ollama_endpoint", "chat");
	g_DebugCvar = CreateConVar("nvd_ollama_debug", "1");
	g_TimeoutCvar = CreateConVar("nvd_ollama_timeout", "30.0", "Safety timeout in seconds");
	g_ConcurrencyCvar = CreateConVar("nvd_ollama_concurrency", "2", "Max concurrent AI requests (1-8)");

	RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK);
	RegAdminCmd("sm_ollama_status", Command_OllamaStatus, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ollama_reload", Command_OllamaReload, ADMFLAG_KICK);

	for (int i = 0; i < MAX_PENDING; i++)
		g_PendingRequests[i].inUse = false;

	g_RequestQueue = new ArrayList();

	CreateTimer(15.0, Timer_CleanupQueue, _, TIMER_REPEAT);
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
		pack.ReadCell(); // skip plugin
		pack.ReadCell(); // skip cbData
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

	g_HttpClient.Post("/api/chat", payload, OnWarmupResponse, 0);
	delete payload;
}

public void OnWarmupResponse(HTTPResponse response, any data)
{
	if (response.Status == HTTPStatus_OK)
		PrintToServer("[NVD] ✅ Warmup OK");
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
			Function cb; any data; Handle plugin;
			FreeSlot(i, cb, data, plugin);
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
	g_HttpClient.Post("/api/chat", payload, OnTestResponse, pack);
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
	char prompt[512], system[2048];
	GetNativeString(1, prompt, sizeof(prompt));
	GetNativeString(2, system, sizeof(system));
	Function cb = GetNativeFunction(3);
	any cbData = GetNativeCell(4);
	int client = (numParams >= 5) ? GetNativeCell(5) : -1;
	float customTimeout = (numParams >= 6) ? GetNativeCell(6) : 0.0;

	char model[64], endpoint[32];
	g_ModelCvar.GetString(model, sizeof(model));
	g_EndpointCvar.GetString(endpoint, sizeof(endpoint));

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
		pack.WriteCell(client);
		pack.WriteFloat(customTimeout);
		g_RequestQueue.Push(pack);
		return 1;
	}

	int slot = AllocateSlot(cb, cbData, plugin, client);
	if (slot == -1) return 0;
	SendRequest(slot, prompt, system, model, endpoint, client, customTimeout);
	return 1;
}

void SendRequest(int slot, const char[] prompt, const char[] system, const char[] model, const char[] endpoint, int client, float customTimeout = 0.0)
{
	char url[64]; Format(url, sizeof(url), "/api/%s", endpoint);
	JSONObject payload = new JSONObject();
	payload.SetString("model", model);
	payload.SetBool("stream", false);
	if (StrEqual(endpoint, "chat")) {
		JSONArray msgs = new JSONArray();
		JSONObject sys = new JSONObject(); sys.SetString("role", "system"); sys.SetString("content", system); msgs.Push(sys); delete sys;
		JSONObject usr = new JSONObject(); usr.SetString("role", "user"); usr.SetString("content", prompt); msgs.Push(usr); delete usr;
		payload.Set("messages", msgs); delete msgs;
	} else {
		payload.SetString("prompt", prompt); payload.SetString("system", system);
	}
	JSONObject options = new JSONObject(); options.SetFloat("temperature", 0.8);
	payload.Set("options", options); delete options;
	g_HttpClient.Post(url, payload, OnOllamaResponse, slot);
	delete payload;
	
	float timeout = (customTimeout > 0.0) ? customTimeout : g_TimeoutCvar.FloatValue;
	CreateTimer(timeout, Timer_SafetyTimeout, slot);
}

public int Native_PollResponse(Handle plugin, int numParams)
{
	if (g_PendingResponses == null || g_PendingResponses.Length == 0) return 0;
	float now = GetGameTime();
	int maxlen = GetNativeCell(2);
	for (int i = 0; i < g_PendingResponses.Length; i++) {
		DataPack pack = view_as<DataPack>(g_PendingResponses.Get(i));
		pack.Reset();
		Handle owner = view_as<Handle>(pack.ReadCell());
		any cbData = pack.ReadCell();
		float queuedAt = pack.ReadFloat();
		if (owner == plugin) {
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

int AllocateSlot(Function cb, any data, Handle plugin, int client)
{
	for (int i = 0; i < MAX_PENDING; i++) if (!g_PendingRequests[i].inUse) {
		g_PendingRequests[i].callback = cb; g_PendingRequests[i].callbackData = data;
		g_PendingRequests[i].plugin = plugin; g_PendingRequests[i].inUse = true;
		g_PendingRequests[i].requestTime = GetGameTime();
		return i;
	}
	return -1;
}

bool FreeSlot(int id, Function &cb, any &data, Handle &plugin)
{
	if (id < 0 || id >= MAX_PENDING || !g_PendingRequests[id].inUse) return false;
	cb = g_PendingRequests[id].callback; data = g_PendingRequests[id].callbackData; plugin = g_PendingRequests[id].plugin;
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
		Handle owner = view_as<Handle>(pack.ReadCell()); Function cb = pack.ReadFunction(); any cbData = pack.ReadCell();
		char prompt[512], system[2048], model[64], endpoint[32];
		pack.ReadString(prompt, sizeof(prompt)); pack.ReadString(system, sizeof(system));
		pack.ReadString(model, sizeof(model)); pack.ReadString(endpoint, sizeof(endpoint));
		int client = pack.ReadCell();
		float customTimeout = pack.ReadFloat();
		delete pack;
		int slot = AllocateSlot(cb, cbData, owner, client);
		if (slot != -1) SendRequest(slot, prompt, system, model, endpoint, client, customTimeout);
	}
}

public Action Timer_SafetyTimeout(Handle timer, any slotId)
{
	Function cb; any data; Handle plugin;
	if (FreeSlot(slotId, cb, data, plugin)) QueueResponse(plugin, "ERROR_TIMEOUT", data);
	return Plugin_Stop;
}

public void OnOllamaResponse(HTTPResponse response, any slotId)
{
	Function cb; any data; Handle plugin;
	if (!FreeSlot(slotId, cb, data, plugin)) return;
	if (response.Status != HTTPStatus_OK) { QueueResponse(plugin, "ERROR_HTTP", data); return; }
	JSONObject json = view_as<JSONObject>(response.Data);
	char reply[2048];
	if (!json.GetString("response", reply, sizeof(reply))) {
		JSONObject msg = view_as<JSONObject>(json.Get("message"));
		if (msg != null) { msg.GetString("content", reply, sizeof(reply)); delete msg; }
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
		QueueResponse(plugin, reply, data);
}
