#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

// Plugin Info
public Plugin myinfo =
{
    name = "Voice Comm",
    description = "Provides additional methods of controlling voice communication.",
    author = "databomb (modernized)",
    version = "2.3.0",
    url = "https://vintagejailbreak.org"
};

// ConVar Handles
ConVar g_cvDeadTalk;
ConVar g_cvAllTalk;
ConVar g_cvAnnounce;
ConVar g_cvMuteTime;
ConVar g_cvRoundEndAllTalk;
ConVar g_cvDeadHearAlive;
ConVar g_cvMuteAtStart;
ConVar g_cvTeamTalk;
ConVar g_cvTeamToMute;
ConVar g_cvMuteSpectators;
ConVar g_cvBlockUnmuteOnRetry;
ConVar g_cvAdmOvrd_FirstJoin;
ConVar g_cvAdmOvrd_Spec;
ConVar g_cvAdmOvrd_OnDeath;

// Other Handles
Handle g_hUnmuteTimer;
Handle g_hMutedPlayers;           // ArrayList of SteamIDs
ArrayList g_hTimedPunishments;    // ArrayList of client indices
Cookie g_hVoiceCommCookie;

// Global State
bool g_bMuted[MAXPLAYERS+1];
bool g_bHasJoinedOnce[MAXPLAYERS+1];
int g_iTimeRemaining[MAXPLAYERS+1];
bool g_bBetweenRounds;
bool g_bIsMuteTimeUp;
bool g_bHooksActive;

