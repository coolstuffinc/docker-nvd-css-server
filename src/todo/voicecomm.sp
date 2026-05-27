#include <sourcemod>
#include <sdktools>
#include <clientprefs>

public PlVers:__version =
{
	version = 5,
	filevers = "1.3.9-dev",
	date = "06/13/2014",
	time = "04:03:09"
};
//new Float:NULL_VECTOR[3];
//new String:NULL_STRING[4];
public Extension:__ext_core =
{
	name = "Core",
	file = "core",
	autoload = 0,
	required = 0,
};
//new MaxClients;
public Extension:__ext_sdktools =
{
	name = "SDKTools",
	file = "sdktools.ext",
	autoload = 1,
	required = 1,
};
public Extension:__ext_cprefs =
{
	name = "Client Preferences",
	file = "clientprefs.ext",
	autoload = 1,
	required = 1,
};
public Plugin:myinfo =
{
	name = "Voice Comm",
	description = "Provides additional methods of controlling voice communication.",
	author = "databomb",
	version = "2.2.1",
	url = "vintagejailbreak.org"
};
new Handle:gH_Cvar_DeadTalk;
new Handle:gH_Cvar_AllTalk;
new Handle:gH_Cvar_Announce;
new Handle:gH_Cvar_MuteTime;
new Handle:gH_Cvar_RoundEndAllTalk;
new Handle:gH_Cvar_DeadHearAlive;
new Handle:gH_Cvar_MuteAtStart;
new Handle:gH_Cvar_TeamTalk;
new Handle:gH_UnmuteTimer;
new Handle:gH_Cvar_TeamToMute;
new Handle:gH_Cvar_MuteSpectators;
new Handle:gH_Cvar_BlockUnMuteOnRetry;
new Handle:gH_Cvar_AdmOvrd_FirstJoin;
new Handle:gH_Cvar_AdmOvrd_Spec;
new Handle:gH_Cvar_AdmOvrd_OnDeath;
new Handle:gH_Muted_Players;
new Handle:gH_Cookie_VoiceCommMask;
new Handle:gH_TimedPunishmentLocalArray;
new bool:g_bMuted[66];
new bool:g_bHasJoinedOnce[66];
new gA_LocalTimeRemaining[66];
new bool:g_BetweenRounds;
new bool:g_IsMuteTimeUp;
new bool:g_bHooked;


		i++;
	}
	//return 0;
}

