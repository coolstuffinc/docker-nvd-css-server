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
  g_CvarRadio = CreateConVar("sm_eleft_radio", "1", "Executes radio command on kill (contextual by remaining enemies).");
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
      for (int i = 1; i <= MaxClients; i++)
      {
        if (!IsClientInGame(i) || IsFakeClient(i))
          continue;
        int team = GetClientTeam(i);
        if (team == attackerTeam)
        {
          int n = iVictimSideAlive;
          if (n > 2)
            PrintToChat(i, "\x04[NVD]\x01 %d enemies left", n);
          else if (n == 2)
            PrintToChat(i, "\x04[NVD]\x01 2 enemies left");
          else if (n == 1)
            PrintToChat(i, "\x04[NVD]\x01 1 enemy left");
          else
            PrintToChat(i, "\x04[NVD]\x01 Last one!");
        }
        else if (team == victimTeam)
        {
          int n = iAttackerSideAlive;
          if (n > 2)
            PrintToChat(i, "\x04[NVD]\x01 %d teammates left", n);
          else if (n == 2)
            PrintToChat(i, "\x04[NVD]\x01 2 teammates left");
          else if (n == 1)
            PrintToChat(i, "\x04[NVD]\x01 1 teammate left");
          else
            PrintToChat(i, "\x04[NVD]\x01 No teammates left!");
        }
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
