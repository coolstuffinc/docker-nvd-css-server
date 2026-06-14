#define VERSION "2.0"
#include <sourcemod>
#include <cstrike>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <nvd_bot_chat>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
  name = "Enemies left",
  author = "Axel Juan Nieves",
  description = "Bots call out remaining enemies via AI chat with fallback",
  version = VERSION
};

ConVar g_CvarChat;
ConVar g_CvarRadio;
ConVar g_CvarBlind;
ConVar g_CvarAIChance;
bool g_NvdAvailable;

int g_LastEnemies[MAXPLAYERS+1];
int g_LastAllies[MAXPLAYERS+1];

public void OnPluginStart()
{
  LoadTranslations("enemies_left.phrases");
  g_CvarChat = CreateConVar("sm_eleft_chat", "1", "Bot says how many enemies are left on kill.");
  g_CvarRadio = CreateConVar("sm_eleft_radio", "1", "Executes radio command on kill (contextual by remaining enemies).");
  g_CvarBlind = CreateConVar("sm_eleft_blind", "1", "Prints to chat when someone blinded you.");
  g_CvarAIChance = CreateConVar("sm_eleft_ai_chance", "20", "Chance (1-100) to trigger AI on enemies_left/allies_left");
  CreateConVar("sm_eleft_version", VERSION, "Enemies left version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
  g_NvdAvailable = (GetFeatureStatus(FeatureType_Native, "NVD_SubmitChatEvent") == FeatureStatus_Available);

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

void SayEnemiesFallback(int bot, int enemies, char[] out, int maxlen)
{
  char msg[64];
  if (enemies > 2)
    Format(msg, sizeof(msg), "say_team %T", "CountMany", LANG_SERVER, enemies);
  else if (enemies == 2)
    Format(msg, sizeof(msg), "say_team %T", "Count2", LANG_SERVER);
  else if (enemies == 1)
    Format(msg, sizeof(msg), "say_team %T", "Count1", LANG_SERVER);
  else
    Format(msg, sizeof(msg), "say_team %T", "Count0", LANG_SERVER);
  FakeClientCommand(bot, msg);
  int pos = 9; while (msg[pos] == ' ') pos++;
  strcopy(out, maxlen, msg[pos]);
}

void SayTeammateFallback(int bot, int allies, char[] out, int maxlen)
{
  char msg[64];
  if (allies > 2)
    Format(msg, sizeof(msg), "say_team %T", "VictimMany", LANG_SERVER, allies);
  else if (allies == 2)
    Format(msg, sizeof(msg), "say_team %T", "Victim2", LANG_SERVER);
  else if (allies == 1)
    Format(msg, sizeof(msg), "say_team %T", "Victim1", LANG_SERVER);
  if (allies > 0)
  {
    FakeClientCommand(bot, msg);
    int pos = 9; while (msg[pos] == ' ') pos++;
    strcopy(out, maxlen, msg[pos]);
  }
  else
  {
    out[0] = '\0';
  }
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
    int alliesCount = 0;
    int enemiesCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
      if (!IsClientInGame(i) || !IsPlayerAlive(i))
        continue;
      int team = GetClientTeam(i);
      if (team == attackerTeam)
        alliesCount++;
      else if (team == victimTeam)
        enemiesCount++;
    }

    if (g_CvarRadio.BoolValue)
    {
      if (enemiesCount <= 1)
        FakeClientCommand(attackerClient, "sectorclear");
      else if (enemiesCount == 2)
        FakeClientCommand(attackerClient, "enemydown");
      else
        FakeClientCommand(attackerClient, "needbackup");
    }

    if (g_CvarChat.BoolValue)
    {
      int attackerBot = FindBotOnTeam(attackerTeam);
      if (attackerBot != -1)
      {
        bool used = false;
        if (g_NvdAvailable)
        {
          char cached[320];
          if (NVD_GetCachedResponse(attackerBot, enemiesCount, alliesCount, cached, sizeof(cached)) && cached[0])
          {
            char clean[320]; strcopy(clean, sizeof(clean), cached);
            ReplaceString(clean, 320, "\"", ""); ReplaceString(clean, 320, "[", ""); ReplaceString(clean, 320, "]", ""); TrimString(clean);
            if (clean[0]) { FakeClientCommand(attackerBot, "say %s", clean); used = true; }
          }
        }
        if (!used)
        {
  char fallback[128];
  SayEnemiesFallback(attackerBot, enemiesCount, fallback, sizeof(fallback));
  if (g_NvdAvailable && (alliesCount == 1 || GetRandomInt(1, 100) <= g_CvarAIChance.IntValue))
  {
    g_LastEnemies[attackerBot] = enemiesCount;
    g_LastAllies[attackerBot] = alliesCount;
    NVD_SubmitChatEvent("ENEMIES_LEFT", attackerBot, 40, "enemies_left", enemiesCount, alliesCount);
  }
        }
      }

      int victimBot = FindBotOnTeam(victimTeam);
      if (victimBot != -1)
      {
        int vEnemies = alliesCount;
        int vAllies = enemiesCount;
        bool used = false;
        if (g_NvdAvailable)
        {
          char cached[320];
          if (NVD_GetCachedResponse(victimBot, vEnemies, vAllies, cached, sizeof(cached)) && cached[0])
          {
            char clean[320]; strcopy(clean, sizeof(clean), cached);
            ReplaceString(clean, 320, "\"", ""); ReplaceString(clean, 320, "[", ""); ReplaceString(clean, 320, "]", ""); TrimString(clean);
            if (clean[0]) { FakeClientCommand(victimBot, "say %s", clean); used = true; }
          }
        }
        if (!used)
        {
  char fallback2[128];
  SayTeammateFallback(victimBot, vAllies, fallback2, sizeof(fallback2));
  if (g_NvdAvailable && fallback2[0] && (vAllies == 1 || GetRandomInt(1, 100) <= g_CvarAIChance.IntValue))
  {
    g_LastEnemies[victimBot] = vEnemies;
    g_LastAllies[victimBot] = vAllies;
    NVD_SubmitChatEvent("ALLIES_LEFT", victimBot, 35, "allies_left", vEnemies, vAllies);
  }
        }
      }
    }
  }	
}

public void OnPlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));
  if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && g_CvarChat.BoolValue && g_CvarBlind.BoolValue)
  {
    if (g_CvarRadio.BoolValue)
      FakeClientCommand(client, "fallback");

    char msg[128];
    Format(msg, sizeof(msg), "say_team %T", "Blind", LANG_SERVER);
    FakeClientCommand(client, msg);
  }
}