public void OnPluginStart()
{
	LoadTranslations("voicecomm.phrases");
	LoadTranslations("common.phrases");
	CreateConVar("sm_voicecomm_version", "2.2.1", "Version of VoiceComm Plugin", 139584, false, 0.0, false, 0.0);
	gH_Cvar_Announce = CreateConVar("sm_voicecomm_announce", "1", "Enable or disable the messages: 0 - disabled, 1 - enabled", 262144, true, 0.0, true, 1.0);
	gH_Cvar_TeamTalk = CreateConVar("sm_voicecomm_teamtalk", "0", "Controls talking when alive if deadtalk is set to -2. 0 - Players talk to both teams when alive, 1 - Players talk to only their teammates when alive", 262144, true, 0.0, true, 1.0);
	gH_Cvar_MuteTime = CreateConVar("sm_voicecomm_mutetime", "29.0", "Controls the length of time terrorists are muted starting from the beginning of the round.", 262144, true, 2.5, false, 0.0);
	gH_Cvar_DeadHearAlive = CreateConVar("sm_voicecomm_deadhearalive", "1", "Controls hearing after death. 0 - Dead players do not hear alive players. 1 - Dead hear alive.", 262144, true, 0.0, true, 1.0);
	gH_Cvar_MuteAtStart = CreateConVar("sm_voicecomm_startmuted", "1", "Controls whether a team starts the round muted.", 262144, true, 0.0, true, 1.0);
	gH_Cvar_TeamToMute = CreateConVar("sm_voicecomm_mutedteam", "2", "Defines the team to mute if startmuted is enabled. In CS:S, 2=Terrorists, 3=CTs", 262144, true, 1.0, true, 3.0);
	gH_Cvar_RoundEndAllTalk = CreateConVar("sm_voicecomm_roundendalltalk", "1", "Controls whether all talk is turned on between the time between rounds", 262144, true, 0.0, true, 1.0);
	gH_Cvar_MuteSpectators = CreateConVar("sm_voicecomm_spectatormute", "1", "Controls whether spectators are automatically muted. (Admins are exempt).", 262144, true, 0.0, true, 1.0);
	gH_Cvar_BlockUnMuteOnRetry = CreateConVar("sm_voicecomm_blockunmuteonreconnect", "1", "Controls whether players will automatically be unmuted when rejoining or if previous mutes are enforced.", 262144, true, 0.0, true, 1.0);
	gH_Cvar_AdmOvrd_FirstJoin = CreateConVar("sm_voicecomm_admovrd_firstjoin", "1", "If enabled admins who first join will be allowed to talk.", 262144, true, 0.0, true, 1.0);
	gH_Cvar_AdmOvrd_OnDeath = CreateConVar("sm_voicecomm_admovrd_death", "1", "If enabled admins who die are allowed to talk with everyone.", 262144, true, 0.0, true, 1.0);
	gH_Cvar_AdmOvrd_Spec = CreateConVar("sm_voicecomm_admovrd_spectate", "1", "If enabled admins speak with everyone on round start if they are a spectator.", 262144, true, 0.0, true, 1.0);
	gH_Cookie_VoiceCommMask = RegClientCookie("VoiceComm_Status", "Bit-mask for VoiceComm status", CookieAccess:2);
	gH_TimedPunishmentLocalArray = CreateArray(1, 0);
	new idx = 1;
	while (idx <= MaxClients)
	{
		gA_LocalTimeRemaining[idx] = 0;
		idx++;
	}
	gH_Cvar_AllTalk = FindConVar("sv_alltalk");
	SetConVarFlags(gH_Cvar_AllTalk, GetConVarFlags(gH_Cvar_AllTalk) & -257);
	AddCommandListener(Listen_EffectiveMute, "sm_mute");
	AddCommandListener(Listen_EffectiveMute, "sm_gag");
	AddCommandListener(Listen_EffectiveMute, "sm_silence");
	AddCommandListener(Listen_EffectiveUnMute, "sm_unmute");
	AddCommandListener(Listen_EffectiveUnMute, "sm_ungag");
	AddCommandListener(Listen_EffectiveUnMute, "sm_unsilence");
	RegAdminCmd("sm_listmutes", Command_MuteCheck, 512, "sm_listmutes - Lists all player names who are currently muted.", "", 0);
	HookConVarChange(gH_Cvar_AllTalk, ConVarChange_AllTalk);
	gH_Muted_Players = CreateArray(23, 0);
	CreateTimer(60.0, CheckTimedPunishments, any:0, 1);
	AutoExecConfig(true, "voicecomm", "sourcemod");
	//return 0;
}

public void OnAllPluginsLoaded()
{
	gH_Cvar_DeadTalk = FindConVar("sm_deadtalk");
	if (gH_Cvar_DeadTalk)
	{
		SetConVarBounds(gH_Cvar_DeadTalk, ConVarBounds:1, true, -2.0);
	}
	//return 0;
}

public void OnConfigsExecuted()
{
	if (gH_Cvar_DeadTalk)
	{
		new var1;
		if (GetConVarInt(gH_Cvar_DeadTalk) < 0 && !g_bHooked)
		{
			HookEvent("player_death", PlayerDeath, EventHookMode:1);
			HookEvent("player_spawn", PlayerSpawn, EventHookMode:1);
			HookEvent("round_start", RoundStart, EventHookMode:1);
			HookEvent("round_end", RoundEnd, EventHookMode:1);
			HookEvent("player_team", Event_PlayerTeamSwitch, EventHookMode:1);
			g_bHooked = true;
		}
		HookConVarChange(gH_Cvar_DeadTalk, ConVarChange_DeadTalk);
	}
	//return 0;
}

