#include <sourcemod>
#include <sdktools>

new Handle:v_TextEnabled;
new Handle:v_MaxCash;
new g_iAccount = -1;
new g_iAutoCash[66] =
{
	-1, ...
};
public Plugin:myinfo =
{
	name = "[CS:S] Give Cash",
	description = "Change player's cash amounts",
	author = "DarthNinja",
	version = "1.0.0",
	url = "DarthNinja.com"
};
public void OnPluginStart()
{
	g_iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
	if (g_iAccount == -1)
	{
		SetFailState("[CS:S] Give Cash - Failed to find offset for m_iAccount!");
	}
	CreateConVar("sm_givecash_version", "1.0.0", "Plugin Version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	v_MaxCash = CreateConVar("sm_givecash_max", "1", "Enable/Disable cap of 60,000 cash max <1/0>", 0, true, 0.0, true, 1.0);
	v_TextEnabled = CreateConVar("sm_givecash_showtext", "1", "Set to 0 to skip telling the target client about changes to their cash", 0, true, 0.0, true, 1.0);
	RegAdminCmd("sm_cash", SetCash, ADMFLAG_GENERIC, "sm_cash <target> <value> - Sets <target>'s cash to <value>");
	RegAdminCmd("sm_setcash", SetCash, ADMFLAG_GENERIC, "sm_setcash <target> <value> - Sets <target>'s cash to <value>");
	RegAdminCmd("sm_addcash", AddCash, ADMFLAG_GENERIC, "sm_addcash <target> <value> - Adds <value> to the <target>'s cash");
	RegAdminCmd("sm_autocash", AutoCash, ADMFLAG_GENERIC, "sm_autocash <target> <value> - Sets <target>'s cash to <value> at the start of every round. Use -1 to cancel");
	HookEvent("player_spawn", AutoCash2, EventHookMode_Post);
	LoadTranslations("common.phrases");
}

	CreateConVar("sm_givecash_version", "1.0.0", "Plugin Version", 270656, false, 0.0, false, 0.0);
	v_MaxCash = CreateConVar("sm_givecash_max", "1", "Enable/Disable cap of 60,000 cash max <1/0>", 0, true, 0.0, true, 1.0);
	v_TextEnabled = CreateConVar("sm_givecash_showtext", "1", "Set to 0 to skip telling the target client about changes to their cash", 0, true, 0.0, true, 1.0);
	RegAdminCmd("sm_cash", SetCash, 32, "sm_cash <target> <value> - Sets <target>'s cash to <value>", "", 0);
	RegAdminCmd("sm_setcash", SetCash, 32, "sm_setcash <target> <value> - Sets <target>'s cash to <value>", "", 0);
	RegAdminCmd("sm_addcash", AddCash, 32, "sm_addcash <target> <value> - Adds <value> to the <target>'s cash", "", 0);
	RegAdminCmd("sm_autocash", AutoCash, 32, "sm_autocash <target> <value> - Sets <target>'s cash to <value> at the start of every round. Use -1 to cancel", "", 0);
	HookEvent("player_spawn", AutoCash2, EventHookMode:1);
	LoadTranslations("common.phrases");
}

public AutoCash2(Handle:hEvent, String:strName[], bool:bDontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if (g_iAutoCash[client] != -1)
	{
		if (GetConVarBool(v_TextEnabled))
		{
			PrintToChat(client, "\x04[\x03Give Cash\x04]:\x01 Your cash has automatically been set to \x05%i\x01 due to the start of the round", g_iAutoCash[client]);
		}
		SetEntData(client, g_iAccount, g_iAutoCash[client], 4, false);
	}
	//return 0;
}

