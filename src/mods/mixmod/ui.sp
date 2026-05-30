/**
 * UI模块
 */

#if defined _mixmod_ui_included
  #endinput
#endif
#define _mixmod_ui_included

char g_szPasswordMenuValue[MAXPLAYERS + 1][32];

/**
 * 初始化UI系统
 */
void Mix_InitUI()
{
    if (g_hHelpPanel != INVALID_HANDLE) {
        CloseHandle(g_hHelpPanel);
        g_hHelpPanel = INVALID_HANDLE;
    }

    g_hHelpPanel = CreatePanel();
    char buf[128];

    Format(buf, sizeof(buf), "%t", "Help Panel Title");
    SetPanelTitle(g_hHelpPanel, buf);
    DrawPanelItem(g_hHelpPanel, "", ITEMDRAW_SPACER);

    Format(buf, sizeof(buf), "%t", "Help Player Commands");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Score");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help MVP");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help HP");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Ready");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Not Ready");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Panel Toggle");
    DrawPanelText(g_hHelpPanel, buf);

    DrawPanelText(g_hHelpPanel, " ");

    Format(buf, sizeof(buf), "%t", "Help Admin Commands");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Mix");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Live");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Prac");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Map");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Restart Round");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Swap");
    DrawPanelText(g_hHelpPanel, buf);

    Format(buf, sizeof(buf), "%t", "Help Record");
    DrawPanelText(g_hHelpPanel, buf);

    DrawPanelItem(g_hHelpPanel, "", ITEMDRAW_SPACER);

    SetPanelCurrentKey(g_hHelpPanel, 10);

    Format(buf, sizeof(buf), "%t", "Close");
    DrawPanelItem(g_hHelpPanel, buf, ITEMDRAW_CONTROL);
}

/**
 * 显示玩家帮助面板
 *
 * @param client 目标客户端
 */
void Mix_ShowHelp(int client)
{
    if (g_hHelpPanel == INVALID_HANDLE) {
        Mix_InitUI();
    }

    SendPanelToClient(g_hHelpPanel, client, Mix_HandleDoNothing, 30);
}

/**
 * 创建主满十菜单
 *
 * @param client 目标客户端
 */
