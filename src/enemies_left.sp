#define VERSION "1.0"
#include <sourcemod>
#include <cstrike>
#include <sdktools>
#pragma semicolon 1
#define PLUGIN_VERSION	"1.0.0.4"
#define TEAM_T					2
#define TEAM_CT					3

public Plugin:myinfo = {
	name = "Enemies left",
	author = "Axel Juan Nieves",
	description = "Says in chat enemies left to go",
	version = VERSION
}

new Handle:g_CvarChat = INVALID_HANDLE;
new Handle:g_CvarRadio = INVALID_HANDLE;
new Handle:g_CvarBlind = INVALID_HANDLE;

public OnPluginStart()
{
	LoadTranslations("enemies_left.phrases");
	g_CvarChat = CreateConVar("sm_eleft_chat", "1", "Automatically says on chat how many enemies are left. 1=Enabled | 0=Disabled");
	g_CvarRadio = CreateConVar("sm_eleft_radio", "0", "Executes 'enemy down' radio command automatically. 1=Enabled | 0=Disabled");
	g_CvarBlind = CreateConVar("sm_eleft_blind", "1", "Prints to chat when someone blinded you. 1=Enabled | 0=Disabled");
	CreateConVar("sm_eleft_version", VERSION, "Enemies left version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	AutoExecConfig(true, "enemies_left");
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_blind", OnPlayerBlind);
}
 
public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{    
	new victimId = GetEventInt(event, "userid");
	new victimClient = GetClientOfUserId(victimId);
	new victimTeam = GetClientTeam(victimClient);
	new attackerId = GetEventInt(event, "attacker");
	new attackerClient = GetClientOfUserId(attackerId);
	new attackerTeam = GetClientTeam(attackerClient);
	
	if ( victimTeam != attackerTeam )
	{
		new iAliveEnemies = 0;
		new i = 0;
		new iMaxClients = MaxClients;
		for (i = 1; i <= iMaxClients; i++)
		{
			if (IsClientConnected (i) && IsClientInGame (i) && !IsClientObserver (i))
			{
				new iTeam = GetClientTeam (i);
				if (iTeam == victimTeam)
				{
					if ( IsPlayerAlive(i) )
					{
						iAliveEnemies++;
					} 
				}
			}
		}
		if ( iAliveEnemies>2 )
		{
			if ( GetConVarBool(g_CvarRadio) )
			{
				FakeClientCommand(attackerClient, "enemydown");
			}
			if ( GetConVarBool(g_CvarChat) )
			{
				decl String:buffer[512];
				Format(buffer, sizeof(buffer), "say_team %t", "CountMany", iAliveEnemies);
				FakeClientCommand(attackerClient, buffer);
			}
		
		}
		else if ( iAliveEnemies==2 )
		{
			if ( GetConVarBool(g_CvarRadio) )
			{
				FakeClientCommand(attackerClient, "enemydown");
			}
			if ( GetConVarBool(g_CvarChat) )
			{
				decl String:buffer[512];
				Format(buffer, sizeof(buffer), "say_team %t", "Count2", iAliveEnemies);
				FakeClientCommand(attackerClient, buffer);
			}
		
		}
		else if ( iAliveEnemies==1 )
		{
			if ( GetConVarBool(g_CvarRadio) )
			{
				FakeClientCommand(attackerClient, "enemydown");
			}
			if ( GetConVarBool(g_CvarChat) )
			{
				decl String:buffer[512];
				Format(buffer, sizeof(buffer), "say_team %t", "Count1", iAliveEnemies);
				FakeClientCommand(attackerClient, buffer);
			}
			
		}
		else if ( iAliveEnemies==0 )
		{
			if ( GetConVarBool(g_CvarRadio) )
			{
				FakeClientCommand(attackerClient, "enemydown");
			}
			if ( GetConVarBool(g_CvarChat) )
			{
				decl String:buffer[512];
				Format(buffer, sizeof(buffer), "say_team %t", "Count0", iAliveEnemies);
				FakeClientCommand(attackerClient, buffer);
			}
			
		}
	}	
}

public OnPlayerBlind(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	if ( GetConVarBool(g_CvarChat) && GetConVarBool(g_CvarBlind))
	{
		if ( GetConVarBool(g_CvarRadio) )
		{
			FakeClientCommand(client, "fallback");
		}
		decl String:buffer[512];
		Format(buffer, sizeof(buffer), "say_team %t", "Blind", 1);
		FakeClientCommand(client, buffer);
	}
}