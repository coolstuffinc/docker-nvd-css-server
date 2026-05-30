/**
 * 核心功能模块
 */

#if defined _mixmod_core_included
  #endinput
#endif
#define _mixmod_core_included

/**
 * 初始化ConVars
 */
void Mix_InitConVars()
{
    // 载入翻译文件
    LoadTranslations("common.phrases");

    // 创建ConVars
    g_hCvarEnabled = CreateConVar("sm_mixmod_enable", "1", "Enable/Disable this plugin: 0 - Off, 1 - On");
    g_hCvarShowMoneyAndWeapons = CreateConVar("sm_mixmod_showmoney", "1", "Show money/weapons info to teammates? 0 - Off, 1 - On");
    g_hCvarShowScores = CreateConVar("sm_mixmod_showscores", "1", "Show scores on round start? 0 - Off, 1 - On");
    g_hCvarEnableRRCommand = CreateConVar("sm_mixmod_enable_rr_command", "1", "Enable sm_rr command? 0 - Off, 1 - On");
    g_hCvarPlayTeamSwapedSound = CreateConVar("sm_mixmod_enable_st_sound", "1", "Play sound on team swap? 0 - Off, 1 - On");
    g_hCvarCusomNameTeamCT = CreateConVar("sm_mixmod_custom_name_ct", "Team A", "Custom CT team name (max 32 chars)");
    g_hCvarCusomNameTeamT = CreateConVar("sm_mixmod_custom_name_t", "Team B", "Custom T team name (max 32 chars)");
    g_hCvarRestartTimeInLiveCommand = CreateConVar("sm_mixmod_live_restart_time", "5", "Set mp_restartgame time (seconds) for live command");
    g_hCvarUseZBMatchCommand = CreateConVar("sm_mixmod_use_zb_lo3", "0", "Use zb_lo3 command instead of mp_restartgame? 0 - Off, 1 - On");
    g_hCvarMr3Enabled = CreateConVar("sm_mixmod_mr3_enable", "1", "Enable/Disable MR3 overtime (if tied 15-15): 0 - Off, 1 - On");
    g_hCvarStopCustomCfg = CreateConVar("sm_mixmod_custom_stop_cfg", "0", "Use stop.cfg instead of prac/warmup config? 0 - Off, 1 - On");
    g_hCvarShowSwitchInPanel = CreateConVar("sm_mixmod_show_swap_in_panel", "1", "How to notify team swap at last round: 0 - Chat, 1 - Panel");
    g_hCvarShowCashInPanel = CreateConVar("sm_mixmod_show_cash_in_panel", "0", "How to show player money: 0 - Chat, 1 - Panel");
    g_hCvarHalfAutoLiveStart = CreateConVar("sm_mixmod_half_auto_live", "1", "Automatically start live at round start? 0 - Off, 1 - On");
    g_hCvarCustomPracCfg = CreateConVar("sm_mixmod_custom_prac_cfg", "prac.cfg", "Custom config file name for warmup");
    g_hCvarKickAdmins = CreateConVar("sm_mixmod_kick_admins", "0", "Kick admins with sm_kickct/sm_kickt? 0 - Off, 1 - On");
    g_hCvarDisableSayCommand = CreateConVar("sm_mixmod_disable_public_chat", "0", "Disable public chat? 0 - Off, 1 - On, 2 - Only during live");
    g_hCvarEnableKnifeRound = CreateConVar("sm_mixmod_enable_knife_round", "0", "Play knife round before match? 0 - Off, 1 - On");
    g_hCvarUseKo3Command = CreateConVar("sm_mixmod_use_zb_ko3", "0", "Use zb_ko3 instead of mp_restartgame? 0 - Off, 1 - On");
    g_hCvarInformWinnerInPanel = CreateConVar("sm_mixmod_show_winner_in", "1", "How to show winner: 0 - Chat, 1 - Panel");
    g_hCvarRpwShowPass = CreateConVar("sm_mixmod_rpw_show_pass", "1", "Show random password to all? 0 - Off (admins only), 1 - On");
    g_hCvarRemoveProps = CreateConVar("sm_mixmod_remove_props", "0", "Remove map props? 0 - Off, 1 - On");
    g_hCvarAutoMixEnabled = CreateConVar("sm_mixmod_auto_warmod_enable", "1", "Enable auto war/ready system? 0 - Off, 1 - On");
    g_hCvarEnableAutoSourceTVRecord = CreateConVar("sm_mixmod_autorecord_enable", "0", "Automatically start SourceTV record on live? 0 - Off, 1 - On");
    g_hCvarAutoSourceTVRecordSaveDir = CreateConVar("sm_mixmod_autorecord_save_dir", "mix_records", "Directory for SourceTV records");
    g_hCvarKnifeWinTeamVote = CreateConVar("sm_mixmod_knife_round_win_vote", "1", "Allow knife round winner to choose team? 0 - Off, 1 - On");
    g_hCvarEnablePasswords = CreateConVar("sm_mixmod_password_commands_enable", "0", "Enable password commands? 0 - Off, 1 - On");
    g_hCvarAllowManualSwitching = CreateConVar("sm_mixmod_manual_switch_enable", "1", "Allow manual team switching? 0 - Off, 1 - On");
    g_hCvarDelayBeforeSwapping = CreateConVar("sm_mixmod_time_before_swapping_teams", "0.1", "Seconds to wait before swapping teams");
    g_hCvarShowTkMessage = CreateConVar("sm_mixmod_show_tk_damage", "1", "Notify all players of TK damage? 0 - Off, 1 - On");
    g_hCvarRemovePassWhenMixIsEnded = CreateConVar("sm_mixmod_remove_password_on_mix_end", "1", "Remove password when match ends? 0 - Off, 1 - On");
    g_hCvarShowMVP = CreateConVar("sm_mixmod_show_mvp", "1", "Show MVP? 0 - Off, 1 - On");
    g_hCvarDontRemovePropsMaps = CreateConVar("sm_mixmod_dont_remove_props_maplist", "de_inferno,", "Maps to exclude from prop removal");
    g_hCvarEnableVoiceCommands = CreateConVar("sm_mixmod_enable_voice_commands", "1", "Enable sm_mmute/sm_mgag? 0 - Off, 1 - On");
    g_hFogDelete = CreateConVar("sm_mixmod_delete_fog", "1", "Remove map fog? 0 - Off, 1 - On");
    g_hCvarOpenAutoKick = CreateConVar("sm_mixmod_auto_kick", "0", "Auto-kick unready players when 10 players are in? 0 - Off, 1 - On");
    g_hCvarBotAutoReady = CreateConVar("sm_mixmod_bot_auto_ready", "1", "Bots auto-ready? 0 - Off, 1 - On");
    g_hCvarBotAutoReady = CreateConVar("sm_mixmod_bot_auto_ready", "1", "Bots give ready automatically? 0 - No, 1 - Yes");

    // 插件版本控制
    g_hPluginVersion = CreateConVar("sm_mixmod_version", PLUGIN_VERSION, "满十插件版本", FCVAR_SS_ADDED|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
    SetConVarString(g_hPluginVersion, PLUGIN_VERSION);

    // 监听版本改变
    HookConVarChange(g_hPluginVersion, Mix_OnVersionChanged);

    // 查找游戏偏移量和ConVars
    Mix_FindGameOffsets();
}

/**
 * 查找游戏偏移量和ConVars
 */
void Mix_FindGameOffsets()
{
    // 查找玩家金钱偏移量
    g_iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
    if (g_iAccount == -1) {
        // 这里使用硬编码的消息，因为没有对应的翻译短语
        // 可以在翻译文件中添加"Account Offset Not Found"短语
        PrintToChatAll("\x04[%s]:\x03 Cannot find m_iAccount offset! - Money info disabled!", MODNAME);
    }

    // 查找游戏重启ConVar
    g_hRestartGame = FindConVar("mp_restartgame");
    if (g_hRestartGame == INVALID_HANDLE) {
        // 这里使用硬编码的消息，因为没有对应的翻译短语
        // 可以在翻译文件中添加"Restart Game ConVar Not Found"短语
        PrintToChatAll("\x04[%s]:\x03 Cannot find mp_restartgame cvar!", MODNAME);
        SetFailState("[%s]: Cannot find mp_restartgame cvar!", MODNAME);
    }
    HookConVarChange(g_hRestartGame, Mix_OnGameRestarted);

    // 查找冻结时间ConVar
    g_hFreezeTime = FindConVar("mp_freezetime");
    if (g_hFreezeTime == INVALID_HANDLE) {
        // 这里使用硬编码的消息，因为没有对应的翻译短语
        // 可以在翻译文件中添加"Freeze Time ConVar Not Found"短语
        PrintToChatAll("\x04[%s]:\x03 Cannot find mp_freezetime cvar!", MODNAME);
        SetFailState("[%s]: Cannot find mp_freezetime cvar!", MODNAME);
    }

    // 查找服务器密码ConVar
    g_hPassword = FindConVar("sv_password");

    // 查找服务器名称ConVar
    g_hHostName = FindConVar("hostname");
    GetConVarString(g_hHostName, g_szHostName, sizeof(g_szHostName));
}

/**
 * 地图开始时调用
 */
void Mix_OnMapStart()
{
    if (g_bIsBuyZoneDisabled) {
        if (Mix_EnableBuyZone()) {
            g_bIsBuyZoneDisabled = false;
        }
    }

    // 移除雾效果
    if (GetConVarInt(g_hFogDelete) == 1) {
        int fogController = FindEntityByClassname(-1, "env_fog_controller");
        if (fogController != -1) {
            DispatchKeyValue(fogController, "fogenable", "false");
            AcceptEntityInput(fogController, "TurnOff");
        }
    }

    // 预加载声音
    PrecacheSound("ambient/misc/brass_bell_C.wav", true);

    // 重置地图投票相关变量
    if (g_bHasVoteMap == true && g_bTenVoted == true) {
        g_bHasVoteMap = false;
        Mix_ResetReadySystem();
    }

    // 重置玩家状态
    for (int i = 0; i <= MaxClients; i++) {
        g_bGaggedPlayers[i] = false;
        g_bMutedPlayers[i] = false;
    }

    // 重置插件状态
    g_bHasMixStarted = false;
    g_bDidLiveStarted = false;
    g_bIsKo3Running = false;
    g_bIsItManual = true;
    g_bIsRandomBeingUsed = false;

    // 重新查找金钱偏移量
    g_iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
    if (g_iAccount == -1) {
        // 这里使用硬编码的消息，因为没有对应的翻译短语
        // 可以在翻译文件中添加"Account Offset Not Found"短语
        PrintToChatAll("\x04[%s]:\x03 Cannot find m_iAccount offset! - Money info disabled!", MODNAME);
    }

    // 重新查找游戏重启ConVar
    g_hRestartGame = FindConVar("mp_restartgame");
    if (g_hRestartGame == INVALID_HANDLE) {
        // 这里使用硬编码的消息，因为没有对应的翻译短语
        // 可以在翻译文件中添加"Restart Game ConVar Not Found"短语
        PrintToChatAll("\x04[%s]:\x03 Cannot find mp_restartgame cvar!", MODNAME);
        SetFailState("[%s]: Cannot find mp_restartgame cvar!", MODNAME);
    }
    HookConVarChange(g_hRestartGame, Mix_OnGameRestarted);

    // 获取服务器名称
    GetConVarString(g_hHostName, g_szHostName, sizeof(g_szHostName));

    // 重置地图列表状态
    g_bIsMapListGenerated = false;
    Mix_CreateMapList();

    // 检查当前地图是否可以移除道具
    Mix_CheckPropsForCurrentMap();
}

/**
 * 地图结束时调用
 */
void Mix_OnMapEnd()
{
    Mix_StopKickUnreadyTimer();

    if (GetConVarInt(g_hCvarEnableAutoSourceTVRecord) == 1) {
        ServerCommand("tv_enable 1");
    }

    g_bIsRecording = false;
    g_bIsRecordManual = false;

    // 为防止换图后玩家数量变化，重置相关变量
    if (g_bHasVoteMap == false && g_bTenVoted == true) {
        g_bHasVoteMap = false;
        g_bTenVoted = false;
    }
}

/**
 * 当插件卸载时调用
 *
 * 此函数在插件被卸载前调用，用于清理资源和恢复游戏状态。
 */
void Mix_OnPluginEnd()
{
    // 停止任何正在进行的录制
    if (g_bIsRecording) {
        ServerCommand("tv_stoprecord");
        g_bIsRecording = false;
    }

    // 恢复购买区
    if (g_bIsBuyZoneDisabled) {
        Mix_EnableBuyZone();
    }

    // 关闭所有计时器
    if (g_hHudTimer != INVALID_HANDLE) {
        KillTimer(g_hHudTimer);
        g_hHudTimer = INVALID_HANDLE;
    }

    Mix_StopKickUnreadyTimer();

    if (g_hReadyStatus != INVALID_HANDLE) {
        CloseHandle(g_hReadyStatus);
        g_hReadyStatus = INVALID_HANDLE;
    }

    // 关闭所有菜单句柄
    if (g_hMapListMenu != INVALID_HANDLE) {
        CloseHandle(g_hMapListMenu);
        g_hMapListMenu = INVALID_HANDLE;
    }

    if (g_hMixMenu != INVALID_HANDLE) {
        CloseHandle(g_hMixMenu);
        g_hMixMenu = INVALID_HANDLE;
    }

    if (g_hHelpPanel != INVALID_HANDLE) {
        CloseHandle(g_hHelpPanel);
        g_hHelpPanel = INVALID_HANDLE;
    }

    if (g_hWinTeamPanel != INVALID_HANDLE) {
        CloseHandle(g_hWinTeamPanel);
        g_hWinTeamPanel = INVALID_HANDLE;
    }

    // 移除服务器密码（如果启用了密码功能）
    if (GetConVarInt(g_hCvarEnablePasswords) == 1) {
        ServerCommand("sv_password \"\"");
    }
}

/**
 * 当游戏帧更新时调用
 *
 * 此函数在每个游戏帧更新时调用，可用于实现需要持续检查的功能。
 * 注意：此函数会被频繁调用，应避免在此执行耗时操作。
 */
void Mix_OnGameFrame()
{
    // 目前没有需要在每帧执行的操作
    // 保留此函数以便将来可能的扩展
}

/**
 * 版本改变时的回调
 */
public void Mix_OnVersionChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    SetConVarString(convar, PLUGIN_VERSION);
}

/**
 * 检查当前地图是否可以移除道具
 */
void Mix_CheckPropsForCurrentMap()
{
    char mapName[64];
    char propMaplist[2048];
    GetCurrentMap(mapName, sizeof(mapName));
    GetConVarString(g_hCvarDontRemovePropsMaps, propMaplist, sizeof(propMaplist));

    g_bIsMapValidToRemoveProps = true;
    if (StrContains(propMaplist, mapName) != -1) {
        g_bIsMapValidToRemoveProps = false;
    }
}

/**
 * 当客户端授权时调用
 */
void Mix_OnClientAuthorized(int client)
{
    if (!IsFakeClient(client)) {
        if (g_bHasMixStarted) {
            // 通知玩家比赛正在进行
            CreateTimer(60.0, Mix_InformPlayerAboutTheMix, client);
        }
    }
}
