#include <sourcemod>
#include <sdktools>
#include "../include/nvd_core"

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
	Format(systemPrompt, sizeof(systemPrompt), "You are NVD Admin AI. Concise. RULES: 1. Propose votes using [CMD: sm_votecommand arg1]. 2. IF NO COMMAND, JUST CHAT.");

	NVD_AskAI(prompt, systemPrompt, OnAIResponse, client);

	return Plugin_Handled;
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
