#include <sourcemod>
#include <ripext>
#include <nvd_core>

// ============================================================================
// ESTRUTURA PARA ARMAZENAR CALLBACKS POR REQUISIÇÃO (evita race condition)
// ============================================================================
enum struct PendingRequest
{
    Function callback;
    any callbackData;
    Handle callerPlugin;  // ← Handle do plugin que chamou o native
    bool inUse;
}

// Pool de requisições pendentes (ajuste MAX_PENDING se necessário)
#define MAX_PENDING 8
PendingRequest g_PendingRequests[MAX_PENDING];

HTTPClient g_HttpClient;
ConVar g_IpCvar;
ConVar g_PortCvar;
ConVar g_ModelCvar;
ConVar g_EndpointCvar;
ConVar g_DebugCvar;
char g_BaseUrl[256];

public Plugin myinfo =
{
    name = "NVD Core",
    author = "OpenCode",
    description = "NVD AI Framework - HTTP/Ollama bridge for SourcePawn",
    version = "1.1.1",  // ← Atualizado
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
    g_EndpointCvar = CreateConVar("nvd_ollama_endpoint", "chat", "Ollama API endpoint: generate or chat");
    g_DebugCvar = CreateConVar("nvd_ollama_debug", "1", "Enable debug logging");
    AutoExecConfig(true, "nvd_core");

    RegAdminCmd("sm_ollama_test", Command_OllamaTest, ADMFLAG_KICK, "Test Ollama connectivity");
    
    // Inicializa pool de callbacks
    for (int i = 0; i < MAX_PENDING; i++)
    {
        g_PendingRequests[i].inUse = false;
        g_PendingRequests[i].callerPlugin = INVALID_HANDLE;
    }
}

public void OnPluginEnd()
{
    // Limpa handles de plugins armazenados
    for (int i = 0; i < MAX_PENDING; i++)
    {
        if (g_PendingRequests[i].inUse && g_PendingRequests[i].callerPlugin != INVALID_HANDLE)
        {
            CloseHandle(g_PendingRequests[i].callerPlugin);
        }
    }
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
    {
        LogMessage("NVD Core: HTTPClient initialized, base URL = %s", g_BaseUrl);
    }
}

// ============================================================================
// FUNÇÃO AUXILIAR: Aloca slot no pool de callbacks
// ============================================================================
int AllocatePendingSlot(Function callback, any data, Handle callerPlugin)
{
    for (int i = 0; i < MAX_PENDING; i++)
    {
        if (!g_PendingRequests[i].inUse)
        {
            g_PendingRequests[i].callback = callback;
            g_PendingRequests[i].callbackData = data;
            g_PendingRequests[i].callerPlugin = (callerPlugin != INVALID_HANDLE) ? CloneHandle(callerPlugin) : INVALID_HANDLE;
            g_PendingRequests[i].inUse = true;
            return i;
        }
    }
    LogError("NVD Core: No free pending request slots (max %d)", MAX_PENDING);
    return -1;
}

// ============================================================================
// FUNÇÃO AUXILIAR: Libera slot e retorna dados
// ============================================================================
bool FreePendingSlot(int slotId, Function &callback, any &data, Handle &pluginHandle)
{
    if (slotId < 0 || slotId >= MAX_PENDING || !g_PendingRequests[slotId].inUse)
        return false;
    
    callback = g_PendingRequests[slotId].callback;
    data = g_PendingRequests[slotId].callbackData;
    pluginHandle = g_PendingRequests[slotId].callerPlugin;
    
    g_PendingRequests[slotId].inUse = false;
    g_PendingRequests[slotId].callback = null;
    g_PendingRequests[slotId].callbackData = 0;
    g_PendingRequests[slotId].callerPlugin = INVALID_HANDLE;
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

    if (client == 0)
        PrintToServer("[NVD] Testing Ollama connectivity at %s...", g_BaseUrl);
    else if (IsClientInGame(client))
        PrintToChat(client, "\x04[NVD]\x03 Testing Ollama connectivity...", g_BaseUrl);

    g_DebugCvar.SetInt(1);

    JSONObject payload = new JSONObject();
    payload.SetString("model", "nvd-admin");
    payload.SetString("prompt", "ping");
    payload.SetBool("stream", false);

    char url[128], endpoint[16];
    g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    Format(url, sizeof(url), "api/%s", endpoint[0] == '/' ? endpoint[1] : endpoint);

    // ← PASSA "client" como data para OnOllamaResponse
    g_HttpClient.Post(url, payload, OnOllamaResponse, client);
    delete payload;
    return Plugin_Handled;
}

