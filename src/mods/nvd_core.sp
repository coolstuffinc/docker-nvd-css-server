#include <sourcemod>
#include <ripext>
#include "../include/nvd_core"

HTTPClient g_HttpClient;
Function g_Callback;
any g_CallbackData;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("NVD_AskAI", Native_AskAI);
    RegPluginLibrary("nvd_core");
    return APLRes_Success;
}

public void OnPluginStart()
{
    AutoExecConfig(true, "nvd_core");
}

public void OnConfigsExecuted()
{
    char ip[64], port[16], baseUrl[256];
    ConVar ipCvar = FindConVar("nvd_ollama_ip");
    ConVar portCvar = FindConVar("nvd_ollama_port");
    
    ipCvar.GetString(ip, sizeof(ip));
    portCvar.GetString(port, sizeof(port));
    Format(baseUrl, sizeof(baseUrl), "http://%s:%s", ip, port);
    
    g_HttpClient = new HTTPClient(baseUrl);
    g_HttpClient.SetHeader("Content-Type", "application/json");
}

public int Native_AskAI(Handle plugin, int numParams)
{
    char prompt[512], systemPrompt[2048];
    GetNativeString(1, prompt, sizeof(prompt));
    GetNativeString(2, systemPrompt, sizeof(systemPrompt));

    g_Callback = GetNativeFunction(3);
    g_CallbackData = GetNativeCell(4);

    JSONObject payload = new JSONObject();
    payload.SetString("model", "nvd-admin"); // Usando o modelo que você criou
    payload.SetString("prompt", prompt);
    payload.SetBool("stream", false);
    payload.SetString("system", systemPrompt);

    g_HttpClient.Post("api/generate", payload, OnOllamaResponse);
    delete payload;
    return 0;
}

public void OnOllamaResponse(HTTPResponse response, any data)
{
    if (response.Status != HTTPStatus_OK || response.Data == null)
    {
        LogError("NVD Core Error: Ollama unreachable (Status: %d)", response.Status);
        return;
    }

    JSONObject json = view_as<JSONObject>(response.Data);
    char reply[1024];
    json.GetString("response", reply, sizeof(reply));
    
    Call_StartFunction(INVALID_HANDLE, g_Callback);
    Call_PushString(reply);
    Call_PushCell(g_CallbackData);
    Call_Finish();
    
    delete json;
}
