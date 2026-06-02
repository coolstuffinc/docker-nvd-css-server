#include <sourcemod>
#include <ripext>
#include <nvd_core>

// ============================================================================
// POOL DE CALLBACKS (isso SIM é essencial - evita race condition)
// ============================================================================
enum struct PendingRequest
{
    Function callback;
    any callbackData;
    Handle callerPlugin;
    bool inUse;
}

#define MAX_PENDING 8
PendingRequest g_PendingRequests[MAX_PENDING];

HTTPClient g_HttpClient;
ConVar g_IpCvar, g_PortCvar, g_ModelCvar, g_EndpointCvar, g_DebugCvar;
char g_BaseUrl[256];

public Plugin myinfo =
{
    name = "NVD Core",
    author = "OpenCode", 
    description = "NVD AI Framework - HTTP/Ollama bridge for SourcePawn",
    version = "1.1.2",
    url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("NVD_AskAI", Native_AskAI);
    RegPluginLibrary("nvd_core");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_IpCvar = CreateConVar("nvd_ollama_ip", "172.17.0.1", "Ollama server IP");
    g_PortCvar = CreateConVar("nvd_ollama_port", "11433", "Ollama server port");
    g_ModelCvar = CreateConVar("nvd_ollama_model", "nvd-admin", "Ollama model name");
    g_EndpointCvar = CreateConVar("nvd_ollama_endpoint", "chat", "API endpoint: chat or generate");
    g_DebugCvar = CreateConVar("nvd_ollama_debug", "1", "Enable debug logging");
    AutoExecConfig(true, "nvd_core");

    RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK, "Test Ollama connectivity");
    
    for (int i = 0; i < MAX_PENDING; i++)
        g_PendingRequests[i].inUse = false;
}

public void OnPluginEnd()
{
    for (int i = 0; i < MAX_PENDING; i++)
        if (g_PendingRequests[i].inUse && g_PendingRequests[i].callerPlugin != INVALID_HANDLE)
            CloseHandle(g_PendingRequests[i].callerPlugin);
}

public void OnConfigsExecuted()
{
    char ip[64], port[16];
    g_IpCvar.GetString(ip, sizeof(ip));
    g_PortCvar.GetString(port, sizeof(port));
    Format(g_BaseUrl, sizeof(g_BaseUrl), "http://%s:%s/", ip, port);

    g_HttpClient = new HTTPClient(g_BaseUrl);
    g_HttpClient.FollowLocation = true;
    g_HttpClient.SetHeader("Content-Type", "application/json");
    g_HttpClient.SetHeader("User-Agent", "SourceMod-NVD-AI/1.1");

    if (g_DebugCvar.BoolValue)
        LogMessage("NVD Core: HTTPClient @ %s", g_BaseUrl);
}

// ============================================================================
// POOL HELPERS
// ============================================================================
int AllocateSlot(Function cb, any data, Handle plugin)
{
    for (int i = 0; i < MAX_PENDING; i++)
    {
        if (!g_PendingRequests[i].inUse)
        {
            g_PendingRequests[i].callback = cb;
            g_PendingRequests[i].callbackData = data;
            g_PendingRequests[i].callerPlugin = (plugin != INVALID_HANDLE) ? CloneHandle(plugin) : INVALID_HANDLE;
            g_PendingRequests[i].inUse = true;
            return i;
        }
    }
    LogError("NVD Core: No free callback slots");
    return -1;
}

bool FreeSlot(int id, Function &cb, any &data, Handle &plugin)
{
    if (id < 0 || id >= MAX_PENDING || !g_PendingRequests[id].inUse)
        return false;
    
    cb = g_PendingRequests[id].callback;
    data = g_PendingRequests[id].callbackData;
    plugin = g_PendingRequests[id].callerPlugin;
    
    g_PendingRequests[id].inUse = false;
    g_PendingRequests[id].callback = null;
    g_PendingRequests[id].callerPlugin = INVALID_HANDLE;
    return true;
}

// ============================================================================
// COMANDO DE TESTE
// ============================================================================
public Action Command_OllamaTest(int client, int args)
{
	if (g_HttpClient == null)
	{
		ReplyToCommand(client, "\x04[NVD]\x03 HTTPClient not initialized");
		return Plugin_Handled;
	}

	char model[64], endpoint[16];
	g_ModelCvar.GetString(model, sizeof(model));
	g_EndpointCvar.GetString(endpoint, sizeof(endpoint));

	JSONObject payload = new JSONObject();
	payload.SetString("model", model);
	payload.SetBool("stream", false);

	if (StrEqual(endpoint, "chat"))
	{
		JSONObject userMsg = new JSONObject();
		userMsg.SetString("role", "user");
		userMsg.SetString("content", "ping");

		JSONArray messages = new JSONArray();
		messages.Push(userMsg);
		payload.Set("messages", messages);
		delete userMsg;
		delete messages;
	}
	else
	{
		payload.SetString("prompt", "ping");
	}

	char url[64];
	Format(url, sizeof(url), "api/%s", endpoint);
	
	g_HttpClient.Post(url, payload, OnTestResponse, client);
	delete payload;
	return Plugin_Handled;
}

