/**
 * 地图管理模块
 */

#if defined _mixmod_maps_included
  #endinput
#endif
#define _mixmod_maps_included

/**
 * 初始化地图系统
 */
void Mix_InitMaps()
{
    // 只有在插件首次加载时才重置地图列表
    // 这样可以避免在地图更改或插件重新加载时出现"Invalid Handle"错误
    g_bIsMapListGenerated = false;
    g_hMapListMenu = INVALID_HANDLE; // 只设置为无效，不关闭句柄

    // 创建地图列表
    Mix_CreateMapList();
}

/**
 * 创建地图列表
 */
void Mix_CreateMapList()
{
    if (!g_bIsMapListGenerated) {
        // 清空地图名称数组
        for (int i = 0; i < MAX_MAPS; i++) {
            g_szMapNames[i] = "";
        }

        int mapCount = 0;
        int mapSerial = -1;
        ArrayList mapList = CreateArray(ByteCountToCells(32));

        if (ReadMapList(mapList, mapSerial, "default", MAPLIST_FLAG_MAPSFOLDER | MAPLIST_FLAG_CLEARARRAY)) {
            mapCount = mapList.Length;
            for (int i = 0; i < mapCount && i < MAX_MAPS; i++) {
                mapList.GetString(i, g_szMapNames[i], 32);
            }
        } else {
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Map List Error");
            delete mapList;
            return;
        }

        delete mapList;

        if (mapCount <= 0) {
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "No Map List");
            return;
        }

        g_bIsMapListGenerated = true;

        // 创建地图列表菜单
        if (g_hMapListMenu != INVALID_HANDLE) {
            CloseHandle(g_hMapListMenu);
            g_hMapListMenu = INVALID_HANDLE;
        }

        g_hMapListMenu = CreateMenu(Mix_HandleMapListMenu);
        SetMenuTitle(g_hMapListMenu, "选择地图:");

        for (int i = 0; i < mapCount; i++) {
            AddMenuItem(g_hMapListMenu, g_szMapNames[i], g_szMapNames[i]);
        }

        SetMenuExitButton(g_hMapListMenu, true);
    }
}

/**
 * 地图列表菜单处理
 */
public int Mix_HandleMapListMenu(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select) {
        char mapName[32];
        GetMenuItem(menu, param2, mapName, sizeof(mapName));

        g_szMatchMap = mapName;

        char adminName[MAX_NAME_LENGTH];
        GetClientName(param1, adminName, sizeof(adminName));

        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                SetGlobalTransTarget(i);
                PrintToChat(i, "\x04[%s]:\x03 %t", MODNAME, "Admin Selected Map", adminName, mapName);
            }
        }

        // 延迟更换地图
        CreateTimer(3.0, Mix_ChangeMap, param1);
    } else if (action == MenuAction_End) {
        // 不要在这里关闭菜单，因为我们需要重用它
        // 只有在插件卸载或地图更改时才关闭菜单
        // 这样可以避免"Invalid Handle"错误
    }

    return 0;
}

/**
 * 更换地图定时器回调
 */
public Action Mix_ChangeMap(Handle timer, int client)
{
    if (strlen(g_szMatchMap) > 0) {
        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Changing Map", g_szMatchMap);
        ServerCommand("changelevel %s", g_szMatchMap);
    } else {
        if (Mix_IsInGameClient(client)) {
            PrintToChat(client, "\x04[%s]:\x03 %t", MODNAME, "Invalid Map Name");
        } else {
            char buf[128];
            Format(buf, sizeof(buf), "%t", "Invalid Map Name");
            PrintToServer("[%s]: %s", MODNAME, buf);
        }
    }

    return Plugin_Continue;
}

/**
 * 执行mr12配置
 */
void Mix_ExecuteMr12Config()
{
    if (GetConVarInt(g_hCvarEnabled) == 1) {
        // 重置所有玩家的战绩和统计数据
        Mix_ResetAllStats();

        // 重置MVP系统的分数
        for (int i = 1; i <= MaxClients; i++) {
            g_iScoresOfTheRound[i] = 0;
            g_iScoresOfTheGame[i] = 0;
            g_iDeathsOfTheGame[i] = 0;
        }

        // 重置记分板上的分数
        SetTeamScore(3, 0);
        SetTeamScore(2, 0);

        char customCfg[32];
        GetConVarString(g_hCvarCustomLiveCfg, customCfg, sizeof(customCfg));

        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Executing Cfg", customCfg);
        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Stats Reset");

        Mix_StartRecord(0);

        ServerCommand("exec %s", customCfg);
    }
}

/**
 * 执行练习配置
 */
void Mix_ExecutePracConfig(int client)
{
    if (GetConVarInt(g_hCvarEnabled) == 1) {
        char customCfg[32];
        if (GetConVarInt(g_hCvarStopCustomCfg) == 1) {
            customCfg = "prac.cfg";
        } else {
            GetConVarString(g_hCvarCustomPracCfg, customCfg, sizeof(customCfg));
        }
        Mix_ResetMatchState();
        if (client != 0) {
            char name[33];
            GetClientName(client, name, sizeof(name));
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Admin Executed Cfg", name, customCfg);
        } else {
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Executing Cfg", customCfg);
        }

        ServerCommand("exec %s", customCfg);
        Mix_StopRecord(client, 1);
    }
}

