// CVars' handles
new Handle:cvar_save_scores_css_cash = INVALID_HANDLE;
new Handle:cvar_save_scores_css_spec_cash = INVALID_HANDLE;
new Handle:cvar_startmoney = INVALID_HANDLE;

// Cvars' variables
new bool:save_scores_css_cash = true;
new bool:save_scores_css_spec_cash = true;
new g_CSDefaultCash = 800;

// Offsets
new g_iAccount = -1;

// Loading CS stuff on plugin start
public CS_Stuff()
{
	// Creating cvars
	cvar_save_scores_css_cash = CreateConVar("sm_save_scores_css_cash", "1", "If set to 1 the save scores will also restore players' cash, 0 = off/1 = on", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvar_save_scores_css_spec_cash = CreateConVar("sm_save_scores_css_spec_cash", "1", "If set to 1 the save scores will save spectators' cash and restore it after team join, 0 = off/1 = on", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvar_startmoney = FindConVar("mp_startmoney");
	
	// Hooking cvar change
	HookConVarChange(cvar_save_scores_css_cash, OnCVarChange);
	HookConVarChange(cvar_save_scores_css_spec_cash, OnCVarChange);
	HookConVarChange(cvar_startmoney, OnCVarChange);
	
	// Finding offset for CS cash
	g_iAccount = FindSendPropOffs("CCSPlayer", "m_iAccount");
	if (g_iAccount == -1)
		SetFailState("m_iAccount offset not found");
	
	// Hooking command for detecting of new game start
	cvar_restartgame = FindConVar("mp_restartgame");
	if (cvar_restartgame != INVALID_HANDLE)
		HookConVarChange(cvar_restartgame, NewGameCommand);
	
	// Hooking events for detecting of new game start
	HookEvent("round_start", Event_NewGameStart);
	HookEvent("round_end", Event_RoundEnd);
}

// Set player's cash if game is CS
public SetCash(client, cash)
{
	if (Game == GAME_CS)
	{
		SetEntData(client, g_iAccount, cash, 4, true);
	}
}

// Simply get player's CS cash or return 0 if game is not CS
public GetCash(client)
{
	if (Game == GAME_CS)
	{
		return GetEntData(client, g_iAccount);
	}
	
	return 0;
}