public void OnOllamaResponse(HTTPResponse response, any data)
{
	if (response.Status != HTTPStatus_OK)
	{
		LogError("NVD Core: Ollama returned status %d", response.Status);
		return;
	}

	if (response.Data == null) return;

	JSONObject json = view_as<JSONObject>(response.Data);
	char reply[2048];

	if (!json.GetString("response", reply, sizeof(reply)))
	{
		JSONObject msg;
		if (json.GetObject("message", msg))
		{
			msg.GetString("content", reply, sizeof(reply));
			delete msg;
		}
	}

	if (reply[0] != '\0')
	{
		if (g_DebugCvar.BoolValue)
			LogMessage("NVD Core: Ollama response: %s", reply);

		if (data != 0 && IsClientInGame(data))
			PrintToChat(data, "\x04[NVD]\x03 AI Reply: %s", reply);
			
		Call_StartFunction(INVALID_HANDLE, g_Callback);
		Call_PushString(reply);
		Call_PushCell(g_CallbackData);
		Call_Finish();
	}

	delete json;
}

    if (client > 0 && IsClientInGame(client))
        PrintToChat(client, "[NVD] Testing Ollama...");
    else
        PrintToServer("[NVD] Testing Ollama...");

    JSONObject payload = new JSONObject();
    payload.SetString("model", "nvd-admin");
    payload.SetString("prompt", "ping");
    payload.SetBool("stream", false);

    char url[64], endpoint[32];
    g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    Format(url, sizeof(url), "api/%s", endpoint);  // ← SIMPLES!

    g_HttpClient.Post(url, payload, OnOllamaResponse, client);  // ← passa client como data
    delete payload;
    return Plugin_Handled;
}

// ============================================================================
// NATIVE: NVD_AskAI
// ============================================================================
public int Native_AskAI(Handle plugin, int numParams)
{
    if (g_HttpClient == null) { LogError("NVD Core: HTTPClient not ready"); return 0; }
    if (numParams < 4) { LogError("NVD_AskAI: needs 4 params"); return 0; }

    char prompt[512], system[2048];
    GetNativeString(1, prompt, sizeof(prompt));
    GetNativeString(2, system, sizeof(system));
    
    Function callback = GetNativeFunction(3);
    any cbData = GetNativeCell(4);

    int slot = AllocateSlot(callback, cbData, plugin);
    if (slot == -1) return 0;

    char model[64], endpoint[32], url[64];
    g_ModelCvar.GetString(model, sizeof(model));
    g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    Format(url, sizeof(url), "api/%s", endpoint);  // ← SIMPLES!

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

    if (g_DebugCvar.BoolValue)
        LogMessage("NVD_AskAI: POST %s (slot=%d)", url, slot);

    g_HttpClient.Post(url, payload, OnOllamaResponse, slot);  // ← passa slot como data
    delete payload;
    return 1;
}

// ============================================================================
// CALLBACK HTTP
// ============================================================================
public void OnOllamaResponse(HTTPResponse response, any slotId)
{
    Function callback;
    any cbData;
    Handle callerPlugin;
    
    if (!FreeSlot(view_as<int>(slotId), callback, cbData, callerPlugin))
    {
        LogError("NVD Core: Invalid callback slot %d", slotId);
        return;
    }

    // Erro HTTP?
    if (response.Status != HTTPStatus_OK)
    {
        LogError("NVD Core: HTTP %d", response.Status);
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("");
            Call_PushCell(cbData);
            Call_Finish();
        }
        if (callerPlugin != INVALID_HANDLE) CloseHandle(callerPlugin);
        return;
    }

    if (response.Data == null)
    {
        LogError("NVD Core: null response");
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("");
            Call_PushCell(cbData);
            Call_Finish();
        }
        if (callerPlugin != INVALID_HANDLE) CloseHandle(callerPlugin);
        return;
    }

    JSONObject json = view_as<JSONObject>(response.Data);
    char reply[2048];

    // Tenta vários formatos de resposta
    if (!json.GetString("response", reply, sizeof(reply)))
    {
        JSONObject msg = view_as<JSONObject>(json.Get("message"));
        if (msg != null) { msg.GetString("content", reply, sizeof(reply)); delete msg; }
    }
    
    if (reply[0] == '\0')
    {
        JSONArray choices = view_as<JSONArray>(json.Get("choices"));
        if (choices != null && choices.Length > 0)
        {
            JSONObject choice = view_as<JSONObject>(choices.Get(0));
            if (choice != null)
            {
                JSONObject message = view_as<JSONObject>(choice.Get("message"));
                if (message != null)
                {
                    message.GetString("content", reply, sizeof(reply));
                    delete message;
                }
                delete choice;
            }
            delete choices;
        }
    }
    delete json;

    if (reply[0] == '\0')
    {
        LogError("NVD Core: empty response");
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("");
            Call_PushCell(cbData);
            Call_Finish();
        }
        if (callerPlugin != INVALID_HANDLE) CloseHandle(callerPlugin);
        return;
    }

    if (g_DebugCvar.BoolValue)
        LogMessage("NVD Reply: %.300s%s", reply, strlen(reply)>300?"...":"");

    // Chama o callback do plugin
    if (callback != null && callerPlugin != INVALID_HANDLE)
    {
        Call_StartFunction(callerPlugin, callback);
        Call_PushString(reply);
        Call_PushCell(cbData);
        Call_Finish();
    }
    
    if (callerPlugin != INVALID_HANDLE)
        CloseHandle(callerPlugin);
}