public ConVarChange_DeadTalk(Handle:cvar, String:oldVal[], String:newVal[])
{
	new var1;
	if (GetConVarInt(gH_Cvar_DeadTalk) < 0 && !g_bHooked)
	{
		HookEvent("player_death", PlayerDeath, EventHookMode:1);
		HookEvent("player_spawn", PlayerSpawn, EventHookMode:1);
		HookEvent("round_start", RoundStart, EventHookMode:1);
		HookEvent("round_end", RoundEnd, EventHookMode:1);
		HookEvent("player_team", Event_PlayerTeamSwitch, EventHookMode:1);
		g_bHooked = true;
	}
	else
	{
		new var2;
		if (g_bHooked && GetConVarInt(gH_Cvar_DeadTalk) >= 0)
		{
			UnhookEvent("player_death", PlayerDeath, EventHookMode:1);
			UnhookEvent("player_spawn", PlayerSpawn, EventHookMode:1);
			UnhookEvent("round_start", RoundStart, EventHookMode:1);
			UnhookEvent("round_end", RoundEnd, EventHookMode:1);
			UnhookEvent("player_team", Event_PlayerTeamSwitch, EventHookMode:1);
			g_bHooked = false;
		}
	}
	//return 0;
}

public ConVarChange_AllTalk(Handle:convar, String:oldValue[], String:newValue[])
{
	CreateTimer(0.1, Timer_AllTalk, any:0, 2);
	//return 0;
}

public Action:Timer_AllTalk(Handle:timer)
{
	new mode = GetConVarInt(gH_Cvar_DeadTalk);
	new i = 1;
	while (i <= MaxClients)
	{
		if (IsClientInGame(i))
		{
			if (!g_bMuted[i])
			{
				new var1;
				if (mode == -1 && !IsPlayerAlive(i))
				{
					SetClientListeningFlags(i, 1);
				}
				else
				{
					new var2;
					if (mode == -2 && !IsPlayerAlive(i))
					{
						SetClientListeningFlags(i, 0);
						new DoesUserHaveAdmin = GetAdminFlag(GetUserAdmin(i), AdminFlag:9, AdmAccessMode:1);
						new idx = 1;
						while (idx <= MaxClients)
						{
							new var3;
							if (i != idx && IsClientInGame(idx))
							{
								new indexTeam = GetClientTeam(idx);
								if (!IsPlayerAlive(idx))
								{
									new var4;
									if (indexTeam > 1 && !DoesUserHaveAdmin)
									{
										SetListenOverride(idx, i, ListenOverride:2);
									}
									SetListenOverride(i, idx, ListenOverride:2);
								}
								else
								{
									new var5;
									if (IsPlayerAlive(idx) && !DoesUserHaveAdmin)
									{
										SetListenOverride(idx, i, ListenOverride:1);
										if (!GetConVarBool(gH_Cvar_DeadHearAlive))
										{
											SetListenOverride(i, idx, ListenOverride:1);
										}
									}
								}
							}
							idx++;
						}
					}
				}
			}
		}
		i++;
	}
	return Action:4;
}

public bool:OnClientConnect(client, String:rejectmsg[], maxlen)
{
	g_bMuted[client] = 0;
	g_bHasJoinedOnce[client] = 0;
	return true;
}

public Action:Command_MuteCheck(client, args)
{
	new idx = 1;
	while (idx <= MaxClients)
	{
		if (g_bMuted[idx])
		{
			ReplyToCommand(client, "[\x03SM\x01] %t", "List Mute Name", idx);
		}
		idx++;
	}
	return Plugin_Handled;
}

