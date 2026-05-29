#define VERSION "1.0"
#include <sourcemod>
#include <cstrike>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
  name = "Enemies left",
  author = "Axel Juan Nieves",
  description = "Says in chat enemies left to go",
  version = VERSION
};

ConVar g_CvarChat;
ConVar g_CvarRadio;
ConVar g_CvarBlind;

public void OnPluginStart()
{
  LoadTranslations("enemies_left.phrases");
  g_CvarChat = CreateConVar("sm_eleft_chat", "1", "Automatically says on chat how many enemies are left.");
  g_CvarRadio = CreateConVar("sm_eleft_radio", "0", "Executes 'enemy down' radio command.");
  g_CvarBlind = CreateConVar("sm_eleft_blind", "1", "Prints to chat when someone blinded you.");
  CreateConVar("sm_eleft_version", VERSION, "Enemies left version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);

  HookEvent("player_death", Event_PlayerDeath);
  HookEvent("player_blind", OnPlayerBlind);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{    
  int victimClient = GetClientOfUserId(event.GetInt("userid"));
  int attackerClient = GetClientOfUserId(event.GetInt("attacker"));

  if (victimClient < 1 || victimClient > MaxClients || !IsClientInGame(victimClient))
    return;
  if (attackerClient < 1 || attackerClient > MaxClients || !IsClientInGame(attackerClient))
    return;

  int victimTeam = GetClientTeam(victimClient);
  int attackerTeam = GetClientTeam(attackerClient);

  if (victimTeam != attackerTeam)
  {
    int iAliveEnemies = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
      if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == victimTeam)
      {
        iAliveEnemies++;
      }
    }

    if (g_CvarRadio.BoolValue)
      FakeClientCommand(attackerClient, "enemydown");

    if (g_CvarChat.BoolValue)
    {
      if (iAliveEnemies > 2)
        PrintToChatAll("\x01%t", "CountMany", iAliveEnemies);
      else if (iAliveEnemies == 2)
        PrintToChatAll("\x01%t", "Count2");
      else if (iAliveEnemies == 1)
        PrintToChatAll("\x01%t", "Count1");
      else
        PrintToChatAll("\x01%t", "Count0");
    }


  }	
}

public void OnPlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));
  if (client > 0 && IsClientInGame(client) && g_CvarChat.BoolValue && g_CvarBlind.BoolValue)
  {
    if (g_CvarRadio.BoolValue)
      FakeClientCommand(client, "fallback");

    char nameBuffer[MAX_NAME_LENGTH];
    GetClientName(client, nameBuffer, sizeof(nameBuffer));
    PrintToChatAll("\x01%t", "Blind", nameBuffer);
  }
}
