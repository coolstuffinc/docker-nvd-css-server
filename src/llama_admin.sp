#include <sourcemod>
#include <sdktools>
#include <ripext>

#pragma semicolon 1
#pragma newdecls required

ConVar g_cvOllamaIp;
ConVar g_cvOllamaPort;
ConVar g_cvOllamaModel;
ConVar g_cvDebug;

HTTPClient g_HttpClient;

public Plugin myinfo =
{
  name = "Llama Admin",
  author = "OpenCode",
  description = "AI Admin powered by Ollama",
  version = "1.2.1",
  url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
  g_cvOllamaIp = CreateConVar("llama_admin_ip", "172.17.0.1", "IP address of the Ollama server");
  g_cvOllamaPort = CreateConVar("llama_admin_port", "11433", "Port of the Ollama server");
  g_cvOllamaModel = CreateConVar("llama_admin_model", "llama3.2:1b", "The Ollama model to use");
  g_cvDebug = CreateConVar("llama_admin_debug", "1", "Enable verbose logging for Llama Admin (1=Enabled)");

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
	g_HttpClient.SetHeader("Content-Type", "application/json");
	
	LogMessage("Llama Admin initializing. Base URL: %s", baseUrl);
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
  if (client == 0)
    strcopy(name, sizeof(name), "Console");
  else
    GetClientName(client, name, sizeof(name));

  PrintToChatAll("[Llama] %s is consulting the AI...", name);

  if (g_cvDebug.BoolValue)
    LogMessage("Query from %s: %s", name, question);

  char prompt[512];
  Format(prompt, sizeof(prompt), "Player '%s' asks: %s", name, question);

  char model[64];
  g_cvOllamaModel.GetString(model, sizeof(model));

	char mapList[1024];
	GetMapList(mapList, sizeof(mapList));

	char systemPrompt[2048];
	Format(systemPrompt, sizeof(systemPrompt), "You are NVD Admin AI. Rules:\n1. NEVER execute commands directly. Propose votes using [CMD: sm_votecommand arg1].\n2. IF NO COMMAND IS NEEDED, DO NOT USE [CMD:]. JUST CHAT.\n3. Available maps: %s", mapList);

	// Ollama generate API structure
	JSONObject payload = new JSONObject();
	payload.SetString("model", model);
	payload.SetString("prompt", prompt);
	payload.SetBool("stream", false);
	payload.SetString("system", systemPrompt);

	int userid = (client == 0) ? 0 : GetClientUserId(client);
	g_HttpClient.Post("api/generate", payload, OnOllamaResponse, userid);
	delete payload;


	return Plugin_Handled;
}

void GetMapList(char[] buffer, int size)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/maplist.txt");
	File file = OpenFile(path, "r");
	if (file != null)
	{
		char line[64];
		while (file.ReadLine(line, sizeof(line)))
		{
			TrimString(line);
			if (strlen(line) > 0)
			{
				StrCat(buffer, size, line);
				StrCat(buffer, size, ", ");
			}
		}
		delete file;
	}
}


public void OnOllamaResponse(HTTPResponse response, any userid)
{
    // Removido 'int client' não utilizado
    
    if (response.Status != HTTPStatus_OK || response.Data == null)
    {
        LogError("Ollama Error: Status %d, Data valid: %d", response.Status, response.Data != null);
        return;
    }

    LogMessage("Ollama raw response received.");

    JSONObject json = view_as<JSONObject>(response.Data);
    
    // ... restante ...

	
	if (json.HasKey("error")) {
		char errorMsg[256];
		json.GetString("error", errorMsg, sizeof(errorMsg));
		LogError("Ollama API Error: %s", errorMsg);
		return;
	}

	char reply[1024];
	if (!json.GetString("response", reply, sizeof(reply))) {
		LogError("Failed to parse 'response' field.");
		return;
	}
    // ... resto do código ...



  if (g_cvDebug.BoolValue)
    LogMessage("AI Response: %s", reply);

  // Check for commands
  int cmdStart = StrContains(reply, "[CMD:");
  if (cmdStart != -1)
  {
    int cmdEnd = StrContains(reply[cmdStart], "]");
    if (cmdEnd != -1)
    {
      char cmd[128];
      // Extract command: skip "[CMD: " (5 chars), copy up to ']'
      strcopy(cmd, cmdEnd - 4, reply[cmdStart + 5]);
      TrimString(cmd);

      LogAction(0, -1, "[Llama] Executing AI-generated command: %s", cmd);
      ServerCommand("%s", cmd);

      // Remove the [CMD: ...] block from reply
      char block[130];
      strcopy(block, cmdEnd + 2, reply[cmdStart]);
      ReplaceString(reply, sizeof(reply), block, "");
    }
  }

  TrimString(reply);

  if (strlen(reply) > 0)
  {
    // Truncate long messages with ellipsis
    if (strlen(reply) > 200)
    {
      reply[196] = '.';
      reply[197] = '.';
      reply[198] = '.';
      reply[199] = '\0';
    }

		// Print to all players
		PrintToChatAll("\x04[Llama Admin]\x01 %s", reply);

  }
  // ✅ Function ends cleanly here - no stray prints or braces
}