// ============================================================================
// PLUGIN STARTUP
// ============================================================================
public void OnPluginStart()
{
    LoadTranslations("voicecomm.phrases");
    LoadTranslations("common.phrases");
    
    CreateConVar("sm_voicecomm_version", "2.3.0", "Version of VoiceComm Plugin", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    g_cvAnnounce = CreateConVar("sm_voicecomm_announce", "1", "Enable or disable announcement messages: 0=disabled, 1=enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTeamTalk = CreateConVar("sm_voicecomm_teamtalk", "0", "When deadtalk=-2: 0=alive players talk to both teams, 1=alive players talk only to teammates", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMuteTime = CreateConVar("sm_voicecomm_mutetime", "29.0", "Seconds that the muted team stays muted at round start", FCVAR_NOTIFY, true, 2.5);
    g_cvDeadHearAlive = CreateConVar("sm_voicecomm_deadhearalive", "1", "0=dead players cannot hear alive, 1=dead can hear alive", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMuteAtStart = CreateConVar("sm_voicecomm_startmuted", "1", "Mute a team at round start", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTeamToMute = CreateConVar("sm_voicecomm_mutedteam", "2", "Team to mute at start (CS:S: 2=T, 3=CT)", FCVAR_NOTIFY, true, 1.0, true, 3.0);
    g_cvRoundEndAllTalk = CreateConVar("sm_voicecomm_roundendalltalk", "1", "Enable alltalk between rounds", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMuteSpectators = CreateConVar("sm_voicecomm_spectatormute", "1", "Auto-mute spectators (admins exempt)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvBlockUnmuteOnRetry = CreateConVar("sm_voicecomm_blockunmuteonreconnect", "1", "Enforce previous mutes on reconnect", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAdmOvrd_FirstJoin = CreateConVar("sm_voicecomm_admovrd_firstjoin", "1", "Admins bypass mute on first join", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAdmOvrd_OnDeath = CreateConVar("sm_voicecomm_admovrd_death", "1", "Admins bypass death mute", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAdmOvrd_Spec = CreateConVar("sm_voicecomm_admovrd_spectate", "1", "Admin spectators bypass mute rules", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    
    g_hVoiceCommCookie = new Cookie("VoiceComm_Status", "Bit-mask for VoiceComm status", CookieAccess_Private);
    
    g_hMutedPlayers = new ArrayList(ByteCountToCells(24));  // SteamID storage
    g_hTimedPunishments = new ArrayList();                   // Client indices
    
    // Unblock sv_alltalk from being read-only
    g_cvAllTalk = FindConVar("sv_alltalk");
    if (g_cvAllTalk)
    {
        int flags = g_cvAllTalk.Flags;
        g_cvAllTalk.Flags = flags & ~FCVAR_SPONLY;
    }
    
    // Hook admin mute commands to integrate with our system
    AddCommandListener(OnAdminMuteCommand, "sm_mute");
    AddCommandListener(OnAdminMuteCommand, "sm_gag");
    AddCommandListener(OnAdminMuteCommand, "sm_silence");
    AddCommandListener(OnAdminUnmuteCommand, "sm_unmute");
    AddCommandListener(OnAdminUnmuteCommand, "sm_ungag");
    AddCommandListener(OnAdminUnmuteCommand, "sm_unsilence");
    
    RegAdminCmd("sm_listmutes", Command_ListMutes, ADMFLAG_BAN, "Lists currently muted players");
    
    CreateTimer(60.0, Timer_CheckTimedPunishments, _, TIMER_REPEAT);
    
    AutoExecConfig(true, "voicecomm", "sourcemod");
}

public void OnAllPluginsLoaded()
{
    g_cvDeadTalk = FindConVar("sm_deadtalk");
    if (g_cvDeadTalk)
    {
        g_cvDeadTalk.SetBounds(ConVarBound_Lower, true, -2.0);
    }
}

public void OnConfigsExecuted()
{
    if (g_cvDeadTalk && g_cvDeadTalk.IntValue < 0 && !g_bHooksActive)
    {
        HookEvent("player_death", Event_PlayerDeath);
        HookEvent("player_spawn", Event_PlayerSpawn);
        HookEvent("round_start", Event_RoundStart);
        HookEvent("round_end", Event_RoundEnd);
        HookEvent("player_team", Event_PlayerTeam);
        g_bHooksActive = true;
    }
    
    if (g_cvDeadTalk)
    {
        g_cvDeadTalk.AddChangeHook(OnDeadTalkChanged);
    }
    if (g_cvAllTalk)
    {
        g_cvAllTalk.AddChangeHook(OnAllTalkChanged);
    }
}

// ============================================================================
// CONVAR CHANGE HOOKS
// ============================================================================
public void OnDeadTalkChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar.IntValue < 0 && !g_bHooksActive)
    {
        HookEvent("player_death", Event_PlayerDeath);
        HookEvent("player_spawn", Event_PlayerSpawn);
        HookEvent("round_start", Event_RoundStart);
        HookEvent("round_end", Event_RoundEnd);
        HookEvent("player_team", Event_PlayerTeam);
        g_bHooksActive = true;
    }
    else if (g_bHooksActive && convar.IntValue >= 0)
    {
        UnhookEvent("player_death", Event_PlayerDeath);
        UnhookEvent("player_spawn", Event_PlayerSpawn);
        UnhookEvent("round_start", Event_RoundStart);
        UnhookEvent("round_end", Event_RoundEnd);
        UnhookEvent("player_team", Event_PlayerTeam);
        g_bHooksActive = false;
    }
}

public void OnAllTalkChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CreateTimer(0.1, Timer_UpdateListening);
}

// ============================================================================
// CLIENT EVENTS
// ============================================================================
public void OnClientConnected(int client)
{
    g_bMuted[client] = false;
    g_bHasJoinedOnce[client] = false;
    g_iTimeRemaining[client] = 0;
}

public void OnClientDisconnect(int client)
{
    // Save timed punishment state to cookie before disconnect
    int idx = g_hTimedPunishments.FindValue(client);
    if (idx != -1)
    {
        char cookie[20];
        g_hVoiceCommCookie.Get(client, cookie, sizeof(cookie));
        int mask = StringToInt(cookie);
        
        // Preserve lower 3 bits (punishment type), update time in upper bits
        mask &= 0x07;
        if (g_iTimeRemaining[client] > 0 && g_iTimeRemaining[client] < 0x10000)
        {
            mask |= (g_iTimeRemaining[client] << 3);
        }
        
        g_iTimeRemaining[client] = 0;
        IntToString(mask, cookie, sizeof(cookie));
        g_hVoiceCommCookie.Set(client, cookie);
        g_hTimedPunishments.Erase(idx);
    }
}

public void OnClientPostAdminCheck(int client)
{
    int userid = GetClientUserId(client);
    int punishmentType = 4;  // 4 = none/default
    
    if (AreClientCookiesCached(client))
    {
        char cookie[20];
        g_hVoiceCommCookie.Get(client, cookie, sizeof(cookie));
        int mask = StringToInt(cookie);
        
        if (mask != 0)
        {
            int timeRemaining = (mask >> 3) & 0xFFFF;
            
            // If not marked as permanent (bit 2), and has time remaining, schedule it
            if (!(mask & 0x04) && timeRemaining > 0)
            {
                g_hTimedPunishments.Push(client);
                g_iTimeRemaining[client] = timeRemaining;
            }
            
            // Apply punishment type from lower 2 bits
            switch (mask & 0x03)
            {
                case 1: ServerCommand("sm_mute #%d", userid); punishmentType = 1;
                case 2: ServerCommand("sm_gag #%d", userid); punishmentType = 2;
                case 3: ServerCommand("sm_silence #%d", userid); punishmentType = 3;
            }
        }
    }
    
    // Re-apply session-based mutes if block-on-reconnect is enabled
    if (g_cvBlockUnmuteOnRetry.BoolValue && punishmentType == 4)
    {
        char steamid[24];
        GetClientAuthString(client, steamid, sizeof(steamid));
        int idx = g_hMutedPlayers.FindString(steamid);
        if (idx != -1)
        {
            int storedPunishment = g_hMutedPlayers.Get(idx);
            switch (storedPunishment)
            {
                case 1: ServerCommand("sm_mute #%d", userid);
                case 2: ServerCommand("sm_gag #%d", userid);
                case 3: ServerCommand("sm_silence #%d", userid);
            }
        }
    }
}

public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bMuted[i] = false;
    }
    g_hMutedPlayers.Clear();
}

// ============================================================================
// GAME EVENTS
// ============================================================================
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bBetweenRounds = false;
    bool announce = g_cvAnnounce.BoolValue;
    
    // Disable alltalk between rounds if configured
    if (g_cvRoundEndAllTalk.BoolValue)
    {
        g_cvAllTalk.BoolValue = false;
    }
    
    // Handle start-of-round muting
    if (g_cvMuteAtStart.BoolValue)
    {
        if (announce)
        {
            VoiceComm_PrintToChatAll("%t", "Start of Round with a Muted Team");
        }
        if (g_hUnmuteTimer)
        {
            delete g_hUnmuteTimer;
        }
        g_hUnmuteTimer = CreateTimer(g_cvMuteTime.FloatValue, Timer_UnmuteTeam);
    }
    else if (announce)
    {
        VoiceComm_PrintToChatAll("%t", "Start of Round without Muted Team");
    }
    
    // Handle spectator muting
    if (g_cvMuteSpectators.BoolValue)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || GetClientTeam(i) != 1) continue;  // Skip non-spectators
            
            bool isAdmin = CheckCommandAccess(i, "", ADMFLAG_ROOT, true);
            
            if (isAdmin && g_cvAdmOvrd_Spec.BoolValue)
            {
                if (announce) PrintToChat(i, "[\x03SM\x01] %t", "Spectator - Admin");
                // Admin spectators hear everyone, but no one hears them unless we allow
                for (int j = 1; j <= MaxClients; j++)
                {
                    if (i != j && IsClientInGame(j))
                    {
                        SetListenOverride(j, i, ListenOverride_Mute);
                    }
                }
            }
            else
            {
                if (announce) PrintToChat(i, "[\x03SM\x01] %t", "Spectator - Not Admin");
                // Normal spectators: mute them from being heard
                for (int j = 1; j <= MaxClients; j++)
                {
                    if (i != j && IsClientInGame(j))
                    {
                        SetListenOverride(j, i, ListenOverride_Mute);
                    }
                }
            }
        }
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bBetweenRounds = true;
    g_bIsMuteTimeUp = false;
    
    // Cancel any pending unmute timer
    if (g_hUnmuteTimer)
    {
        delete g_hUnmuteTimer;
        g_hUnmuteTimer = null;
        
        // Restore listening for non-muted players
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !g_bMuted[i])
            {
                SetClientListeningFlags(i, VOICE_LISTENALL);
            }
        }
    }
    
    // Reset listen overrides if using deadtalk=-2 mode
    if (g_cvDeadTalk && g_cvDeadTalk.IntValue == -2)
    {
        for (int recv = 1; recv <= MaxClients; recv++)
        {
            if (!IsClientInGame(recv)) continue;
            for (int send = 1; send <= MaxClients; send++)
            {
                if (recv != send && IsClientInGame(send))
                {
                    SetListenOverride(recv, send, ListenOverride_Default);
                }
            }
        }
    }
    
    // Enable alltalk between rounds if configured
    if (g_cvRoundEndAllTalk.BoolValue)
    {
        g_cvAllTalk.BoolValue = true;
        if (g_cvAnnounce.BoolValue)
        {
            VoiceComm_PrintToChatAll("%t", "Round End - All Talk On");
        }
    }
    else if (g_cvAnnounce.BoolValue)
    {
        VoiceComm_PrintToChatAll("%t", "Round End - All Talk Off");
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client || !IsClientInGame(client)) return;
    
    int deadTalkMode = g_cvDeadTalk ? g_cvDeadTalk.IntValue : 0;
    
    // Apply start-of-round mute if still active
    if (g_cvMuteAtStart.BoolValue && !g_bIsMuteTimeUp && g_cvTeamToMute.IntValue == GetClientTeam(client))
    {
        CreateTimer(0.1, Timer_ApplyMute, GetClientUserId(client));
        return;
    }
    
    // Re-apply session mute if needed
    if (g_bMuted[client])
    {
        SetClientListeningFlags(client, VOICE_LISTENTEAM);
        if (g_cvAnnounce.BoolValue)
        {
            PrintToChat(client, "[\x03SM\x01] %t", "Enforce Existing Mute");
        }
    }
    
    // Handle deadtalk=-2 (team-only when dead)
    if (deadTalkMode == -2 && !g_cvAllTalk.BoolValue)
    {
        if (!g_cvTeamTalk.BoolValue)
        {
            // Mute cross-team when dead
            for (int i = 1; i <= MaxClients; i++)
            {
                if (!IsClientInGame(i) || i == client) continue;
                SetListenOverride(i, client, ListenOverride_Mute);
                if (IsPlayerAlive(i))
                {
                    SetListenOverride(client, i, ListenOverride_Mute);
                }
            }
            if (g_cvAnnounce.BoolValue)
            {
                PrintToChat(client, "[\x03SM\x01] %t", "DeadAllTalk - Spawn - TeamTalk Off");
            }
        }
        CreateTimer(0.1, Timer_SetTeamVoice, GetClientUserId(client));
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client || !IsClientInGame(client)) return;
    if (g_bMuted[client]) return;  // Already muted, skip
    
    int deadTalkMode = g_cvDeadTalk ? g_cvDeadTalk.IntValue : 0;
    bool adminOverride = g_cvAdmOvrd_OnDeath.BoolValue;
    bool isAdmin = CheckCommandAccess(client, "", ADMFLAG_ROOT, true);
    
    // deadtalk=-1: mute on death (unless admin override)
    if (deadTalkMode == -1)
    {
        if (!isAdmin || !adminOverride)
        {
            SetClientListeningFlags(client, VOICE_LISTENTEAM);
            if (g_cvAnnounce.BoolValue)
            {
                PrintToChat(client, "[\x03SM\x01] %t", "Muted On Death - Not Admin");
            }
        }
        else if (g_cvAnnounce.BoolValue)
        {
            PrintToChat(client, "[\x03SM\x01] %t", "Muted On Death - Admin");
        }
    }
    
    // deadtalk=-2: dead players hear only dead + teammates (unless admin)
    else if (deadTalkMode == -2 && !g_cvAllTalk.BoolValue)
    {
        SetClientListeningFlags(client, VOICE_LISTENALL);
        
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || i == client) continue;
            
            bool targetAlive = IsPlayerAlive(i);
            int targetTeam = GetClientTeam(i);
            
            if (!targetAlive)
            {
                // Dead players: mute if different team and not admin
                if (targetTeam > 1 && (!isAdmin || !adminOverride))
                {
                    SetListenOverride(i, client, ListenOverride_Mute);
                }
                SetListenOverride(client, i, ListenOverride_Mute);
            }
            else
            {
                // Alive players: mute if not admin
                if (!isAdmin || !adminOverride)
                {
                    SetListenOverride(i, client, ListenOverride_Mute);
                    if (!g_cvDeadHearAlive.BoolValue)
                    {
                        SetListenOverride(client, i, ListenOverride_Mute);
                    }
                }
            }
        }
        
        if (g_cvAnnounce.BoolValue)
        {
            PrintToChat(client, "[\x03SM\x01] %t", isAdmin ? "DeadAllTalk - Death - Admin" : "DeadAllTalk - Death - Not Admin");
        }
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client || event.GetBool("disconnect")) return;
    
    int newTeam = event.GetInt("team");
    int deadTalkMode = g_cvDeadTalk ? g_cvDeadTalk.IntValue : 0;
    
    // First-join mute logic
    if (!g_bHasJoinedOnce[client])
    {
        g_bHasJoinedOnce[client] = true;
        
        if (deadTalkMode != 0)
        {
            bool adminOverride = g_cvAdmOvrd_FirstJoin.BoolValue;
            bool isAdmin = CheckCommandAccess(client, "", ADMFLAG_ROOT, true);
            
            if (!isAdmin || !adminOverride)
            {
                SetClientListeningFlags(client, VOICE_LISTENTEAM);
                if (g_cvAnnounce.BoolValue)
                {
                    PrintToChat(client, "[\x03SM\x01] %t", "Mute On Join");
                }
            }
            else if (g_cvAnnounce.BoolValue)
            {
                PrintToChat(client, "[\x03SM\x01] %t", "Admin On Join");
            }
        }
    }
    
    // Apply team-based listen overrides if teamtalk is disabled
    if (!g_cvTeamTalk.BoolValue)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i)) continue;
            int otherTeam = GetClientTeam(i);
            if (otherTeam > 1 && newTeam != otherTeam)
            {
                SetListenOverride(client, i, ListenOverride_Mute);
            }
        }
    }
}