// ============================================================================
// NATIVE: NVD_AskAI
// ============================================================================
public int Native_AskAI(Handle plugin, int numParams)
{
    if (g_HttpClient == null)
    {
        LogError("NVD Core: HTTPClient not initialized");
        return 0;
    }
    if (numParams < 4)
    {
        LogError("NVD_AskAI: Expected 4 parameters, got %d", numParams);
        return 0;
    }

    char prompt[512], systemPrompt[2048];
    GetNativeString(1, prompt, sizeof(prompt));
    GetNativeString(2, systemPrompt, sizeof(systemPrompt));

    Function callback = GetNativeFunction(3);
    any callbackData = GetNativeCell(4);

    // ← ALOCA SLOT COM DADOS DO CHAMADOR
    int slotId = AllocatePendingSlot(callback, callbackData, plugin);
    if (slotId == -1)
        return 0;

    char model[64], endpoint[16], url[128];
    g_ModelCvar.GetString(model, sizeof(model));
    g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
    
    // ← FORMATAÇÃO CONSISTENTE DA URL (sem barra duplicada)
    if (endpoint[0] == '/')
        Format(url, sizeof(url), "api%s", endpoint);
    else
        Format(url, sizeof(url), "api/%s", endpoint);

    JSONObject payload = new JSONObject();
    payload.SetString("model", model);

    if (StrEqual(endpoint, "chat"))
    {
        JSONObject systemMsg = new JSONObject();
        systemMsg.SetString("role", "system");
        systemMsg.SetString("content", systemPrompt);

        JSONObject userMsg = new JSONObject();
        userMsg.SetString("role", "user");
        userMsg.SetString("content", prompt);

        JSONArray messages = new JSONArray();
        messages.Push(systemMsg);
        messages.Push(userMsg);

        payload.Set("messages", messages);
        payload.SetBool("stream", false);

        delete systemMsg;
        delete userMsg;
        delete messages;
    }
    else
    {
        payload.SetString("prompt", prompt);
        payload.SetBool("stream", false);
        payload.SetString("system", systemPrompt);
    }

    if (g_DebugCvar.BoolValue)
        LogMessage("NVD_AskAI: POST %s (slot=%d)", url, slotId);

    // ← PASSA slotId COMO "data" PARA OnOllamaResponse
    g_HttpClient.Post(url, payload, OnOllamaResponse, slotId);
    delete payload;
    return 1;  // ← Retorna 1 para indicar sucesso
}

// ============================================================================
// CALLBACK HTTP: OnOllamaResponse
// ============================================================================
public void OnOllamaResponse(HTTPResponse response, any slotId)
{
    // Recupera dados do callback pelo slotId
    Function callback;
    any callbackData;
    Handle callerPlugin;
    
    if (!FreePendingSlot(view_as<int>(slotId), callback, callbackData, callerPlugin))
    {
        LogError("NVD Core: Invalid or expired request slot %d", slotId);
        return;
    }

    // Trata erro HTTP
    if (response.Status != HTTPStatus_OK)
    {
        LogError("NVD Core: Ollama HTTP %d", response.Status);
        
        char location[512];
        if (response.GetHeader("Location", location, sizeof(location)))
            LogError("NVD Core: Redirect: %s", location);
        
        // ← Chama callback com string vazia para indicar erro
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("");
            Call_PushCell(callbackData);
            Call_Finish();
        }
        if (callerPlugin != INVALID_HANDLE)
            CloseHandle(callerPlugin);
        return;
    }

    if (response.Data == null)
    {
        LogError("NVD Core: Null response data");
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("");
            Call_PushCell(callbackData);
            Call_Finish();
        }
        if (callerPlugin != INVALID_HANDLE)
            CloseHandle(callerPlugin);
        return;
    }

    // Parse JSON
    JSONObject json = view_as<JSONObject>(response.Data);
    char reply[2048];  // ← Buffer maior para respostas longas

    // Tenta extrair resposta (suporta endpoints "generate" e "chat")
    if (!json.GetString("response", reply, sizeof(reply)))
    {
        JSONObject msg = view_as<JSONObject>(json.Get("message"));
        if (msg != null)
        {
            msg.GetString("content", reply, sizeof(reply));
            delete msg;
        }
    }

    // Fallback para estrutura do endpoint /api/chat
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
        LogError("NVD Core: Empty response content");
        if (callback != null && callerPlugin != INVALID_HANDLE)
        {
            Call_StartFunction(callerPlugin, callback);
            Call_PushString("");
            Call_PushCell(callbackData);
            Call_Finish();
        }
        if (callerPlugin != INVALID_HANDLE)
            CloseHandle(callerPlugin);
        return;
    }

    if (g_DebugCvar.BoolValue)
    {
        LogMessage("=== [NVD Core Debug] RESPONSE (slot=%d) ===", slotId);
        LogMessage("Reply: %.500s%s", reply, (strlen(reply) > 500) ? "..." : "");
        LogMessage("============================================");
    }

    // ← CHAMA CALLBACK COM HANDLE CORRETO
    if (callback != null && callerPlugin != INVALID_HANDLE)
    {
        Call_StartFunction(callerPlugin, callback);
        Call_PushString(reply);
        Call_PushCell(callbackData);
        int result = Call_Finish();
        
        if (result != SP_ERROR_NONE)
            LogError("NVD Core: Callback execution failed (error %d)", result);
    }
    else if (callback == null)
    {
        LogError("NVD Core: Callback function is null");
    }
    else if (callerPlugin == INVALID_HANDLE)
    {
        LogError("NVD Core: Caller plugin handle is invalid");
    }

    // Limpa handle clonado
    if (callerPlugin != INVALID_HANDLE)
        CloseHandle(callerPlugin);
}
