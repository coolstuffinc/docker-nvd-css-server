#include <sourcemod>
#include <sdktools>
#include <cstrike>

public Plugin:myinfo =
{
	name = "Force Round End",
	description = "Go to the nextround",
	author = "The.Hardstyle.Bro",
	version = "1.0",
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	RegAdminCmd("sm_endround", Command_FRE, ADMFLAG_SLAY, "Force Round End");
}

public Action:Command_FRE(client, args)
{
	CS_TerminateRound(3.0, CSRoundEnd_Draw, true);
	PrintToChatAll("[SM] %N has ended the round.", client);
	LogAction(client, -1, "\"%L\" triggered sm_endround", client);
	return Plugin_Handled;
}
