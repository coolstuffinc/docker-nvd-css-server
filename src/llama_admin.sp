#include <sourcemod>
#include <sdktools>
#include <ripext>

#pragma semicolon 1
#pragma newdecls required

ConVar g_cvOllamaIp;
ConVar g_cvOllamaPort;
ConVar g_cvOllamaModel;

HTTPClient g_HttpClient;

public Plugin myinfo =
{
	name = "Llama Admin",
	author = "OpenCode",
	description = "AI Admin powered by Ollama",
	version = "1.1.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_cvOllamaIp = CreateConVar("llama_admin_ip", "172.17.0.1", "IP address of the Ollama server (default is Docker host)");
	g_cvOllamaPort = CreateConVar("llama_admin_port", "11434", "Port of the Ollama server");
	g_cvOllamaModel = CreateConVar("llama_admin_model", "llama3", "The Ollama model to use");

	RegConsoleCmd("sm_ask", Command_Ask, "Ask the Llama Admin a question");
	
	AutoExecConfig(true, "llama_admin");
}

public void OnConfigsExecuted()
{
	char baseUrl[256];
	char ip[64], port[16];
	
	g_cvOllamaIp.GetString(ip, sizeof(ip));
	g_cvOllamaPort.GetString(port, sizeof(port));
	
	Format(baseUrl, sizeof(baseUrl), "http://%s:%s", ip, port);
	g_HttpClient = new HTTPClient(baseUrl);
}

public Action Command_Ask(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[Llama] Usage: !ask <your question>");
		return Plugin_Handled;
	}

	char question[256];
	GetCmdArgString(question, sizeof(question));

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	PrintToChatAll("[Llama] %s is consulting the AI...", name);
	
	char prompt[512];
	Format(prompt, sizeof(prompt), "Player '%s' asks: %s", name, question);
	
	char model[64];
	g_cvOllamaModel.GetString(model, sizeof(model));

	JSONObject payload = new JSONObject();
	payload.SetString("model", model);
	payload.SetString("prompt", prompt);
	payload.SetBool("stream", false);
	
	// Add the persona instructions as the system prompt to enforce rules
	char systemPrompt[1024];
	Format(systemPrompt, sizeof(systemPrompt), "You are the NVD (NemViDeOnde) Server Admin AI. Keep responses CONCISE (max 2 sentences). To run an RCON command, format like: [CMD: sm_kick playername]. Your chat is public.");
	payload.SetString("system", systemPrompt);

	g_HttpClient.Post("api/generate", payload, OnOllamaResponse, GetClientUserId(client));
	delete payload;

	return Plugin_Handled;
}

public void OnOllamaResponse(HTTPResponse response, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (response.Status != HTTPStatus_OK)
	{
		if (client)
		{
			PrintToChat(client, "[Llama] Error: AI server unreachable or returned status %d.", response.Status);
		}
		return;
	}

	if (response.Data == null)
	{
		if (client)
		{
			PrintToChat(client, "[Llama] Error: Received empty data from AI.");
		}
		return;
	}

	JSONObject json = view_as<JSONObject>(response.Data);
	
	char reply[1024];
	json.GetString("response", reply, sizeof(reply));
	
	// Check for commands
	int cmdStart = StrContains(reply, "[CMD:");
	if (cmdStart != -1)
	{
		int cmdEnd = StrContains(reply[cmdStart], "]");
		if (cmdEnd != -1)
		{
			// Extract the command
			char cmd[128];
			strcopy(cmd, cmdEnd, reply[cmdStart + 5]); // +5 to skip "[CMD: "
			TrimString(cmd);
			
			// Execute the command locally
			ServerCommand("%s", cmd);
			PrintToServer("[Llama] Executing AI commanded: %s", cmd);
			
			// Remove the command block from the chat reply
			ReplaceString(reply, sizeof(reply), reply[cmdStart], reply[cmdStart + cmdEnd + 1]);
		}
	}
	
	TrimString(reply);
	
	if (strlen(reply) > 0)
	{
		// Need to handle large messages by splitting them or just truncating
		if (strlen(reply) > 200)
		{
			reply[196] = '.';
			reply[197] = '.';
			reply[198] = '.';
			reply[199] = '\0';
		}
		
		PrintToChatAll("[Llama] %s", reply);
	}
}