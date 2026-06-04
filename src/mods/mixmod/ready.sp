/**
 * 准备系统模块
 */

#if defined _mixmod_ready_included
  #endinput
#endif
#define _mixmod_ready_included

// 新增：准备面板显示控制变量
bool g_bReadyPanelVisible = true;

/**
 * 检查客户端是否可参与满十准备。
 *
 * 只允许真实玩家且必须在 T/CT 队，避免控制台、观察者、SourceTV/Replay
 * 或无效客户端污染 ready 计数。
 */
bool Mix_IsReadyEligibleClient(int client)
{
    if (client < 1 || client > MaxClients) {
        return false;
    }

    if (!IsClientInGame(client) || IsClientSourceTV(client) || IsClientReplay(client)) {
        return false;
    }
    
    // Ignore bots if bot auto ready is disabled
    if (IsFakeClient(client) && GetConVarInt(g_hCvarBotAutoReady) == 0) {
        return false;
    }

    int team = GetClientTeam(client);
    return (team == CS_TEAM_T || team == CS_TEAM_CT);
}

/**
 * 停止自动踢未准备玩家倒计时。
 */
void Mix_StopKickUnreadyTimer()
{
    if (g_hKickUnreadyTimer != INVALID_HANDLE) {
        KillTimer(g_hKickUnreadyTimer);
        g_hKickUnreadyTimer = INVALID_HANDLE;
    }

    g_bKickCountdownActive = false;
    g_bIsKicked = false;
    g_iSecond = 30;
}

Action Mix_CreateReadyPanel()
{
    if (!g_bReadyPanelVisible) {
        return Plugin_Continue;
    }

    char name[MAX_NAME_LENGTH];
    char readyBuf[1024], unreadyBuf[1024];
    readyBuf[0] = '\0';
    unreadyBuf[0] = '\0';
    int readyCount = 0, unreadyCount = 0;
    int rLineCount = 0, uLineCount = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsClientSourceTV(i) && !IsClientReplay(i))
        {
            if (GetClientTeam(i) == CS_TEAM_T || GetClientTeam(i) == CS_TEAM_CT) 
            {
                GetClientName(i, name, sizeof(name));
                if (g_bReadyPlayers[i]) {
                    if (rLineCount > 0)
                        StrCat(readyBuf, sizeof(readyBuf), "\n");
                    StrCat(readyBuf, sizeof(readyBuf), "  ");
                    StrCat(readyBuf, sizeof(readyBuf), name);
                    rLineCount++;
                    readyCount++;
                } else {
                    if (uLineCount > 0)
                        StrCat(unreadyBuf, sizeof(unreadyBuf), "\n");
                    StrCat(unreadyBuf, sizeof(unreadyBuf), "  ");
                    StrCat(unreadyBuf, sizeof(unreadyBuf), name);
                    uLineCount++;
                    unreadyCount++;
                }
            }
        }
    }

    int total = readyCount + unreadyCount;

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            char hintMsg[1024];
            char title[128], countLine[128], cmdLine[128], countLabel[64];

            Format(title, sizeof(title), "%t", "Ready Panel Title", MODNAME);

            Format(countLabel, sizeof(countLabel), "%t", "Ready Label");
            Format(countLine, sizeof(countLine), "%s: %d/%d", countLabel, readyCount, total);

            Format(hintMsg, sizeof(hintMsg), "%s\n%s", title, countLine);

            if (readyCount > 0) {
                char cat[64];
                Format(cat, sizeof(cat), "%t", "Ready Category Ready");
                Format(hintMsg, sizeof(hintMsg), "%s\n%s\n%s", hintMsg, cat, readyBuf);
            }
            if (unreadyCount > 0) {
                char cat[64];
                Format(cat, sizeof(cat), "%t", "Ready Category Not Ready");
                Format(hintMsg, sizeof(hintMsg), "%s\n%s\n%s", hintMsg, cat, unreadyBuf);
            }

            char c1[64], c2[64], c3[64];
            Format(c1, sizeof(c1), "%t", "Ready Cmd Ready");
            Format(c2, sizeof(c2), "%t", "Ready Cmd NotReady");
            Format(c3, sizeof(c3), "%t", "Ready Cmd Toggle");
            Format(cmdLine, sizeof(cmdLine), "%s\n%s\n%s", c1, c2, c3);
            Format(hintMsg, sizeof(hintMsg), "%s\n%s", hintMsg, cmdLine);

            SetHudTextParams(0.75, 0.2, 60.0, 200, 200, 50, 255);
            ShowHudText(i, 4, "%s", hintMsg);
        }
    }

    return Plugin_Continue;
}

// 在十人准备后隐藏准备面板
void Mix_HideReadyPanel()
{
    g_bReadyPanelVisible = false;
    if (g_hReadyStatus != INVALID_HANDLE) {
        CloseHandle(g_hReadyStatus);
        g_hReadyStatus = INVALID_HANDLE;
    }
}

// 重新显示准备面板
void Mix_ShowReadyPanel()
{
    if (!g_bReadyPanelVisible) {
        g_bReadyPanelVisible = true;
        Mix_CreateReadyPanel();
    }
}

/**
 * 重置所有玩家的准备状态
 */
void Mix_ResetReadySystem()
{
    g_bAllowReady = true;
    g_iReadyCount = 0;
    // g_bTenVoted = false; // 不要在这里重置g_bTenVoted，否则流程会出错
    for (int i = 1; i <= MaxClients; i++) {
        g_bReadyPlayers[i] = false;
        g_iReadyPlayersData[i] = -1;
    }
}

/**
 * 准备系统倒计时定时器
 * 用于在达到10名准备玩家后，倒计时踢出未准备的玩家
 */
public Action Mix_ReadyCountdownTimer(Handle timer, any data)
{
    // 检查玩家数量是否仍然满足条件
    int playerCount = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (Mix_IsReadyEligibleClient(i)) {
            playerCount++;
        }
    }
    
    // 如果玩家数量不足10人或已经有10人准备，停止计时器
    if (playerCount < 10 || g_iReadyCount >= 10) {
        PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Ready Cancelled");
        g_hKickUnreadyTimer = INVALID_HANDLE;
        g_bKickCountdownActive = false;
        g_bIsKicked = false;
        g_iSecond = 30;
        return Plugin_Stop;
    }
    
    if (g_iSecond <= 0) {
        if (!g_bIsKicked) {
            g_bIsKicked = true;
            
            int kickCount = 0;
            for (int i = 1; i <= MaxClients; i++) {
                if (Mix_IsReadyEligibleClient(i)) {
                    if (!g_bReadyPlayers[i]) {
                        KickClient(i, "[%s]: %t", MODNAME, "Kicked Not Ready");
                        kickCount++;
                    }
                }
            }
            if (kickCount > 0) {
                PrintToChatAll("\x04[%s]:\x03 %t", MODNAME, "Kicked Unready", kickCount);
            }
        }
        g_bKickCountdownActive = false;
        g_hKickUnreadyTimer = INVALID_HANDLE;
        g_bIsKicked = false;
        g_iSecond = 30;
        return Plugin_Stop;
    } else {
        char msg[128];
        Format(msg, sizeof(msg), "%t", "Unready Kick Warning", g_iSecond, "");
        PrintCenterTextAll(msg);
        g_iSecond--;
    }
    
    return Plugin_Continue;
}
