#include <sourcemod>
#include <sdktools>
#include <nvd_core>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "Llama Admin",
	author = "OpenCode",
	description = "AI Admin powered by NVD Core",
	version = "2.0.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_ask", Command_Ask, "Ask the Llama Admin a question");
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

	PrintToChatAll("\x04[Llama Admin]\x01 %s está consultando a IA...", name);
	
	char prompt[512];
	Format(prompt, sizeof(prompt), "Player '%s' asks: %s", name, question);
	
	char systemPrompt[2048];
	Format(systemPrompt, sizeof(systemPrompt), "You are NVD Admin AI. Concise. RULES: 1. You CANNOT execute direct actions. You can ONLY propose votes for the server to decide (e.g. sm_votekick, sm_votemap, sm_voteban). 2. Propose votes using exactly [CMD: sm_votecommand arg1]. 3. IF NO ACTION REQUESTED, JUST CHAT.");

	NVD_AskAI(prompt, systemPrompt, OnAIResponse, client);
}

public void OnAIResponse(const char[] response, any data)
{
	char reply[1024];
	strcopy(reply, sizeof(reply), response);
	
	// Parse [CMD: ...] block if it exists
	if (StrContains(reply, "[CMD:") == 0)
	{
		int endBracket = StrContains(reply, "]");
		if (endBracket != -1)
		{
			char cmd[128];
			strcopy(cmd, endBracket - 4, reply[5]); // Copy text between [CMD: and ]
			
			// Execute the parsed command on the server
			TrimString(cmd);
			LogMessage("[Llama Admin] Extracted and executing command: '%s'", cmd);
			ServerCommand("%s", cmd);

			// Remove the [CMD: ...] block from the reply text
			strcopy(reply, sizeof(reply), reply[endBracket + 1]);
			TrimString(reply);
		}
	}

	if (strlen(reply) > 0)
	{
		PrintToChatAll("\x04[Llama Admin]\x01 %s", reply);
	}
}

public void OnAIResponse(const char[] response, any data)
{
	char reply[1024];
	strcopy(reply, sizeof(reply), response);
	
	if (strlen(reply) > 0)
	{
		PrintToChatAll("\x04[Llama Admin]\x01 %s", reply);
	}
}