void Mix_CreateMainMixMenu(int client)
{
    if (!g_bIsMixMenuGenerated || g_hMixMenu == INVALID_HANDLE) {
        if (g_hMixMenu != INVALID_HANDLE) {
            CloseHandle(g_hMixMenu);
            g_hMixMenu = INVALID_HANDLE;
        }

        g_hMixMenu = CreateMenu(Mix_HandleMixMenu);
        char buffer[128];
        Format(buffer, sizeof(buffer), "%t", "Menu Admin Title");
        SetMenuTitle(g_hMixMenu, buffer);

        // 添加主菜单项
        Format(buffer, sizeof(buffer), "%t", "Menu Live");
        AddMenuItem(g_hMixMenu, "live", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Prac");
        AddMenuItem(g_hMixMenu, "prac", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Map");
        AddMenuItem(g_hMixMenu, "map", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Restart");
        AddMenuItem(g_hMixMenu, "restart", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Swap");
        AddMenuItem(g_hMixMenu, "swap", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Switch Admin");
        AddMenuItem(g_hMixMenu, "switchadmin", buffer);

        // 根据当前状态添加录制选项
        if (g_bIsRecording) {
            Format(buffer, sizeof(buffer), "%t", "Menu Stop Record");
            AddMenuItem(g_hMixMenu, "stoprecord", buffer);
        } else {
            Format(buffer, sizeof(buffer), "%t", "Menu Record");
            AddMenuItem(g_hMixMenu, "record", buffer);
        }

        // 添加密码相关选项
        if (GetConVarInt(g_hCvarEnablePasswords) == 1) {
            Format(buffer, sizeof(buffer), "%t", "Menu Set Password");
            AddMenuItem(g_hMixMenu, "pass", buffer);
            Format(buffer, sizeof(buffer), "%t", "Menu Remove Password");
            AddMenuItem(g_hMixMenu, "rpass", buffer);
            Format(buffer, sizeof(buffer), "%t", "Menu Random Password");
            AddMenuItem(g_hMixMenu, "rpw", buffer);
        }

        Format(buffer, sizeof(buffer), "%t", "Menu Kick CT");
        AddMenuItem(g_hMixMenu, "kickct", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Kick T");
        AddMenuItem(g_hMixMenu, "kickt", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Random Teams");
        AddMenuItem(g_hMixMenu, "random", buffer);
        Format(buffer, sizeof(buffer), "%t", "Menu Knife Round");
        AddMenuItem(g_hMixMenu, "ko3", buffer);

        g_bIsMixMenuGenerated = true;
    }

    DisplayMenu(g_hMixMenu, client, MENU_TIME_FOREVER);
}

/**
 * 处理主满十菜单选择
 */
public int Mix_HandleMixMenu(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select) {
        char option[32];
        GetMenuItem(menu, param2, option, sizeof(option));

        if (StrEqual(option, "live")) {
            Mix_StartLive(param1);
        } else if (StrEqual(option, "prac")) {
            Mix_ExecutePracConfig(param1);
        } else if (StrEqual(option, "map")) {
            // 确保地图列表已生成
            if (!g_bIsMapListGenerated) {
                Mix_CreateMapList();
            }

            // 如果地图列表菜单无效，重新创建
            if (g_hMapListMenu == INVALID_HANDLE) {
                Mix_CreateMapList(); // 这将重新创建菜单
            }

            // 显示菜单
            if (g_hMapListMenu != INVALID_HANDLE) {
                DisplayMenu(g_hMapListMenu, param1, MENU_TIME_FOREVER);
            } else {
                SetGlobalTransTarget(param1);
                PrintToChat(param1, "\x04[%s]:\x03 %t", MODNAME, "Cannot Display Map List");
            }
        } else if (StrEqual(option, "restart")) {
            Mix_RestartRound(param1);
        } else if (StrEqual(option, "swap")) {
            Mix_SwapTeams();
        } else if (StrEqual(option, "switchadmin")) {
            if (g_hAdminMenu != INVALID_HANDLE) {
                DisplayMenu(g_hAdminMenu, param1, MENU_TIME_FOREVER);
            } else {
                SetGlobalTransTarget(param1);
                PrintToChat(param1, "\x04[%s]:\x03 %t", MODNAME, "Admin Menu Unavailable");
            }
        } else if (StrEqual(option, "record")) {
            Mix_StartRecord(param1);
        } else if (StrEqual(option, "stoprecord")) {
            Mix_StopRecord(param1, 1);
        } else if (StrEqual(option, "pass")) {
            Mix_HandlePasswordCommand(param1);
        } else if (StrEqual(option, "rpass")) {
            Mix_RemovePassword(param1);
        } else if (StrEqual(option, "rpw")) {
            Mix_SetRandomPassword(param1);
        } else if (StrEqual(option, "kickct")) {
            Mix_KickTeam(param1, TEAM_CT, GetConVarInt(g_hCvarKickAdmins));
        } else if (StrEqual(option, "kickt")) {
            Mix_KickTeam(param1, TEAM_T, GetConVarInt(g_hCvarKickAdmins));
        } else if (StrEqual(option, "random")) {
            Mix_RandomizeTeams();
        } else if (StrEqual(option, "ko3")) {
            Mix_StartKnifeRound(param1);
        }

        // 在一些操作后重新生成菜单
        g_bIsMixMenuGenerated = false;
    }

    return 0;
}

/**
 * 处理密码命令
 */
void Mix_HandlePasswordCommand(int client)
{
    if (GetConVarInt(g_hCvarEnablePasswords) == 1) {
        if (!Mix_IsInGameClient(client)) {
            PrintToServer("[%s]: 此命令只能在游戏内使用", MODNAME);
            return;
        }

        g_szPasswordMenuValue[client][0] = '\0';
        Mix_ShowPasswordMenu(client);
    } else {
        if (Mix_IsInGameClient(client)) {
            SetGlobalTransTarget(client);
            PrintToChat(client, "\x04[%s]:\x03 %t", MODNAME, "Password Commands Disabled");
        } else {
            PrintToServer("[%s]: Password commands disabled", MODNAME);
        }
    }
}

/**
 * 显示密码输入菜单。
 */
void Mix_ShowPasswordMenu(int client)
{
    if (!Mix_IsInGameClient(client)) {
        return;
    }

    Handle menu = CreateMenu(Mix_HandlePasswordMenu);
    char titleBuf[128];
    if (g_szPasswordMenuValue[client][0] == '\0') {
        Format(titleBuf, sizeof(titleBuf), "%t", "Menu Enter Password");
    } else {
        Format(titleBuf, sizeof(titleBuf), "%t", "Menu Enter Password With Val", g_szPasswordMenuValue[client]);
    }
    SetMenuTitle(menu, titleBuf);

    char buffer[32];
    for (int i = 0; i < 10; i++) {
        Format(buffer, sizeof(buffer), "%d", i);
        AddMenuItem(menu, buffer, buffer);
    }

    AddMenuItem(menu, "a", "a");
    AddMenuItem(menu, "b", "b");
    AddMenuItem(menu, "c", "c");
    AddMenuItem(menu, "d", "d");
    AddMenuItem(menu, "e", "e");
    AddMenuItem(menu, "f", "f");

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/**
 * 处理密码菜单
 */
public int Mix_HandlePasswordMenu(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select) {
        if (!Mix_IsInGameClient(param1)) {
            return 0;
        }

        char item[32];
        GetMenuItem(menu, param2, item, sizeof(item));

        if (strlen(g_szPasswordMenuValue[param1]) + strlen(item) >= sizeof(g_szPasswordMenuValue[])) {
            SetGlobalTransTarget(param1);
            PrintToChat(param1, "\x04[%s]:\x03 %t", MODNAME, "Password Length Limit");
            return 0;
        }

        StrCat(g_szPasswordMenuValue[param1], sizeof(g_szPasswordMenuValue[]), item);

        char name[MAX_NAME_LENGTH];
        GetClientName(param1, name, sizeof(name));

        if (strlen(g_szPasswordMenuValue[param1]) >= 4) {
            SetConVarString(g_hPassword, g_szPasswordMenuValue[param1]);

            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Password Set By", name);
            g_szPasswordMenuValue[param1][0] = '\0';
        } else {
            Mix_ShowPasswordMenu(param1);
        }
    } else if (action == MenuAction_Cancel) {
        if (param1 >= 1 && param1 <= MaxClients) {
            g_szPasswordMenuValue[param1][0] = '\0';
        }
    } else if (action == MenuAction_End) {
        CloseHandle(menu);
    }

    return 0;
}

/**
 * 设置随机密码
 */
void Mix_SetRandomPassword(int client)
{
    if (GetConVarInt(g_hCvarEnablePasswords) == 1) {
        char password[32];
        char chars[] = "0123456789abcdef";

        for (int i = 0; i < 5; i++) {
            int randomIndex = GetRandomInt(0, strlen(chars) - 1);
            password[i] = chars[randomIndex];
        }
        password[5] = '\0';

        SetConVarString(g_hPassword, password);
        g_bIsRandomPasswordWasLastPw = true;

        if (GetConVarInt(g_hCvarRpwShowPass) == 1) {
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Password Set To", password);
        } else {
            if (client != 0) {
                char name[MAX_NAME_LENGTH];
                GetClientName(client, name, sizeof(name));

                PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Random Password Set By", name);
                SetGlobalTransTarget(client);
                PrintToChat(client, "\x04[%s]:\x03 %t", MODNAME, "Password Set To", password);
            } else {
                PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Random Password Set");
                PrintToServer("[%s]: Server password set to: %s", MODNAME, password);
            }

            for (int i = 1; i <= MaxClients; i++) {
                if (i != client && IsClientInGame(i) && !IsFakeClient(i)) {
                    if (CheckCommandAccess(i, "sm_password", ADMFLAG_KICK, false)) {
                        SetGlobalTransTarget(i);
                        PrintToChat(i, "\x04[%s]:\x03 %t", MODNAME, "Password Set To", password);
                    }
                }
            }
        }
    } else {
        if (client != 0) {
            SetGlobalTransTarget(client);
            PrintToChat(client, "\x04[%s]:\x03 %t", MODNAME, "Password Commands Disabled");
        } else {
            PrintToServer("[%s]: Password commands disabled", MODNAME);
        }
    }
}

/**
 * 移除服务器密码
 */
void Mix_RemovePassword(int client)
{
    if (GetConVarInt(g_hCvarEnablePasswords) == 1) {
        SetConVarString(g_hPassword, "");
        g_bIsRandomPasswordWasLastPw = false;

        if (client != 0) {
            char name[MAX_NAME_LENGTH];
            GetClientName(client, name, sizeof(name));

            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Password Removed By", name);
        } else {
            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Password Removed");
        }
    } else {
        if (client != 0) {
            SetGlobalTransTarget(client);
            PrintToChat(client, "\x04[%s]:\x03 %t", MODNAME, "Password Commands Disabled");
        } else {
            PrintToServer("[%s]: Password commands disabled", MODNAME);
        }
    }
}

/**
 * 启动满十(live)
 */
void Mix_StartLive(int client)
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

        // 首先执行mr12配置，确保配置正确加载
        Mix_ExecuteMr12Config();

        g_bHasMixStarted = true;
        g_bDidLiveStarted = true;
        g_bIsItManual = true;

        g_iCurrentRound = 1;
        g_iCurrentHalf = 1;
        g_iCTScore = 0;
        g_iTScore = 0;
        g_iCTScoreH1 = 0;
        g_iTScoreH1 = 0;

        if (g_bIsBuyZoneDisabled) {
            if (Mix_EnableBuyZone()) {
                g_bIsBuyZoneDisabled = false;
            }
        }

        char name[MAX_NAME_LENGTH];
        Mix_GetCommandSourceName(client, name, sizeof(name));
        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Live Started By", name);

        char teamAName[32];
        char teamBName[32];
        GetConVarString(g_hCvarCusomNameTeamCT, teamAName, sizeof(teamAName));
        GetConVarString(g_hCvarCusomNameTeamT, teamBName, sizeof(teamBName));

        char hostName[128];
        Format(hostName, sizeof(hostName), "%s | %s vs %s | Live", g_szHostName, teamAName, teamBName);
        SetConVarString(g_hHostName, hostName);

        if (GetConVarInt(g_hCvarUseZBMatchCommand) == 1) {
            ServerCommand("zb_lo3");
        } else {
            int restartTime = GetConVarInt(g_hCvarRestartTimeInLiveCommand);
            if (restartTime < 1) {
                restartTime = 1;
            }
            SetConVarInt(g_hRestartGame, restartTime);
        }

        // 录制已经在Mix_ExecuteMr12Config中启动，不需要再次启动
    }
}

/**
 * 重启当前回合
 */
void Mix_RestartRound(int client)
{
    if (GetConVarInt(g_hCvarEnabled) == 1) {
        if (GetConVarInt(g_hCvarEnableRRCommand) == 1) {
            char name[MAX_NAME_LENGTH];
            Mix_GetCommandSourceName(client, name, sizeof(name));

            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Round Restarted By", name);
            SetConVarInt(g_hRestartGame, 1);
        } else {
            SetGlobalTransTarget(client);
            PrintToChat(client, "\x04[%s]:\x03 %t", MODNAME, "Restart Round Disabled");
        }
    }
}

/**
 * 开始刀局
 */
void Mix_StartKnifeRound(int client)
{
    if (GetConVarInt(g_hCvarEnabled) == 1) {
        if (GetConVarInt(g_hCvarEnableKnifeRound) == 1) {
            g_bHasMixStarted = true;
            g_bDidLiveStarted = true;
            g_bIsKo3Running = true;

            // 刀局开始时禁用购买区
            if (!g_bIsBuyZoneDisabled) {
                if (Mix_DisableBuyZone()) {
                    g_bIsBuyZoneDisabled = true;
                }
            }

            if (GetConVarInt(g_hCvarUseKo3Command) == 1) {
                ServerCommand("zb_ko3");
            } else {
                SetConVarInt(g_hRestartGame, 3);
            }

            char name[MAX_NAME_LENGTH];
            Mix_GetCommandSourceName(client, name, sizeof(name));

            PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Knife Round Started By", name);
        } else {
            SetGlobalTransTarget(client);
            PrintToChat(client, "\x04[%s]:\x03 %t", MODNAME, "Knife Round Disabled");
        }
    }
}
