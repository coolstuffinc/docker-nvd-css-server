#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "Llama Admin",
	author = "OpenCode",
	description = "Ask questions to the Llama AI Admin",
	version = "1.0.0",
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
	GetClientName(client, name, sizeof(name));

	// Log in a format the bridge can easily parse
	PrintToServer("[LLAMA_QUERY] %s: %s", name, question);
	
	ReplyToCommand(client, "[Llama] Consulting the brain... please wait.");

	return Plugin_Handled;
}
