#include <sourcemod>
#include <ripext>
#include <nvd_core>

HTTPClient g_HttpClient;
Function g_Callback;
any g_CallbackData;
ConVar g_IpCvar;
ConVar g_PortCvar;

public Plugin myinfo =
{
	name = "NVD Core",
	author = "OpenCode",
	description = "NVD AI Framework - HTTP/Ollama bridge for SourcePawn",
	version = "1.0.0",
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
	g_IpCvar = CreateConVar("nvd_ollama_ip", "172.17.0.1", "Ollama server IP", FCVAR_PROTECTED);
	g_PortCvar = CreateConVar("nvd_ollama_port", "11433", "Ollama server port", FCVAR_PROTECTED);
	AutoExecConfig(true, "nvd_core");
}

public void OnConfigsExecuted()
{
	char ip[64], port[16], baseUrl[256];
	g_IpCvar.GetString(ip, sizeof(ip));
	g_PortCvar.GetString(port, sizeof(port));
	Format(baseUrl, sizeof(baseUrl), "http://%s:%s", ip, port);

	g_HttpClient = new HTTPClient(baseUrl);
	g_HttpClient.SetHeader("Content-Type", "application/json");
}

public int Native_AskAI(Handle plugin, int numParams)
{
	if (g_HttpClient == null)
	{
		LogError("NVD Core: HTTPClient not initialized (configs not executed yet?)");
		return 0;
	}

	char prompt[512], systemPrompt[2048];
	GetNativeString(1, prompt, sizeof(prompt));
	GetNativeString(2, systemPrompt, sizeof(systemPrompt));

	g_Callback = GetNativeFunction(3);
	g_CallbackData = GetNativeCell(4);

	JSONObject payload = new JSONObject();
	payload.SetString("model", "nvd-admin");
	payload.SetString("prompt", prompt);
	payload.SetBool("stream", false);
	payload.SetString("system", systemPrompt);

	g_HttpClient.Post("api/generate", payload, OnOllamaResponse);
	delete payload;
	return 0;
}

public void OnOllamaResponse(HTTPResponse response, any data)
{
	if (response.Status != HTTPStatus_OK)
	{
		LogError("NVD Core: Ollama returned status %d", response.Status);
		return;
	}

	if (response.Data == null)
	{
		LogError("NVD Core: Ollama returned null response");
		return;
	}

	JSONObject json = view_as<JSONObject>(response.Data);
	char reply[1024];
	json.GetString("response", reply, sizeof(reply));

	if (reply[0] == '\0')
	{
		LogError("NVD Core: Ollama response has empty 'response' field");
		delete json;
		return;
	}

	Call_StartFunction(INVALID_HANDLE, g_Callback);
	Call_PushString(reply);
	Call_PushCell(g_CallbackData);
	Call_Finish();

	delete json;
}