// ============================================================================
// TIMERS
// ============================================================================
public Action Timer_UnmuteTeam(Handle timer)
{
    g_bIsMuteTimeUp = true;
    g_hUnmuteTimer = null;
    
    int mutedTeam = g_cvTeamToMute.IntValue;
    bool allTalk = g_cvAllTalk.BoolValue;
    bool teamTalk = g_cvTeamTalk.BoolValue;
    
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client)) continue;
        if (GetClientTeam(client) != mutedTeam) continue;
        
        SetClientListeningFlags(client, VOICE_LISTENALL);
        
        if (!allTalk && !teamTalk)
        {
            // Mute cross-team communication
            for (int other = 1; other <= MaxClients; other++)
            {
                if (client != other && IsClientInGame(other) && GetClientTeam(other) != mutedTeam)
                {
                    SetListenOverride(other, client, ListenOverride_Mute);
                }
            }
        }
    }
    
    if (g_cvAnnounce.BoolValue)
    {
        VoiceComm_PrintToChatAll("%t", "Mute Time Expired");
    }
    
    return Plugin_Stop;
}

public Action Timer_ApplyMute(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client && IsClientInGame(client))
    {
        SetClientListeningFlags(client, VOICE_LISTENTEAM);
    }
    return Plugin_Stop;
}

