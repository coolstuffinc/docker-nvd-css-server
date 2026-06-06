#include <sourcemod>
#include <ripext>
#include <nvd_core>

enum struct PendingRequest
{
    Function callback;
    any callbackData;
    Handle callerPlugin;
    char playerName[32];
    int playerId;
    float requestTime;
    bool inUse;
}

#define MAX_PENDING 8
PendingRequest g_PendingRequests[MAX_PENDING];

// ── Rate Limiting ────────────────────────────────────────────────
#define RATE_LIMIT_WINDOW 5.0
#define MAX_REQUESTS_PER_WINDOW 3
float g_PlayerLastRequest[MAXPLAYERS + 1];
int g_PlayerRequestCount[MAXPLAYERS + 1];
float g_WindowStart[MAXPLAYERS + 1];

HTTPClient g_HttpClient;
ConVar g_IpCvar, g_PortCvar, g_ModelCvar, g_EndpointCvar, g_DebugCvar;
ConVar g_TimeoutCvar, g_ConcurrencyCvar;
char g_BaseUrl[256];

public Plugin myinfo = { name = "NVD Core", author = "OpenCode", description = "AI bridge with rate limiting", version = "2.0.0" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("NVD_AskAI", Native_AskAI);
    CreateNative("NVD_CanRequest", Native_CanRequest);
    RegPluginLibrary("nvd_core");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_IpCvar = CreateConVar("nvd_ollama_ip", "172.17.0.1");
    g_PortCvar = CreateConVar("nvd_ollama_port", "11433");
    g_ModelCvar = CreateConVar("nvd_ollama_model", "smollm2:1.7b-instruct-q4_K_M");
    g_EndpointCvar = CreateConVar("nvd_ollama_endpoint", "chat");
    g_DebugCvar = CreateConVar("nvd_ollama_debug", "1");
    g_TimeoutCvar = CreateConVar("nvd_ollama_timeout", "30.0", "Safety timeout in seconds");
    g_ConcurrencyCvar = CreateConVar("nvd_ollama_concurrency", "2", "Max concurrent AI requests (1-8)");
    
    RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK);
    RegAdminCmd("sm_ollama_status", Command_OllamaStatus, ADMFLAG_GENERIC);
    
    for (int i = 0; i < MAX_PENDING; i++)
        g_PendingRequests[i].inUse = false;
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
    g_HttpClient = new HTTPClient(g_BaseUrl);
    g_HttpClient.FollowLocation = true;
    g_HttpClient.SetHeader("Content-Type", "application/json");
    
    if (g_DebugCvar.BoolValue)
        PrintToServer("[NVD] Core v2.0 loaded → Ollama at %s, model: %s", g_BaseUrl, g_ModelCvar);
}

// ============================================================================
// COMMANDS
// ============================================================================
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
    
    ReplyToCommand(client, "[NVD] ═══ Status ═══");
    ReplyToCommand(client, "[NVD] Model: %s", g_ModelCvar);
    ReplyToCommand(client, "[NVD] Endpoint: %s:%s", g_IpCvar, g_PortCvar);
    ReplyToCommand(client, "[NVD] Queue: %d/%d active", used, g_ConcurrencyCvar.IntValue);
    ReplyToCommand(client, "[NVD] Timeout: %.0fs", g_TimeoutCvar.FloatValue);
    return Plugin_Handled;
}

void TestConnection(int client)
{
    char model[64];
    g_ModelCvar.GetString(model, sizeof(model));
    
    JSONObject payload = new JSONObject();
    payload.SetString("model", model);
    payload.SetBool("stream", false);
    
    JSONObject userMsg = new JSONObject();
    userMsg.SetString("role", "user");
    userMsg.SetString("content", "ping");
    JSONArray messages = new JSONArray();
    messages.Push(userMsg);
    payload.Set("messages", messages);
    delete userMsg;
    delete messages;
    
    DataPack pack = new DataPack();
    pack.WriteCell(client);
    
    g_HttpClient.Post("/api/chat", payload, OnTestResponse, pack);
    delete payload;
}

public void OnTestResponse(HTTPResponse response, DataPack pack)
{
    pack.Reset();
    int client = pack.ReadCell();
    delete pack;
    
    if (!IsClientInGame(client)) return;
    
    if (response.Status == HTTPStatus_OK)
    {
        JSONObject json = view_as<JSONObject>(response.Data);
        JSONObject msg = view_as<JSONObject>(json.Get("message"));
        if (msg != null)
        {
            char reply[256];
            msg.GetString("content", reply, sizeof(reply));
            ReplyToCommand(client, "[NVD] ✅ Ollama OK: \"%s\"", reply);
            delete msg;
        }
        else
            ReplyToCommand(client, "[NVD] ✅ Ollama connected (no message in response)");
        delete json;
    }
    else
    {
        ReplyToCommand(client, "[NVD] ❌ Ollama error: HTTP %d", response.Status);
    }
}

