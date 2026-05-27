#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

new Handle:hEnable;
new EnableTeam;

public Plugin:myinfo =
{
	name = "Player Stacker",
	description = "Removes player stacking limit",
	author = "Blodia",
	version = "1.0",
	url = ""
};

public void OnPluginStart()
{
	CreateConVar("playerstacker_version", "1.0", "Player Stacker version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	hEnable = CreateConVar("playerstacker_enable", "1", "0 disables plugin, 1 removes stack limit for both teams, 2 removes stack limit for terrorist only, 3 removes stack limit for counter terrorist only", FCVAR_PLUGIN);
	HookConVarChange(hEnable, ConVarChange);
	EnableTeam = GetConVarInt(hEnable);
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			SDKHook(client, SDKHook_PostThink, OnPostThink);
		}
	}
}

public ConVarChange(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (hEnable == cvar)
	{
		EnableTeam = StringToInt(newVal);
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_PostThink, OnPostThink);
}

public OnPostThink(client)
{
	if (!EnableTeam)
	{
		return;
	}
	if (!IsPlayerAlive(client))
	{
		return;
	}
	if (EnableTeam > 1 && EnableTeam != GetClientTeam(client))
	{
		return;
	}
	
	new GroundEnt = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	if (GroundEnt > 0 && GroundEnt <= MaxClients)
	{
		SetEntPropEnt(client, Prop_Send, "m_hGroundEntity", -1);
	}
}