public Action:AutoCash(client, args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "Usage: sm_autocash <target> <value>");
		return Plugin_Handled;
	}
	decl String:buffer[64];
	decl String:target_name[32];
	decl target_list[65];
	decl target_count;
	decl bool:tn_is_ml;
	GetCmdArg(1, buffer, 64);
	if (0 >= (target_count = ProcessTargetString(buffer, client, target_list, 65, 4, target_name, 32, tn_is_ml)))
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	decl String:Cash[16];
	GetCmdArg(2, Cash, 15);
	new iCash = StringToInt(Cash, 10);
	if (iCash < 0 && iCash != -1)
	{
		ReplyToCommand(client, "[SM] Cash value is less then 0 - Using 0 instead!");
		iCash = 0;
	}
	else
	{
		if (iCash > 60000 && GetConVarBool(v_MaxCash))
		{
			ReplyToCommand(client, "[SM] Cash value is over 60000 - Using 60000 to prevent problems!");
			iCash = 60000;
		}
	}
	if (iCash == -1)
	{
		ShowActivity2(client, "\x04[\x03Give Cash\x04] ", " \x05%s\x01 will no longer receive cash at the start of every round.", target_name);
	}
	else
	{
		ShowActivity2(client, "\x04[\x03Give Cash\x04] ", " \x01Set \x05%s's\x01 to receive \x04%i\x01 cash at the start of every round!", target_name, iCash);
	}
	new i;
	while (i < target_count)
	{
		g_iAutoCash[target_list[i]] = iCash;
		if (GetConVarBool(v_TextEnabled) && iCash != -1)
		{
			PrintToChat(target_list[i], "\x04[\x03Give Cash\x04]:\x01 An admin set your cash to change to \x05%i\x01 every time you spawn!", iCash);
		}
		i++;
	}
	return Plugin_Handled;
}

public Action:SetCash(client, args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "Usage: sm_cash <target> <value>");
		return Plugin_Handled;
	}
	decl String:buffer[64];
	decl String:target_name[32];
	decl target_list[65];
	decl target_count;
	decl bool:tn_is_ml;
	GetCmdArg(1, buffer, 64);
	if (0 >= (target_count = ProcessTargetString(buffer, client, target_list, 65, 1, target_name, 32, tn_is_ml)))
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	decl String:Cash[16];
	GetCmdArg(2, Cash, 15);
	new iCash = StringToInt(Cash, 10);
	if (0 > iCash)
	{
		ReplyToCommand(client, "[SM] Cash value is less then 0 - Using 0 instead!");
		iCash = 0;
	}
	else
	{
		if (iCash > 60000 && GetConVarBool(v_MaxCash))
		{
			ReplyToCommand(client, "[SM] Cash value is over 60000 - Using 60000 to prevent problems!");
			iCash = 60000;
		}
	}
	ShowActivity2(client, "\x04[\x03Give Cash\x04] ", " \x01Set \x05%s's\x01 cash to \x04%i\x01!", target_name, iCash);
	new i;
	while (i < target_count)
	{
		SetEntData(target_list[i], g_iAccount, iCash, 4, false);
		if (GetConVarBool(v_TextEnabled))
		{
			PrintToChat(target_list[i], "\x04[\x03Give Cash\x04]:\x01 An admin set your cash to \x05%i\x01!", iCash);
		}
		i++;
	}
	return Plugin_Handled;
}

public Action:AddCash(client, args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "Usage: sm_addcash <target> <value>");
		return Plugin_Handled;
	}
	decl String:buffer[64];
	decl String:target_name[32];
	decl target_list[65];
	decl target_count;
	decl bool:tn_is_ml;
	GetCmdArg(1, buffer, 64);
	if (0 >= (target_count = ProcessTargetString(buffer, client, target_list, 65, 1, target_name, 32, tn_is_ml)))
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	decl String:Cash[16];
	GetCmdArg(2, Cash, 15);
	new iCash = StringToInt(Cash, 10);
	if (0 > iCash)
	{
		ReplyToCommand(client, "[SM] Cash value is less then 0 - Using 0 instead!");
		iCash = 0;
	}
	else
	{
		if (iCash > 60000 && GetConVarBool(v_MaxCash))
		{
			ReplyToCommand(client, "[SM] Cash value is over 60000 - Using 60000 to prevent problems!");
			iCash = 60000;
		}
	}
	ShowActivity2(client, "\x04[\x03Give Cash\x04] ", " \x01Added \x04%i\x01 to \x05%s's\x01 cash!", iCash, target_name);
	new i;
	while (i < target_count)
	{
		if (GetConVarBool(v_TextEnabled))
		{
			PrintToChat(target_list[i], "\x04[\x03Give Cash\x04]:\x01 An admin added \x05%i\x01 to your cash!", iCash);
		}
		new iExistingCash = GetEntData(target_list[i], g_iAccount, 4);
		iCash = iExistingCash + iCash;
		if (iCash > 60000 && GetConVarBool(v_MaxCash))
		{
			iCash = 60000;
		}
		SetEntData(target_list[i], g_iAccount, iCash, 4, false);
		i++;
	}
	return Plugin_Handled;
}

