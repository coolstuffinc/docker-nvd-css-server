#include <sourcemod>
#include <ripext>
#include <nvd_core>

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

public Plugin myinfo = { name = "NVD Core", author = "OpenCode", description = "AI bridge", version = "1.2.0" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("NVD_AskAI", Native_AskAI);
    RegPluginLibrary("nvd_core");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_IpCvar = CreateConVar("nvd_ollama_ip", "172.17.0.1");
    g_PortCvar = CreateConVar("nvd_ollama_port", "11433");
    g_ModelCvar = CreateConVar("nvd_ollama_model", "nvd-admin");
    g_EndpointCvar = CreateConVar("nvd_ollama_endpoint", "chat");
    g_DebugCvar = CreateConVar("nvd_ollama_debug", "1");
    RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK);
    for (int i = 0; i < MAX_PENDING; i++) g_PendingRequests[i].inUse = false;
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
}

public Action Command_OllamaTest(int client, int args)
{
    ReplyToCommand(client, "[NVD] Testing Ollama...");
    char model[64], endpoint[32];
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
    else payload.SetString("prompt", "ping");
    char url[64];
    Format(url, sizeof(url), "/api/%s", endpoint);
    g_HttpClient.Post(url, payload, OnOllamaResponse, client);
    delete payload;
    return Plugin_Handled;
}

public int Native_AskAI(Handle plugin, int numParams)
{
    char prompt[512], system[2048];
    GetNativeString(1, prompt, sizeof(prompt));
    GetNativeString(2, system, sizeof(system));
    int slot = AllocateSlot(GetNativeFunction(3), GetNativeCell(4), plugin);
    if (slot == -1) return 0;
    char model[64], endpoint[32], url[64];
    g_ModelCvar.GetString(model, sizeof(model));
    g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    Format(url, sizeof(url), "/api/%s", endpoint);
    JSONObject payload = new JSONObject();
    payload.SetString("model", model);
    if (StrEqual(endpoint, "chat"))
    {
        JSONArray msgs = new JSONArray();
        JSONObject sys = new JSONObject(); sys.SetString("role", "system"); sys.SetString("content", system); msgs.Push(sys); delete sys;
        JSONObject usr = new JSONObject(); usr.SetString("role", "user"); usr.SetString("content", prompt); msgs.Push(usr); delete usr;
        payload.Set("messages", msgs);
        delete msgs;
    }
    else { payload.SetString("prompt", prompt); payload.SetString("system", system); }
    payload.SetBool("stream", false);
    g_HttpClient.Post(url, payload, OnOllamaResponse, slot);
    
    // Timer de segurança: força a liberação do slot se demorar mais que 30s
    // (modelos pequenos podem levar ~10s para carregar na VRAM)
    CreateTimer(30.0, Timer_SafetyTimeout, slot, TIMER_FLAG_NO_MAPCHANGE);
    
    delete payload;
    return 1;
}

public Action Timer_SafetyTimeout(Handle timer, any slotId)
{
    Function callback; any cbData; Handle callerPlugin;
    if (FreeSlot(slotId, callback, cbData, callerPlugin))
    {
        LogError("NVD Core: Request timed out for slot %d after 30s", slotId);
        PrintToServer("[NVD] ⚠️ Ollama request timed out (30s). Check if model is loaded: curl http://127.0.0.1:11433/api/tags");
        // Notifica o plugin chamador que houve timeout
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("ERROR_TIMEOUT");
            Call_PushCell(cbData);
            Call_Finish();
        }
        if (callerPlugin != INVALID_HANDLE) CloseHandle(callerPlugin);
    }
    return Plugin_Stop;
}

public void OnOllamaResponse(HTTPResponse response, any slotId)
{
    Function callback; any cbData; Handle callerPlugin;
    if (!FreeSlot(slotId, callback, cbData, callerPlugin)) return;
    if (response.Status != HTTPStatus_OK) { if (callerPlugin != INVALID_HANDLE) CloseHandle(callerPlugin); return; }
    JSONObject json = view_as<JSONObject>(response.Data);
    char reply[2048];
    if (!json.GetString("response", reply, sizeof(reply)))
    {
        JSONObject msg = view_as<JSONObject>(json.Get("message"));
        if (msg != null) { msg.GetString("content", reply, sizeof(reply)); delete msg; }
    }
    delete json;
    if (reply[0] != '\0')
    {
        Call_StartFunction(callerPlugin, callback);
        Call_PushString(reply);
        Call_PushCell(cbData);
        Call_Finish();
    }
    if (callerPlugin != INVALID_HANDLE) CloseHandle(callerPlugin);
}

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
    return -1;
}

bool FreeSlot(int id, Function &cb, any &data, Handle &plugin)
{
    if (id < 0 || id >= MAX_PENDING || !g_PendingRequests[id].inUse) return false;
    cb = g_PendingRequests[id].callback;
    data = g_PendingRequests[id].callbackData;
    plugin = g_PendingRequests[id].callerPlugin;
    g_PendingRequests[id].inUse = false;
    return true;
}