// ============================================================================
// NATIVE: NVD_AskAI
// ============================================================================
public int Native_AskAI(Handle plugin, int numParams)
{
    char prompt[512], system[2048];
    GetNativeString(1, prompt, sizeof(prompt));
    GetNativeString(2, system, sizeof(system));
    
    // Get optional client ID for rate limiting (param 5, added in v2)
    int client = -1;
    if (numParams >= 5)
        client = GetNativeCell(5);
    
    int slot = AllocateSlot(GetNativeFunction(3), GetNativeCell(4), plugin, client);
    if (slot == -1)
    {
        LogError("[NVD] All slots busy! Increase nvd_ollama_concurrency or check for stuck requests.");
        return 0;
    }
    
    char model[64], endpoint[32], url[64];
    g_ModelCvar.GetString(model, sizeof(model));
    g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    Format(url, sizeof(url), "/api/%s", endpoint);
    
    JSONObject payload = new JSONObject();
    payload.SetString("model", model);
    
    if (StrEqual(endpoint, "chat"))
    {
        JSONArray msgs = new JSONArray();
        JSONObject sys = new JSONObject();
        sys.SetString("role", "system");
        sys.SetString("content", system);
        msgs.Push(sys);
        delete sys;
        
        JSONObject usr = new JSONObject();
        usr.SetString("role", "user");
        usr.SetString("content", prompt);
        msgs.Push(usr);
        delete usr;
        
        payload.Set("messages", msgs);
        delete msgs;
    }
    else
    {
        payload.SetString("prompt", prompt);
        payload.SetString("system", system);
    }
    
    payload.SetBool("stream", false);
    
    g_HttpClient.Post(url, payload, OnOllamaResponse, slot);
    delete payload;
    
    // Safety timeout (configurable via nvd_ollama_timeout)
    float timeout = g_TimeoutCvar.FloatValue;
    CreateTimer(timeout, Timer_SafetyTimeout, slot, TIMER_FLAG_NO_MAPCHANGE);
    
    return 1;
}

// ============================================================================
// NATIVE: NVD_CanRequest (rate limit check)
// ============================================================================
public int Native_CanRequest(Handle plugin, int numParams)
{
    if (numParams < 1) return 0;
    int client = GetNativeCell(1);
    return CheckRateLimit(client) ? 1 : 0;
}

// ============================================================================
// RATE LIMITING
// ============================================================================
bool CheckRateLimit(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return true; // No limit for non-player callers
    
    float now = GetGameTime();
    
    // Reset window if expired
    if (now - g_WindowStart[client] > RATE_LIMIT_WINDOW)
    {
        g_WindowStart[client] = now;
        g_PlayerRequestCount[client] = 0;
    }
    
    g_PlayerRequestCount[client]++;
    
    if (g_PlayerRequestCount[client] > MAX_REQUESTS_PER_WINDOW)
    {
        float waitTime = RATE_LIMIT_WINDOW - (now - g_WindowStart[client]);
        if (waitTime > 0)
        {
            if (g_DebugCvar.BoolValue)
            {
                char name[32];
                GetClientName(client, name, sizeof(name));
                PrintToServer("[NVD] ⏱ Rate limit hit for %s (wait %.0fs)", name, waitTime);
            }
            return false;
        }
        // Reset if window has passed
        g_WindowStart[client] = now;
        g_PlayerRequestCount[client] = 1;
    }
    
    return true;
}

// ============================================================================
// SLOT MANAGEMENT
// ============================================================================
int AllocateSlot(Function cb, any data, Handle plugin, int client = -1)
{
    int maxConcurrent = g_ConcurrencyCvar.IntValue;
    if (maxConcurrent < 1) maxConcurrent = 1;
    if (maxConcurrent > MAX_PENDING) maxConcurrent = MAX_PENDING;
    
    // First check if we have capacity
    int active = 0;
    for (int i = 0; i < MAX_PENDING; i++)
        if (g_PendingRequests[i].inUse) active++;
    
    if (active >= maxConcurrent)
    {
        if (g_DebugCvar.BoolValue)
            PrintToServer("[NVD] ⚠️ Max concurrency reached (%d/%d), rejecting request", active, maxConcurrent);
        return -1;
    }
    
    // Find free slot
    for (int i = 0; i < MAX_PENDING; i++)
    {
        if (!g_PendingRequests[i].inUse)
        {
            g_PendingRequests[i].callback = cb;
            g_PendingRequests[i].callbackData = data;
            g_PendingRequests[i].callerPlugin = (plugin != INVALID_HANDLE) ? CloneHandle(plugin) : INVALID_HANDLE;
            g_PendingRequests[i].requestTime = GetGameTime();
            g_PendingRequests[i].playerId = client;
            g_PendingRequests[i].playerName[0] = '\0';
            
            if (client >= 1 && client <= MaxClients && IsClientInGame(client))
            {
                char pName[32];
                GetClientName(client, pName, sizeof(pName));
                strcopy(g_PendingRequests[i].playerName, sizeof(g_PendingRequests[i].playerName), pName);
            }
            
            g_PendingRequests[i].inUse = true;
            
            if (g_DebugCvar.BoolValue)
                PrintToServer("[NVD] 🤖 Request queued (slot %d, active: %d/%d)", i, active + 1, maxConcurrent);
            
            return i;
        }
    }
    return -1;
}