public Action Timer_SetTeamVoice(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client && IsClientInGame(client))
    {
        SetClientListeningFlags(client, VOICE_LISTENGAME);
        if (g_cvAnnounce.BoolValue)
        {
            PrintToChat(client, "[\x03SM\x01] %t", "DeadAllTalk - Spawn - TeamTalk On");
        }
    }
    return Plugin_Stop;
}

public Action Timer_UpdateListening(Handle timer)
{
    int mode = g_cvDeadTalk ? g_cvDeadTalk.IntValue : 0;
    
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || g_bMuted[client]) continue;
        
        if (mode == -1 && !IsPlayerAlive(client))
        {
            SetClientListeningFlags(client, VOICE_LISTENTEAM);
        }
        else if (mode == -2 && !IsPlayerAlive(client))
        {
            SetClientListeningFlags(client, VOICE_LISTENALL);
            bool isAdmin = CheckCommandAccess(client, "", ADMFLAG_ROOT, true);
            
            for (int other = 1; other <= MaxClients; other++)
            {
                if (client == other || !IsClientInGame(other)) continue;
                
                bool otherAlive = IsPlayerAlive(other);
                int otherTeam = GetClientTeam(other);
                
                if (!otherAlive)
                {
                    if (otherTeam > 1 && !isAdmin)
                    {
                        SetListenOverride(other, client, ListenOverride_Mute);
                    }
                    SetListenOverride(client, other, ListenOverride_Mute);
                }
                else
                {
                    if (!isAdmin)
                    {
                        SetListenOverride(other, client, ListenOverride_Mute);
                        if (!g_cvDeadHearAlive.BoolValue)
                        {
                            SetListenOverride(client, other, ListenOverride_Mute);
                        }
                    }
                }
            }
        }
    }
    return Plugin_Stop;
}