public Action:Timer_DelayedTeamVoice(Handle:timer)
{
	g_IsMuteTimeUp = true;
	new mutedTeam = GetConVarInt(gH_Cvar_TeamToMute);
	new AllTalk = GetConVarInt(gH_Cvar_AllTalk);
	new TeamTalk = GetConVarBool(gH_Cvar_TeamTalk);
	new idx = 1;
	while (idx <= MaxClients)
	{
		if (IsClientInGame(idx))
		{
			new clientTeam = GetClientTeam(idx);
			new var1;
			if (mutedTeam == clientTeam && IsPlayerAlive(idx))
			{
				SetClientListeningFlags(idx, 0);
				new var2;
				if (!AllTalk && !TeamTalk)
				{
					new Tidx = 1;
					while (Tidx <= MaxClients)
					{
						if (IsClientInGame(Tidx))
						{
							new TidxTeam = GetClientTeam(Tidx);
							new var3;
							if (idx != Tidx && clientTeam != TidxTeam)
							{
								SetListenOverride(Tidx, idx, ListenOverride:2);
							}
						}
						Tidx++;
					}
				}
			}
		}
		idx++;
	}
	if (GetConVarBool(gH_Cvar_Announce))
	{
	gH_UnmuteTimer = MissingTAG:0;
	return Action:0;
}

public Action:RoundStart(Handle:event, String:name[], bool:dontBroadcast)
{
	g_BetweenRounds = false;
	new Announce = GetConVarBool(gH_Cvar_Announce);
	if (GetConVarBool(gH_Cvar_RoundEndAllTalk))
	{
		SetConVarBool(gH_Cvar_AllTalk, false, false, false);
	}
	if (GetConVarBool(gH_Cvar_MuteAtStart))
	{
		if (Announce)
		{
		gH_UnmuteTimer = CreateTimer(GetConVarFloat(gH_Cvar_MuteTime), Timer_DelayedTeamVoice, any:0, 2);
	}
	else
	{
		if (Announce)
		{
	}
	if (GetConVarBool(gH_Cvar_MuteSpectators))
	{
		new AdmIdx = 1;
		while (AdmIdx <= MaxClients)
		{
			if (IsClientInGame(AdmIdx))
			{
				if (GetClientTeam(AdmIdx) == 1)
				{
					new var1;
					if (GetAdminFlag(GetUserAdmin(AdmIdx), AdminFlag:9, AdmAccessMode:1) && GetConVarBool(gH_Cvar_AdmOvrd_Spec))
					{
						if (Announce)
						{
							PrintToChat(AdmIdx, "[\x03SM\x01] %t", "Spectator - Admin");
						}
						new PIdx = 1;
						while (PIdx <= MaxClients)
						{
							new var2;
							if (IsClientInGame(PIdx) && AdmIdx != PIdx)
							{
								SetListenOverride(PIdx, AdmIdx, ListenOverride:2);
							}
							PIdx++;
						}
					}
					if (Announce)
					{
						PrintToChat(AdmIdx, "[\x03SM\x01] %t", "Spectator - Not Admin");
					}
					new idx = 1;
					while (idx <= MaxClients)
					{
						new var3;
						if (IsClientInGame(idx) && AdmIdx != idx)
						{
							SetListenOverride(idx, AdmIdx, ListenOverride:1);
						}
						idx++;
					}
				}
			}
			AdmIdx++;
		}
	}
	return Action:0;
}

public Action:PlayerSpawn(Handle:event, String:name[], bool:dontBroadcast)
{
	new DeadTalkMode = GetConVarInt(gH_Cvar_DeadTalk);
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client)
	{
		return Action:0;
	}
	new var1;
	if (GetConVarBool(gH_Cvar_MuteAtStart) && !g_IsMuteTimeUp && GetConVarInt(gH_Cvar_TeamToMute) == GetClientTeam(client))
	{
		CreateTimer(0.1, Timer_DoMute, client, 2);
	}
	else
	{
		if (g_bMuted[client] == true)
		{
			SetClientListeningFlags(client, 1);
			if (GetConVarInt(gH_Cvar_Announce))
			{
				PrintToChat(client, "[\x03SM\x01] %t", "Enforce Existing Mute");
			}
		}
		if (!(DeadTalkMode == -1))
		{
			if (DeadTalkMode == -2)
			{
				if (!GetConVarBool(gH_Cvar_TeamTalk))
				{
					new idx = 1;
					while (idx <= MaxClients)
					{
						if (IsClientInGame(idx))
						{
							if (client != idx)
							{
								SetListenOverride(idx, client, ListenOverride:2);
								if (IsPlayerAlive(idx))
								{
									SetListenOverride(client, idx, ListenOverride:2);
								}
							}
						}
						idx++;
					}
					if (GetConVarInt(gH_Cvar_Announce))
					{
						PrintToChat(client, "[\x03SM\x01] %t", "DeadAllTalk - Spawn - TeamTalk Off");
					}
				}
				CreateTimer(0.1, Timer_DoTeam, client, 2);
			}
		}
	}
	return Action:0;
}

public Action:Timer_DoTeam(Handle:timer, any:client)
{
	if (IsClientInGame(client))
	{
		SetClientListeningFlags(client, 8);
		if (GetConVarBool(gH_Cvar_Announce))
		{
			PrintToChat(client, "[\x03SM\x01] %t", "DeadAllTalk - Spawn - TeamTalk On");
		}
	}
	return Action:4;
}

public Action:Timer_DoMute(Handle:timer, any:client)
{
	if (IsClientInGame(client))
	{
		SetClientListeningFlags(client, 1);
	}
	return Action:4;
}

public PlayerDeath(Handle:event, String:name[], bool:dontBroadcast)
{
	new DeadTalkMode = GetConVarInt(gH_Cvar_DeadTalk);
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new RoundEndAllTalk = GetConVarBool(gH_Cvar_RoundEndAllTalk);
	new bool:AdminOverrideDeath = GetConVarBool(gH_Cvar_AdmOvrd_OnDeath);
	if (!client)
	{
		//return 0;
	}
	if (g_bMuted[client])
	{
		//return 0;
	}
	new var2;
	if (!g_BetweenRounds || (g_BetweenRounds && !RoundEndAllTalk))
	{
		if (DeadTalkMode == -1)
		{
			new var3;
			if (!GetAdminFlag(GetUserAdmin(client), AdminFlag:9, AdmAccessMode:1) || !AdminOverrideDeath)
			{
				SetClientListeningFlags(client, 1);
				if (GetConVarBool(gH_Cvar_Announce) == 1)
				{
					PrintToChat(client, "[\x03SM\x01] %t", "Muted On Death - Not Admin");
				}
			}
			else
			{
				if (AdminOverrideDeath)
				{
					if (GetConVarBool(gH_Cvar_Announce) == 1)
					{
						PrintToChat(client, "[\x03SM\x01] %t", "Muted On Death - Admin");
					}
				}
			}
		}
		new var4;
		if (DeadTalkMode == -2 && !GetConVarBool(gH_Cvar_AllTalk))
		{
			SetClientListeningFlags(client, 0);
			new DoesUserHaveAdmin;
			if (AdminOverrideDeath)
			{
				DoesUserHaveAdmin = GetAdminFlag(GetUserAdmin(client), AdminFlag:9, AdmAccessMode:1);
			}
			new idx = 1;
			while (idx <= MaxClients)
			{
				new var5;
				if (client != idx && IsClientInGame(idx))
				{
					new indexTeam = GetClientTeam(idx);
					if (!IsPlayerAlive(idx))
					{
						new var6;
						if (indexTeam != 1 && !DoesUserHaveAdmin)
						{
							SetListenOverride(idx, client, ListenOverride:2);
						}
						SetListenOverride(client, idx, ListenOverride:2);
					}
					else
					{
						new var7;
						if (IsPlayerAlive(idx) && !DoesUserHaveAdmin)
						{
							SetListenOverride(idx, client, ListenOverride:1);
							if (!GetConVarBool(gH_Cvar_DeadHearAlive))
							{
								SetListenOverride(client, idx, ListenOverride:1);
							}
						}
					}
				}
				idx++;
			}
			if (GetConVarInt(gH_Cvar_Announce))
			{
				if (DoesUserHaveAdmin)
				{
					PrintToChat(client, "[\x03SM\x01] %t", "DeadAllTalk - Death - Admin");
				}
				PrintToChat(client, "[\x03SM\x01] %t", "DeadAllTalk - Death - Not Admin");
			}
		}
	}
	//return 0;
}

public Action:RoundEnd(Handle:event, String:name[], bool:dontBroadcast)
{
	g_BetweenRounds = true;
	g_IsMuteTimeUp = false;
	if (gH_UnmuteTimer)
	{
		CloseHandle(gH_UnmuteTimer);
		gH_UnmuteTimer = MissingTAG:0;
		new idx = 1;
		while (idx <= MaxClients)
		{
			if (IsClientInGame(idx))
			{
				if (!g_bMuted[idx])
				{
					SetClientListeningFlags(idx, 0);
				}
			}
			idx++;
		}
	}
	new DeadTalkMode = GetConVarInt(gH_Cvar_DeadTalk);
	if (DeadTalkMode == -2)
	{
		new RcvIdx = 1;
		while (RcvIdx <= MaxClients)
		{
			new SndIdx = 1;
			while (SndIdx <= MaxClients)
			{
				new var1;
				if (IsClientInGame(RcvIdx) && IsClientInGame(SndIdx) && RcvIdx != SndIdx)
				{
					SetListenOverride(RcvIdx, SndIdx, ListenOverride:0);
				}
				SndIdx++;
			}
			RcvIdx++;
		}
	}
	if (GetConVarBool(gH_Cvar_RoundEndAllTalk))
	{
		SetConVarBool(gH_Cvar_AllTalk, true, false, false);
		if (GetConVarInt(gH_Cvar_Announce))
		{
	}
	else
	{
		if (GetConVarInt(gH_Cvar_Announce))
		{
	}
	return Action:0;
}

public Action:Event_PlayerTeamSwitch(Handle:event, String:name[], bool:dontBroadcast)
{
	new NewTeam = GetEventInt(event, "team");
	new Bool:Disconnect = GetEventBool(event, "disconnect");
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (Disconnect)
	{
		return Plugin_Handled;
	}
	new DeadTalkMode = GetConVarInt(gH_Cvar_DeadTalk);
	if (!g_bHasJoinedOnce[client])
	{
		g_bHasJoinedOnce[client] = 1;
		if (DeadTalkMode)
		{
			new bool:AdminOverrideJoin = GetConVarBool(gH_Cvar_AdmOvrd_FirstJoin);
			new var1;
			if (!GetAdminFlag(GetUserAdmin(client), AdminFlag:9, AdmAccessMode:1) || !AdminOverrideJoin)
			{
				SetClientListeningFlags(client, 1);
				if (GetConVarBool(gH_Cvar_Announce))
				{
					PrintToChat(client, "[\x03SM\x01] %t", "Mute On Join");
				}
			}
			else
			{
				if (AdminOverrideJoin)
				{
					if (GetConVarBool(gH_Cvar_Announce))
					{
						PrintToChat(client, "[\x03SM\x01] %t", "Admin On Join");
					}
				}
			}
		}
	}
	if (!GetConVarBool(gH_Cvar_TeamTalk))
	{
		new idx = 1;
		while (idx <= MaxClients)
		{
			if (IsClientInGame(idx))
			{
				new idxTeam = GetClientTeam(idx);
				new var2;
				if (idxTeam > 1 && NewTeam != idxTeam)
				{
					SetListenOverride(client, idx, ListenOverride:2);
				}
			}
			idx++;
		}
	}
	return Plugin_Handled;
}

public Action:Listen_EffectiveMute(client, String:command[], args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: %s <target> <optional:time>", command);
		return Plugin_Handled;
	}
	decl String:arg[64];
	GetCmdArg(1, arg, 64);
	decl String:target_name[64];
	decl target_list[65];
	decl target_count;
	decl bool:tn_is_ml;
	if (0 >= (target_count = ProcessTargetString(arg, client, target_list, 65, 0, target_name, 64, tn_is_ml)))
	{
		return Action:0;
	}
	new i;
	while (i < target_count)
	{
		new VCommType:Punishment = 4;
		if (StrEqual(command, "sm_silence", false))
		{
			g_bMuted[target_list[i]] = 1;
			Punishment = MissingTAG:3;
		}
		else
		{
			if (StrEqual(command, "sm_mute", false))
			{
				g_bMuted[target_list[i]] = 1;
				Punishment = MissingTAG:1;
			}
			if (StrEqual(command, "sm_gag", false))
			{
				Punishment = MissingTAG:2;
			}
		}
		if (GetCmdArgs() > 1)
		{
			decl String:sTime[20];
			GetCmdArg(2, sTime, 20);
			new iTime = StringToInt(sTime, 10);
			iTime &= 65535;
			decl String:sBitMask[20];
			GetClientCookie(target_list[i], gH_Cookie_VoiceCommMask, sBitMask, 19);
			new iBitMask = StringToInt(sBitMask, 10);
			switch (Punishment)
			{
				case 1:
				{
					iBitMask |= 1;
				}
				case 2:
				{
					iBitMask |= 2;
				}
				case 3:
				{
					iBitMask |= 3;
				}
				default:
				{
				}
			}
			if (0 < iTime)
			{
				iBitMask &= 7;
				iBitMask = iTime << 3 | iBitMask;
				IntToString(iBitMask, sBitMask, 19);
				SetClientCookie(target_list[i], gH_Cookie_VoiceCommMask, sBitMask);
				new iFindIdx = FindValueInArray(gH_TimedPunishmentLocalArray, target_list[i]);
				if (iFindIdx == -1)
				{
					PushArrayCell(gH_TimedPunishmentLocalArray, target_list[i]);
				}
				gA_LocalTimeRemaining[target_list[i]] = iTime;
			}
			else
			{
				if (!iTime)
				{
					iBitMask |= 4;
					iBitMask &= 7;
					IntToString(iBitMask, sBitMask, 19);
					SetClientCookie(target_list[i], gH_Cookie_VoiceCommMask, sBitMask);
				}
			}
		}
		decl String:sSteamID[24];
		GetClientAuthId(target_list[i], sSteamID, 22);
		new iFindIndex = FindStringInArray(gH_Muted_Players, sSteamID);
		if (iFindIndex == -1)
		{
			new iPushedIndex = PushArrayString(gH_Muted_Players, sSteamID);
			SetArrayCell(gH_Muted_Players, iPushedIndex, Punishment, 22, false);
		}
		i++;
	}
	return Action:0;
}

public Action:Listen_EffectiveUnMute(client, String:command[], args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: %s <target> <optional:'force'>", command);
		return Plugin_Handled;
	}
	decl String:arg[64];
	GetCmdArg(1, arg, 64);
	decl String:target_name[64];
	decl target_list[65];
	decl target_count;
	decl bool:tn_is_ml;
	if (0 >= (target_count = ProcessTargetString(arg, client, target_list, 65, 0, target_name, 64, tn_is_ml)))
	{
		return Action:0;
	}
	new i;
	while (i < target_count)
	{
		g_bMuted[target_list[i]] = 0;
		if (GetCmdArgs() > 1)
		{
			decl String:sOption[20];
			GetCmdArg(2, sOption, 20);
			if (StrEqual(sOption, "force", false))
			{
				new iFindIdx = FindValueInArray(gH_TimedPunishmentLocalArray, target_list[i]);
				if (iFindIdx != -1)
				{
					RemoveFromArray(gH_TimedPunishmentLocalArray, iFindIdx);
				}
				SetClientCookie(target_list[i], gH_Cookie_VoiceCommMask, "0");
				ReplyToCommand(client, "[\x03SM\x01] %t", "Removed Stateful Mute", target_list[i]);
			}
		}
		decl String:sSteamID[24];
		GetClientAuthId(target_list[i], sSteamID, 22);
		new arrayIndex = FindStringInArray(gH_Muted_Players, sSteamID);
		if (arrayIndex != -1)
		{
			RemoveFromArray(gH_Muted_Players, arrayIndex);
		}
		i++;
	}
	return Action:0;
}

public OnMapEnd()
{
	new player = 1;
	while (player <= MaxClients)
	{
		g_bMuted[player] = 0;
		player++;
	}
	ClearArray(gH_Muted_Players);
	//return 0;
}

public void OnClientDisconnect(int client)
{
	new iFindIdx = FindValueInArray(gH_TimedPunishmentLocalArray, client);
	if (iFindIdx != -1)
	{
		decl String:sCookie[20];
		GetClientCookie(client, gH_Cookie_VoiceCommMask, sCookie, 19);
		new iCookie = StringToInt(sCookie, 10);
		iCookie &= 7;
		new var1;
		if (gA_LocalTimeRemaining[client] > 0 && gA_LocalTimeRemaining[client] < 65536)
		{
			iCookie = gA_LocalTimeRemaining[client] << 3 | iCookie;
		}
		gA_LocalTimeRemaining[client] = 0;
		IntToString(iCookie, sCookie, 19);
		SetClientCookie(client, gH_Cookie_VoiceCommMask, sCookie);
		RemoveFromArray(gH_TimedPunishmentLocalArray, iFindIdx);
	}
	//return 0;
}

public OnClientPostAdminCheck(client)
{
	new userid = GetClientUserId(client);
	new VCommType:PunishmentType = 4;
	if (AreClientCookiesCached(client))
	{
		decl String:sBitMask[20];
		GetClientCookie(client, gH_Cookie_VoiceCommMask, sBitMask, 18);
		new iBitMask = StringToInt(sBitMask, 10);
		if (iBitMask)
		{
			new iTimeRemaining = iBitMask >>> 3;
			iTimeRemaining &= 65535;
			if (!(iBitMask & 4))
			{
				if (0 < iTimeRemaining)
				{
					PushArrayCell(gH_TimedPunishmentLocalArray, client);
					gA_LocalTimeRemaining[client] = iTimeRemaining;
				}
			}
			switch (iBitMask & 2 | 1)
			{
				case 1:
				{
					PunishmentType = MissingTAG:1;
					ServerCommand("sm_mute #%d", userid);
				}
				case 2:
				{
					PunishmentType = MissingTAG:2;
					ServerCommand("sm_gag #%d", userid);
				}
				case 3:
				{
					PunishmentType = MissingTAG:3;
					ServerCommand("sm_silence #%d", userid);
				}
				default:
				{
				}
			}
		}
	}
	new var1;
	if (GetConVarBool(gH_Cvar_BlockUnMuteOnRetry) && PunishmentType == VCommType:4)
	{
		decl String:sSteamID[24];
		GetClientAuthId(client, sSteamID, 22);
		new arrayIndex = FindStringInArray(gH_Muted_Players, sSteamID);
		if (arrayIndex != -1)
		{
			new VCommType:ThePunishment = GetArrayCell(gH_Muted_Players, arrayIndex, 22, false);
			switch (ThePunishment)
			{
				case 1:
				{
					ServerCommand("sm_mute #%d", userid);
				}
				case 2:
				{
					ServerCommand("sm_gag #%d", userid);
				}
				case 3:
				{
					ServerCommand("sm_silence #%d", userid);
				}
				default:
				{
				}
			}
		}
	}
	//return 0;
}

public Action:CheckTimedPunishments(Handle:timer)
{
	new iTimeArraySize = GetArraySize(gH_TimedPunishmentLocalArray);
	new idx;
	while (idx < iTimeArraySize)
	{
		new iClientIndex = GetArrayCell(gH_TimedPunishmentLocalArray, idx, 0, false);
		if (IsClientInGame(iClientIndex))
		{
			gA_LocalTimeRemaining[iClientIndex]--;
			if (0 >= gA_LocalTimeRemaining[iClientIndex])
			{
				decl String:sSteamID[24];
				GetClientAuthId(iClientIndex, sSteamID, 22);
				new iFindIndex = FindStringInArray(gH_Muted_Players, sSteamID);
				new VCommType:CommPunishment = 4;
				if (iFindIndex != -1)
				{
					CommPunishment = GetArrayCell(gH_Muted_Players, iFindIndex, 22, false);
				}
				RemoveFromArray(gH_TimedPunishmentLocalArray, idx);
				SetClientCookie(iClientIndex, gH_Cookie_VoiceCommMask, "0");
				new userid = GetClientUserId(iClientIndex);
				switch (CommPunishment)
				{
					case 1:
					{
						ServerCommand("sm_unmute #%d force", userid);
					}
					case 2:
					{
						ServerCommand("sm_ungag #%d force", userid);
					}
					case 3:
					{
						ServerCommand("sm_unsilence #%d force", userid);
					}
					default:
					{
					}
				}
			}
		}
		idx++;
	}
	return Action:0;
}