bool FreeSlot(int id, Function &cb, any &data, Handle &plugin)
{
    if (id < 0 || id >= MAX_PENDING || !g_PendingRequests[id].inUse)
        return false;
    
    cb = g_PendingRequests[id].callback;
    data = g_PendingRequests[id].callbackData;
    plugin = g_PendingRequests[id].callerPlugin;
    
    if (g_DebugCvar.BoolValue)
    {
        char name[32];
        strcopy(name, sizeof(name), g_PendingRequests[id].playerName);
        PrintToServer("[NVD] ✅ Slot %d freed (%s, held for %.1fs)", 
            id, name[0] ? name : "system", GetGameTime() - g_PendingRequests[id].requestTime);
    }
    
    g_PendingRequests[id].inUse = false;
    return true;
}

// ============================================================================
// CALLBACKS
// ============================================================================
public Action Timer_SafetyTimeout(Handle timer, any slotId)
{
    // Read player info BEFORE freeing the slot
    char playerInfo[64];
    if (slotId >= 0 && slotId < MAX_PENDING && g_PendingRequests[slotId].inUse)
        strcopy(playerInfo, sizeof(playerInfo), g_PendingRequests[slotId].playerName[0] ? g_PendingRequests[slotId].playerName : "system");
    else
        strcopy(playerInfo, sizeof(playerInfo), "unknown");
    
    Function callback; any cbData; Handle callerPlugin;
    if (!FreeSlot(slotId, callback, cbData, callerPlugin))
        return Plugin_Stop;
    
    LogError("[NVD] ⚠️ Request timed out (%.0fs) for %s", g_TimeoutCvar.FloatValue, playerInfo);
    PrintToServer("[NVD] ⚠️ Ollama request timed out (%.0fs). Check: curl http://%s/api/tags",
        g_TimeoutCvar.FloatValue, g_BaseUrl);
    
    // Notify caller plugin about timeout
    if (callback != null && callerPlugin != INVALID_HANDLE)
    {
        Call_StartFunction(callerPlugin, callback);
        Call_PushString("ERROR_TIMEOUT");
        Call_PushCell(cbData);
        Call_Finish();
    }
    
    if (callerPlugin != INVALID_HANDLE)
        CloseHandle(callerPlugin);
    
    return Plugin_Stop;
}

public void OnOllamaResponse(HTTPResponse response, any slotId)
{
    // Read player info BEFORE freeing the slot
    char playerInfo[32];
    if (slotId >= 0 && slotId < MAX_PENDING && g_PendingRequests[slotId].inUse)
        strcopy(playerInfo, sizeof(playerInfo), g_PendingRequests[slotId].playerName[0] ? g_PendingRequests[slotId].playerName : "system");
    else
        strcopy(playerInfo, sizeof(playerInfo), "unknown");
    
    Function callback; any cbData; Handle callerPlugin;
    if (!FreeSlot(slotId, callback, cbData, callerPlugin))
        return;
    
    if (response.Status != HTTPStatus_OK)
    {
        LogError("[NVD] ❌ HTTP %d for %s", response.Status, playerInfo);
        
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("ERROR_HTTP");
            Call_PushCell(cbData);
            Call_Finish();
        }
        
        if (callerPlugin != INVALID_HANDLE)
            CloseHandle(callerPlugin);
        return;
    }
    
    JSONObject json = view_as<JSONObject>(response.Data);
    char reply[2048];
    
    if (!json.GetString("response", reply, sizeof(reply)))
    {
        JSONObject msg = view_as<JSONObject>(json.Get("message"));
        if (msg != null)
        {
            msg.GetString("content", reply, sizeof(reply));
            delete msg;
        }
    }
    
    delete json;
    
    if (reply[0] != '\0' && callback != null && callerPlugin != INVALID_HANDLE)
    {
        Call_StartFunction(callerPlugin, callback);
        Call_PushString(reply);
        Call_PushCell(cbData);
        Call_Finish();
    }
    
    if (callerPlugin != INVALID_HANDLE)
        CloseHandle(callerPlugin);
}