/**
 * 执行mr3配置
 */
void Mix_ExecuteMr3Config(int client)
{
    if (GetConVarInt(g_hCvarEnabled) == 1) {
        char customCfg[32];
        GetConVarString(g_hCvarCustomMr3Cfg, customCfg, sizeof(customCfg));

        if (client != 0) {
            char name[33];
            GetClientName(client, name, sizeof(name));
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Admin Executed Cfg", name, customCfg);
        } else {
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Executing Cfg", customCfg);
        }

        ServerCommand("exec %s", customCfg);
    }
}

/**
 * 开始录制
 */
void Mix_StartRecord(int client)
{
    if (GetConVarInt(g_hCvarEnableAutoSourceTVRecord) == 1 && !g_bIsRecording) {
        char mapName[64];
        char teamAName[32];
        char teamBName[32];
        char date[32];
        char timeStr[32];
        char folder[64];
        char filePath[512];

        GetCurrentMap(mapName, sizeof(mapName));
        GetConVarString(g_hCvarCusomNameTeamCT, teamAName, sizeof(teamAName));
        GetConVarString(g_hCvarCusomNameTeamT, teamBName, sizeof(teamBName));
        GetConVarString(g_hCvarAutoSourceTVRecordSaveDir, folder, sizeof(folder));

        FormatTime(date, sizeof(date), "%Y-%m-%d", GetTime());
        FormatTime(timeStr, sizeof(timeStr), "%H-%M", GetTime());

        Format(filePath, sizeof(filePath), "%s/auto_%s_%s_%s_%s-vs-%s", folder, date, timeStr, mapName, teamAName, teamBName);

        if (client == 0) {
            if (g_bIsItManual) {
                PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Record Started", mapName, filePath);
            }
        } else {
            char name[33];
            GetClientName(client, name, sizeof(name));
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Admin Started Recording", name);
        }

        // 先停止旧的录制，再开始新录制
        ServerCommand("tv_stoprecord");
        ServerCommand("tv_record %s", filePath);
        g_bIsRecording = true;

        if (client != 0) {
            g_bIsRecordManual = true;
        }
    }
}

/**
 * Recording stopped
 */
void Mix_StopRecord(int client, int inform)
{
    if (GetConVarInt(g_hCvarEnableAutoSourceTVRecord) == 1 && g_bIsRecording) {
        if (client == 0) {
            if (g_bIsItManual && inform != 0) {
                PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Record Stopped");
            }
        } else {
            char name[33];
            GetClientName(client, name, sizeof(name));
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Admin Stopped Recording", name);
        }

        ServerCommand("tv_stoprecord");
        g_bIsRecording = false;
        g_bIsRecordManual = false;
    }
}

/**
 * 投票更换地图
 */
void Mix_VoteMap()
{
    if (!g_bIsMapListGenerated) {
        Mix_CreateMapList();
    }

    if (!g_bIsMapListGenerated) {
        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Failed Map List");
        return;
    }

    Handle mapVoteMenu = CreateMenu(Mix_HandleMapVoteMenu);
    SetMenuTitle(mapVoteMenu, "Selecionar mapa:");

    int mapCount = 0;
    for (int i = 0; i < MAX_MAPS; i++) {
        if (strlen(g_szMapNames[i]) > 0) {
            AddMenuItem(mapVoteMenu, g_szMapNames[i], g_szMapNames[i]);
            mapCount++;
        }
    }

    if (mapCount <= 0) {
        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "No Map List");
        CloseHandle(mapVoteMenu);
        return;
    }

    SetMenuExitButton(mapVoteMenu, false);
    Mix_VoteMenuToAll(mapVoteMenu, 20, 0);

    PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Map Vote Start");
    g_bHasVoteMap = true;
}

/**
 * 地图投票菜单处理
 */
public int Mix_HandleMapVoteMenu(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End) {
        CloseHandle(menu);
    } else if (action == MenuAction_VoteEnd) {
        char mapName[32];
        GetMenuItem(menu, param1, mapName, sizeof(mapName));

        g_szMatchMap = mapName;
        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Map Vote Result", mapName);

        // 延迟更换地图
        CreateTimer(3.0, Mix_ChangeMap, 0);

        // 新增：地图投票结束后进入第二次准备
        Mix_VoteMapEndCallback();
    }

    return 0;
}

/**
 * 地图投票结束后处理
 */
void Mix_OnVoteMapEnd()
{
    Mix_ResetReadySystem();
    g_bTenVoted = true;
    PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Map Vote Over");
}

/**
 * 地图投票菜单结束后回调
 */
void Mix_VoteMapEndCallback()
{
    Mix_OnVoteMapEnd();
}