public Action Timer_CheckTimedPunishments(Handle timer)
{
    for (int i = 0; i < g_hTimedPunishments.Length; i++)
    {
        int client = g_hTimedPunishments.Get(i);
        if (!IsClientInGame(client)) continue;
        
        g_iTimeRemaining[client]--;
        
        if (g_iTimeRemaining[client] <= 0)
        {
            char steamid[24];
            GetClientAuthString(client, steamid, sizeof(steamid));
            int idx = g_hMutedPlayers.FindString(steamid);
            
            int punishment = (idx != -1) ? g_hMutedPlayers.Get(idx) : 4;
            
            g_hTimedPunishments.Erase(i);
            g_hVoiceCommCookie.Set(client, "0");
            g_iTimeRemaining[client] = 0;
            
            int userid = GetClientUserId(client);
            switch (punishment)
            {
                case 1: ServerCommand("sm_unmute #%d force", userid);
                case 2: ServerCommand("sm_ungag #%d force", userid);
                case 3: ServerCommand("sm_unsilence #%d force", userid);
            }
            i--;  // Adjust index after erase
        }
    }
    return Plugin_Continue;
}

// ============================================================================
// COMMAND LISTENERS (Admin Mute/Unmute Integration)
// ============================================================================
public Action OnAdminMuteCommand(int client, const char[] command, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[SM] Usage: %s <target> [time]", command);
        return Plugin_Handled;
    }
    
    char arg[64], targetName[64];
    GetCmdArg(1, arg, sizeof(arg));
    
    int[] targets = new int[MaxClients];
    int count = ProcessTargetString(arg, client, targets, MaxClients, 0, targetName, sizeof(targetName));
    if (count <= 0)
    {
        ReplyToTargetError(client, count);
        return Plugin_Handled;
    }
    
    int punishmentType = 4;  // default = none
    if (StrEqual(command, "sm_silence", false)) punishmentType = 3;
    else if (StrEqual(command, "sm_mute", false)) punishmentType = 1;
    else if (StrEqual(command, "sm_gag", false)) punishmentType = 2;
    
    char timeStr[20];
    int timeMinutes = 0;
    if (GetCmdArg(2, timeStr, sizeof(timeStr)) > 0)
    {
        timeMinutes = StringToInt(timeStr) & 0xFFFF;
    }
    
    for (int i = 0; i < count; i++)
    {
        int target = targets[i];
        if (punishmentType == 3 || punishmentType == 1)  // silence or mute
        {
            g_bMuted[target] = true;
        }
        
        // Handle timed punishment via cookie
        if (timeMinutes > 0)
        {
            char cookie[20];
            g_hVoiceCommCookie.Get(target, cookie, sizeof(cookie));
            int mask = StringToInt(cookie) & 0x07;  // preserve type bits
            
            mask |= (timeMinutes << 3);  // store time in upper bits
            IntToString(mask, cookie, sizeof(cookie));
            g_hVoiceCommCookie.Set(target, cookie);
            
            if (g_hTimedPunishments.FindValue(target) == -1)
            {
                g_hTimedPunishments.Push(target);
            }
            g_iTimeRemaining[target] = timeMinutes;
        }
        
        // Store in session array for reconnect enforcement
        char steamid[24];
        GetClientAuthString(target, steamid, sizeof(steamid));
        if (g_hMutedPlayers.FindString(steamid) == -1)
        {
            g_hMutedPlayers.PushString(steamid);
            g_hMutedPlayers.Set(g_hMutedPlayers.Length - 1, punishmentType);
        }
    }
    
    return Plugin_Handled;
}

