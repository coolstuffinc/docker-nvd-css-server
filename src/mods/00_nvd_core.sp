#include <sourcemod>
#include <ripext>
#include <nvd_core>

HTTPClient g_HttpClient;
Function g_Callback;
any g_CallbackData;
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
	version = "1.1.0",
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
}

public void OnConfigsExecuted()
{
	char ip[64], port[16];
	g_IpCvar.GetString(ip, sizeof(ip));
	g_PortCvar.GetString(port, sizeof(port));
	Format(g_BaseUrl, sizeof(g_BaseUrl), "http://%s:%s/", ip, port); // Adicionei a barra de volta

	g_HttpClient = new HTTPClient(g_BaseUrl);
	g_HttpClient.FollowLocation = true; // Agora ele vai seguir os redirects automaticamente
	g_HttpClient.SetHeader("Content-Type", "application/json");
	g_HttpClient.SetHeader("User-Agent", "SourceMod-NVD-AI/1.1");

	if (g_DebugCvar.BoolValue)
	{
		LogMessage("NVD Core: HTTPClient initialized, base URL = %s", g_BaseUrl);
	}
}

public Action Command_OllamaTest(int client, int args)
{
	if (g_HttpClient == null)
	{
		ReplyToCommand(client, "\x04[NVD]\x03 HTTPClient not initialized (configs not executed yet?)");
		return Plugin_Handled;
	}

	if (client == 0)
		PrintToServer("[NVD] Testing Ollama connectivity at %s...", g_BaseUrl);
	else
		PrintToChat(client, "\x04[NVD]\x03 Testing Ollama connectivity at %s...", g_BaseUrl);

	g_DebugCvar.SetInt(1);

	JSONObject payload = new JSONObject();
	payload.SetString("model", "nvd-admin");
	payload.SetString("prompt", "ping");
	payload.SetBool("stream", false);

	char url[128];
	char endpoint[16];
	g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
	// Remove barra inicial se houver, garantindo um caminho limpo
	if (endpoint[0] == '/')
		Format(url, sizeof(url), "api%s", endpoint);
	else
		Format(url, sizeof(url), "api/%s", endpoint);

	// Log para verificar se a URL está correta antes de chamar Post
	LogMessage("DEBUG: Calling g_HttpClient.Post(url: %s, ...)", url);
	g_HttpClient.Post(url, payload, OnOllamaResponse, client);
	delete payload;
	return Plugin_Handled;
}

public void OnTestResponse(HTTPResponse response, any client)
{
	if (response.Status == HTTPStatus_OK)
	{
		if (client == 0)
			PrintToServer("[NVD] SUCCESS: Ollama connected (status %d)", response.Status);
		else if (IsClientInGame(client))
			PrintToChat(client, "\x04[NVD]\x03 SUCCESS: Ollama connected (status %d)", response.Status);

		if (response.Data != null)
		{
			JSONObject json = view_as<JSONObject>(response.Data);
			char reply[1024];
			if (json.GetString("response", reply, sizeof(reply)) || json.GetString("message", reply, sizeof(reply)))
			{
				if (client == 0)
					PrintToServer("[NVD] Reply: %s", reply);
				else if (IsClientInGame(client))
					PrintToChat(client, "\x04[NVD]\x03 Reply: %s", reply);
			}
			delete json;
		}
	}
	else
	{
		if (client == 0)
			PrintToServer("[NVD] FAILED: Ollama returned status %d on %s", response.Status, g_BaseUrl);
		else if (IsClientInGame(client))
			PrintToChat(client, "\x04[NVD]\x03 FAILED: Ollama returned status %d on %s", response.Status, g_BaseUrl);
		// Removida a checagem de response.Data em erros para evitar Exception "Invalid JSON"
	}
}

public int Native_AskAI(Handle plugin, int numParams)
{
	if (g_HttpClient == null)
	{
		LogError("NVD Core: HTTPClient not initialized");
		return 0;
	}

	char prompt[512], systemPrompt[2048];
	GetNativeString(1, prompt, sizeof(prompt));
	GetNativeString(2, systemPrompt, sizeof(systemPrompt));

	g_Callback = GetNativeFunction(3);
	g_CallbackData = GetNativeCell(4);

	char model[64], endpoint[16], url[128];
	g_ModelCvar.GetString(model, sizeof(model));
	g_EndpointCvar.GetString(endpoint, sizeof(endpoint));
	if (endpoint[0] == '/')
		Format(url, sizeof(url), "api%s/", endpoint);
	else
		Format(url, sizeof(url), "api/%s/", endpoint);

	LogMessage("DEBUG: Calling g_HttpClient.Post(url: %s, ...)", url);
	g_HttpClient.Post(url, payload, OnOllamaResponse);
	delete payload;
	return 0;
}

public void OnOllamaResponse(HTTPResponse response, any data)
{
	if (response.Status != HTTPStatus_OK)
	{
		LogError("NVD Core: Ollama returned status %d", response.Status);
		
		char location[512];
		if (response.GetHeader("Location", location, sizeof(location)))
		{
			LogError("NVD Core: Redirect Location: %s", location);
		}
		
		return;
	}

	if (response.Data == null)
	{
		LogError("NVD Core: Ollama returned null response");
		return;
	}

	JSONObject json = view_as<JSONObject>(response.Data);
	char reply[1024];

	if (!json.GetString("response", reply, sizeof(reply)))
	{
		JSONObject msg = view_as<JSONObject>(json.Get("message"));
		if (msg != null)
		{
			msg.GetString("content", reply, sizeof(reply));
			delete msg;
		}
	}

	if (reply[0] == '\0')
	{
		LogError("NVD Core: Ollama response has empty content field");
		delete json;
		return;
	}

	if (g_DebugCvar.BoolValue)
	{
		LogMessage("=== [NVD Core Debug] INBOUND RESPONSE ===");
		LogMessage("Ollama response: %s", reply);
		LogMessage("=========================================");
	}

	Call_StartFunction(INVALID_HANDLE, g_Callback);
	Call_PushString(reply);
	Call_PushCell(g_CallbackData);
	Call_Finish();

	delete json;
}
