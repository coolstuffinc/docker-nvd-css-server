#define VERSION "1.1"
#include <sourcemod>
#include <cstrike>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
  name = "Enemies left",
  author = "Axel Juan Nieves",
  description = "Bots call out remaining enemies via chat",
  version = VERSION
};

ConVar g_CvarChat;
ConVar g_CvarRadio;
ConVar g_CvarBlind;

public void OnPluginStart()
{
  LoadTranslations("enemies_left.phrases");
  g_CvarChat = CreateConVar("sm_eleft_chat", "1", "Bot says how many enemies are left on kill.");
  g_CvarRadio = CreateConVar("sm_eleft_radio", "1", "Executes radio command on kill (contextual by remaining enemies).");
  g_CvarBlind = CreateConVar("sm_eleft_blind", "1", "Prints to chat when someone blinded you.");
  CreateConVar("sm_eleft_version", VERSION, "Enemies left version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);

  HookEvent("player_death", Event_PlayerDeath);
  HookEvent("player_blind", OnPlayerBlind);
}

int FindBotOnTeam(int team)
{
  for (int i = 1; i <= MaxClients; i++)
  {
    if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == team)
      return i;
  }
  return -1;
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
    int iAttackerSideAlive = 0;
    int iVictimSideAlive = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
      if (!IsClientInGame(i) || !IsPlayerAlive(i))
        continue;
      int team = GetClientTeam(i);
      if (team == attackerTeam)
        iAttackerSideAlive++;
      else if (team == victimTeam)
        iVictimSideAlive++;
    }
    // iVictimSideAlive = how many enemies the attacker's team still faces
    // iAttackerSideAlive = how many enemies the victim's team still faces

    if (g_CvarRadio.BoolValue)
    {
      int enemiesForAttacker = iVictimSideAlive;
      if (enemiesForAttacker <= 1)
        FakeClientCommand(attackerClient, "sectorclear");
      else if (enemiesForAttacker == 2)
        FakeClientCommand(attackerClient, "enemydown");
      else
        FakeClientCommand(attackerClient, "needbackup");
    }

    if (g_CvarChat.BoolValue)
    {
      int attackerBot = FindBotOnTeam(attackerTeam);
      int victimBot = FindBotOnTeam(victimTeam);
      char msg[64];

      if (attackerBot != -1)
      {
        int n = iVictimSideAlive;
        if (n > 2)
          Format(msg, sizeof(msg), "say_team %d enemies left", n);
        else if (n == 2)
          Format(msg, sizeof(msg), "say_team 2 enemies left");
        else if (n == 1)
          Format(msg, sizeof(msg), "say_team 1 enemy left");
        else
          Format(msg, sizeof(msg), "say_team All dead!");
        FakeClientCommand(attackerBot, msg);
      }

      if (victimBot != -1)
      {
        int n = iVictimSideAlive; // CORREÇÃO: Conta quantos sobraram no PRÓPRIO time da vítima
        if (n > 2)
          Format(msg, sizeof(msg), "say_team We are down to %d now!", n);
        else if (n == 2)
          Format(msg, sizeof(msg), "say_team Only 2 of us left!");
        else if (n == 1)
          Format(msg, sizeof(msg), "say_team I'm the last one alive!");
        
        // Se n == 0, o próprio bot estaria morto e não passaria na checagem do FindBotOnTeam (IsPlayerAlive)
        if (n > 0)
          FakeClientCommand(victimBot, msg);
      }
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