public Action OnAdminUnmuteCommand(int client, const char[] command, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[SM] Usage: %s <target> [force]", command);
        return Plugin_Handled;
    }
    
    char arg[64], targetName[64];
    GetCmdArg(1, arg, sizeof(arg));
    
    int[] targets = new int[MaxClients];
    int count = ProcessTargetString(arg, client, targets, MaxClients, 0, targetName, sizeof(targetName));
    if (count <= 0)
    {
        ReplyToTargetError(client, count);
        return Plugin_Handled;
    }
    
    bool force = (GetCmdArg(2, arg, sizeof(arg)) > 0 && StrEqual(arg, "force", false));
    
    for (int i = 0; i < count; i++)
    {
        int target = targets[i];
        g_bMuted[target] = false;
        
        if (force)
        {
            int idx = g_hTimedPunishments.FindValue(target);
            if (idx != -1) g_hTimedPunishments.Erase(idx);
            g_hVoiceCommCookie.Set(target, "0");
            g_iTimeRemaining[target] = 0;
            ReplyToCommand(client, "[\x03SM\x01] %t", "Removed Stateful Mute", target);
        }
        
        // Remove from session array
        char steamid[24];
        GetClientAuthString(target, steamid, sizeof(steamid));
        idx = g_hMutedPlayers.FindString(steamid);
        if (idx != -1) g_hMutedPlayers.Erase(idx);
    }
    
    return Plugin_Handled;
}

public Action Command_ListMutes(int client, int args)
{
    bool found = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bMuted[i] && IsClientInGame(i))
        {
            ReplyToCommand(client, "[\x03SM\x01] %t", "List Mute Name", i);
            found = true;
        }
    }
    if (!found)
    {
        ReplyToCommand(client, "[\x03SM\x01] %t", "No Muted Players");
    }
    return Plugin_Handled;
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================
// Renamed to avoid overriding the native - prevents conflicts with other plugins
void VoiceComm_PrintToChatAll(const char[] format, any ...)
{
    char buffer[192];
    VFormat(buffer, sizeof(buffer), format, 3);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            PrintToChat(i, "%s", buffer);
        }
    }
}
