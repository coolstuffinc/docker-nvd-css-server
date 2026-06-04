#include <sourcemod>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define QR_MAX_VERSION 12
#define QR_MAX_SIZE ((QR_MAX_VERSION * 4) + 17)
#define QR_MAX_RAW_CODEWORDS 466
#define QR_MAX_DATA_CODEWORDS 370
#define QR_MAX_ECC_CODEWORDS 30
#define QR_MAX_ALIGNMENT_POSITIONS 7
#define QR_QUIET_ZONE 2
#define QR_CONSOLE_MODULE_WIDTH 2
#define QR_PRINT_LINE_LEN (((QR_MAX_SIZE + (QR_QUIET_ZONE * 2)) * QR_CONSOLE_MODULE_WIDTH * 3) + 1)
#define QR_INPUT_BUFFER_SIZE 1024
#define QR_GF256_PRIMITIVE 0x11D
#define QR_FORMAT_POLYNOMIAL 0x537
#define QR_FORMAT_MASK 0x5412
#define QR_VERSION_POLYNOMIAL 0x1F25
#define QR_PAD_BYTE_A 0xEC
#define QR_PAD_BYTE_B 0x11
#define QR_DEFAULT_REQUIRED_FLAG "b"
#define QR_PLUGIN_VERSION "1.3.0"
#define QR_MASK 0
#define QR_ECC_LEVEL_LOW_FORMAT_BITS 1
#define QR_MODE_ALPHANUMERIC 0x2
#define QR_MODE_BYTE 0x4
#define QR_MAX_PIX_ALPHANUMERIC_CHARS 512
#define QR_MAX_BYTE_CHARS 367

// Console batch printing: bundle multiple rows per call to prevent interleaving
// Worst-case row: (QR_MAX_SIZE + QR_QUIET_ZONE*2) * QR_CONSOLE_MODULE_WIDTH * 3 bytes + newline
#define QR_MAX_ROW_BYTES (((QR_MAX_SIZE + QR_QUIET_ZONE * 2) * QR_CONSOLE_MODULE_WIDTH * 3) + 2)
// Keep each batch safely under SourceMod's internal 3072-byte format buffer
#define QR_BATCH_SIZE 2900

// HUD on-screen QR: uses two overlapping channels (white background + dark foreground)
// Limit to version 5 so each channel's string stays under ~1750 bytes (fits SM buffer)
#define QR_HUD_MAX_VERSION 5
#define QR_HUD_MAX_SIZE ((QR_HUD_MAX_VERSION * 4) + 17)                    // 37
#define QR_HUD_CONTENT_SIZE (QR_HUD_MAX_SIZE + (QR_QUIET_ZONE * 2))        // 41
// Buffer: (41 cols + newline) * 41 rows + null = 42*41+1 = 1723
#define QR_HUD_BUFFER_SIZE ((QR_HUD_CONTENT_SIZE + 1) * QR_HUD_CONTENT_SIZE + 4)
#define QR_HUD_BG_CHANNEL 2   // white fill background
#define QR_HUD_FG_CHANNEL 3   // dark module foreground (renders on top)
#define QR_HUD_HOLD_TIME  10.0

enum QRCommand
{
    QRCommand_Main = 0,
    QRCommand_Alias,
    QRCommand_HudMain,
    QRCommand_HudAlias
};

// Target options for the HUD command
enum QRHudTarget
{
    QRHudTarget_Me = 0,
    QRHudTarget_All,
    QRHudTarget_CT,
    QRHudTarget_T
};

ConVar g_CvarEnabled;
ConVar g_CvarAllowPublic;
ConVar g_CvarRequiredFlag;
ConVar g_CvarMainEnabled;
ConVar g_CvarAliasEnabled;
ConVar g_CvarHudEnabled;
ConVar g_CvarHudAliasEnabled;

int g_QrModules[QR_MAX_SIZE][QR_MAX_SIZE];
bool g_QrFunctionModules[QR_MAX_SIZE][QR_MAX_SIZE];

// Per-call HUD string buffers (global so they don't blow the plugin stack)
char g_HudQrBg[QR_HUD_BUFFER_SIZE];   // white fill: '#' for every cell
char g_HudQrFg[QR_HUD_BUFFER_SIZE];   // dark overlay: '#' for dark modules, ' ' for light

static const int QR_ECC_CODEWORDS_PER_BLOCK_LOW[QR_MAX_VERSION + 1] = {
    -1,
    7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24
};

static const int QR_NUM_ERROR_CORRECTION_BLOCKS_LOW[QR_MAX_VERSION + 1] = {
    -1,
    1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4
};

public Plugin myinfo = {
    name = "Console QR Code",
    author = "coolstuffinc",
    description = "Generates console QR codes with support for long PIX payloads",
    version = QR_PLUGIN_VERSION
};

public void OnPluginStart()
{
    CreateConVar("sm_qrcode_version", QR_PLUGIN_VERSION, "qrcode_console version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_CvarEnabled = CreateConVar("sm_qrcode_enable", "1", "Enable qrcode_console plugin command handling (1=on, 0=off)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    g_CvarAllowPublic = CreateConVar("sm_qrcode_allow_public", "1", "Allow all players to use QR commands (1=all, 0=admins only)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    g_CvarRequiredFlag = CreateConVar("sm_qrcode_required_flag", QR_DEFAULT_REQUIRED_FLAG, "Admin flag(s) required when sm_qrcode_allow_public is 0", FCVAR_PLUGIN);
    g_CvarMainEnabled = CreateConVar("sm_qrcode_cmd_qrcode", "1", "Enable sm_qrcode command (1=enabled, 0=disabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    g_CvarAliasEnabled = CreateConVar("sm_qrcode_cmd_qr", "1", "Enable sm_qr alias command (1=enabled, 0=disabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    g_CvarHudEnabled = CreateConVar("sm_qrcode_cmd_qrhud", "1", "Enable sm_qrhud command (1=enabled, 0=disabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    g_CvarHudAliasEnabled = CreateConVar("sm_qrcode_cmd_qr_hud", "1", "Enable sm_qr_hud alias command (1=enabled, 0=disabled)", FCVAR_PLUGIN, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_qrcode", Command_QRCodeMain, "sm_qrcode <text> - Print QR code in console");
    RegConsoleCmd("sm_qr", Command_QRCodeAlias, "sm_qr <text> - Alias for sm_qrcode");
    RegAdminCmd("sm_qrcode_allowcmd", Command_QRCodeAllowCmd, ADMFLAG_GENERIC, "sm_qrcode_allowcmd <sm_qrcode|sm_qr|sm_qrhud|sm_qr_hud|all>");
    RegAdminCmd("sm_qrcode_disallowcmd", Command_QRCodeDisallowCmd, ADMFLAG_GENERIC, "sm_qrcode_disallowcmd <sm_qrcode|sm_qr|sm_qrhud|sm_qr_hud|all>");
    RegAdminCmd("sm_qrcode_listcmd", Command_QRCodeListCmd, ADMFLAG_GENERIC, "Show qrcode command allow/disallow status");

    RegConsoleCmd("sm_qrhud", Command_QRHudMain, "sm_qrhud [@all|@ct|@t|@me] <text> - Show QR code on-screen (HUD)");
    RegConsoleCmd("sm_qr_hud", Command_QRHudAlias, "sm_qr_hud [@all|@ct|@t|@me] <text> - Alias for sm_qrhud");

    AutoExecConfig(true, "plugin.qrcode_console");
}

public Action Command_QRCodeMain(int client, int args)
{
    return Command_QRCode(client, args, QRCommand_Main);
}

public Action Command_QRCodeAlias(int client, int args)
{
    return Command_QRCode(client, args, QRCommand_Alias);
}

public Action Command_QRCode(int client, int args, QRCommand command)
{
    if (!IsCommandAllowed(command))
    {
        ReplyToCommand(client, "[QR] This command is currently disabled by server configuration.");
        return Plugin_Handled;
    }

    if (!CanClientUseQrCommand(client))
    {
        ReplyToCommand(client, "[QR] You do not have access to this command.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_qrcode <text>");
        return Plugin_Handled;
    }

    char text[QR_INPUT_BUFFER_SIZE];
    GetCmdArgString(text, sizeof(text));
    TrimString(text);
    StripQuotes(text);

    int textLen = strlen(text);
    if (textLen < 1)
    {
        ReplyToCommand(client, "[QR] Text cannot be empty.");
        return Plugin_Handled;
    }

    int codewords[QR_MAX_RAW_CODEWORDS];
    int version;
    int qrSize;
    bool usedAlphanumeric;

    if (!EncodeQrPayload(text, textLen, codewords, version, qrSize, usedAlphanumeric))
    {
        ReplyToCommand(client, "[QR] Payload too large (max: %d alphanumeric or %d bytes).", QR_MAX_PIX_ALPHANUMERIC_CHARS, QR_MAX_BYTE_CHARS);
        return Plugin_Handled;
    }

    BuildMatrix(codewords, version, qrSize, g_QrModules, g_QrFunctionModules);
    PrintMatrixToConsole(client, qrSize, g_QrModules);

    ReplyToCommand(client, "[QR] Printed QR code for: %s (v%d, mode=%s)", text, version, usedAlphanumeric ? "alphanumeric" : "byte");
    return Plugin_Handled;
}

public Action Command_QRCodeAllowCmd(int client, int args)
{
    return SetCommandState(client, args, true);
}

public Action Command_QRCodeDisallowCmd(int client, int args)
{
    return SetCommandState(client, args, false);
}

public Action Command_QRCodeListCmd(int client, int args)
{
    ReplyToCommand(client, "[QR] sm_qrcode=%d | sm_qr=%d | sm_qrhud=%d | sm_qr_hud=%d | plugin=%d",
        g_CvarMainEnabled.BoolValue ? 1 : 0,
        g_CvarAliasEnabled.BoolValue ? 1 : 0,
        g_CvarHudEnabled.BoolValue ? 1 : 0,
        g_CvarHudAliasEnabled.BoolValue ? 1 : 0,
        g_CvarEnabled.BoolValue ? 1 : 0);
    if (g_CvarAllowPublic.BoolValue)
    {
        ReplyToCommand(client, "[QR] Access mode: public");
    }
    else
    {
        char flags[32];
        GetRequiredFlagsString(flags, sizeof(flags));
        ReplyToCommand(client, "[QR] Access mode: admins only (flags: %s)", flags);
    }
    return Plugin_Handled;
}

public Action Command_QRHudMain(int client, int args)
{
    return Command_QRHud(client, args, QRCommand_HudMain);
}

public Action Command_QRHudAlias(int client, int args)
{
    return Command_QRHud(client, args, QRCommand_HudAlias);
}

public Action Command_QRHud(int client, int args, QRCommand command)
{
    if (!IsCommandAllowed(command))
    {
        ReplyToCommand(client, "[QR] This command is currently disabled by server configuration.");
        return Plugin_Handled;
    }

    if (!CanClientUseQrCommand(client))
    {
        ReplyToCommand(client, "[QR] You do not have access to this command.");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_qrhud [@all|@ct|@t|@me] <text>  (HUD targets require admin)");
        return Plugin_Handled;
    }

    // Parse optional target: first arg is a target if it starts with '@'
    QRHudTarget target = QRHudTarget_Me;
    int textArgStart = 1;

    if (args >= 2)
    {
        char arg1[16];
        GetCmdArg(1, arg1, sizeof(arg1));

        if (StrEqual(arg1, "@all", false))
        {
            if (!CheckCommandAccess(client, "sm_qrhud_broadcast", ADMFLAG_GENERIC, false))
            {
                ReplyToCommand(client, "[QR] You need admin access to broadcast the QR code.");
                return Plugin_Handled;
            }
            target = QRHudTarget_All;
            textArgStart = 2;
        }
        else if (StrEqual(arg1, "@ct", false))
        {
            if (!CheckCommandAccess(client, "sm_qrhud_broadcast", ADMFLAG_GENERIC, false))
            {
                ReplyToCommand(client, "[QR] You need admin access to send the QR code to a team.");
                return Plugin_Handled;
            }
            target = QRHudTarget_CT;
            textArgStart = 2;
        }
        else if (StrEqual(arg1, "@t", false))
        {
            if (!CheckCommandAccess(client, "sm_qrhud_broadcast", ADMFLAG_GENERIC, false))
            {
                ReplyToCommand(client, "[QR] You need admin access to send the QR code to a team.");
                return Plugin_Handled;
            }
            target = QRHudTarget_T;
            textArgStart = 2;
        }
        else if (StrEqual(arg1, "@me", false))
        {
            target = QRHudTarget_Me;
            textArgStart = 2;
        }
    }

    // Build text from the relevant arguments
    char text[QR_INPUT_BUFFER_SIZE];
    if (textArgStart == 1)
    {
        GetCmdArgString(text, sizeof(text));
    }
    else
    {
        text[0] = '\0';
        for (int i = textArgStart; i <= args; i++)
        {
            char arg[QR_INPUT_BUFFER_SIZE];
            GetCmdArg(i, arg, sizeof(arg));
            if (i > textArgStart)
                StrCat(text, sizeof(text), " ");
            StrCat(text, sizeof(text), arg);
        }
    }

    TrimString(text);
    StripQuotes(text);

    int textLen = strlen(text);
    if (textLen < 1)
    {
        ReplyToCommand(client, "[QR] Text cannot be empty.");
        return Plugin_Handled;
    }

    if (target != QRHudTarget_Me && client == 0)
    {
        ReplyToCommand(client, "[QR] Broadcast targets are not meaningful from server console.");
        return Plugin_Handled;
    }

    int codewords[QR_MAX_RAW_CODEWORDS];
    int version;
    int qrSize;
    bool usedAlphanumeric;

    if (!EncodeQrPayload(text, textLen, codewords, version, qrSize, usedAlphanumeric))
    {
        ReplyToCommand(client, "[QR] Payload too large (max: %d alphanumeric or %d bytes).", QR_MAX_PIX_ALPHANUMERIC_CHARS, QR_MAX_BYTE_CHARS);
        return Plugin_Handled;
    }

    if (version > QR_HUD_MAX_VERSION)
    {
        ReplyToCommand(client, "[QR] Text too long for HUD display (requires QR v%d, HUD max is v%d). Use sm_qrcode for console output.", version, QR_HUD_MAX_VERSION);
        return Plugin_Handled;
    }

    BuildMatrix(codewords, version, qrSize, g_QrModules, g_QrFunctionModules);
    BuildHudBuffers(qrSize, g_QrModules);

    int count = 0;
    if (target == QRHudTarget_All)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                ShowQRHudToClient(i);
                count++;
            }
        }
    }
    else if (target == QRHudTarget_CT)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
            {
                ShowQRHudToClient(i);
                count++;
            }
        }
    }
    else if (target == QRHudTarget_T)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_T)
            {
                ShowQRHudToClient(i);
                count++;
            }
        }
    }
    else
    {
        if (client == 0)
        {
            ReplyToCommand(client, "[QR] HUD display requires an in-game client. Use sm_qrcode for console output.");
            return Plugin_Handled;
        }
        ShowQRHudToClient(client);
        count = 1;
    }

    ReplyToCommand(client, "[QR] QR code shown on HUD for: %s (v%d, mode=%s, recipients=%d)",
        text, version, usedAlphanumeric ? "alphanumeric" : "byte", count);
    return Plugin_Handled;
}

/**
 * Builds g_HudQrBg (white fill) and g_HudQrFg (dark module overlay) for the
 * already-rendered g_QrModules matrix. Both strings use '#' as the block
 * character (1 byte, ASCII) so that font-width differences do not shift the
 * overlay relative to the background.
 *
 * Layout (per cell):
 *   g_HudQrBg : '#' for every cell  → solid white rectangle when shown in white
 *   g_HudQrFg : '#' for dark cells, ' ' for light cells → dark pattern on top
 */
void BuildHudBuffers(int qrSize, const int modules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    int quiet = QR_QUIET_ZONE;
    int bgPos = 0;
    int fgPos = 0;

    for (int y = -quiet; y < qrSize + quiet; y++)
    {
        for (int x = -quiet; x < qrSize + quiet; x++)
        {
            bool dark = (x >= 0 && x < qrSize && y >= 0 && y < qrSize && modules[y][x] == 1);

            if (bgPos + 1 < QR_HUD_BUFFER_SIZE - 1) g_HudQrBg[bgPos++] = '#';
            if (fgPos + 1 < QR_HUD_BUFFER_SIZE - 1) g_HudQrFg[fgPos++] = dark ? '#' : ' ';
        }

        if (bgPos + 1 < QR_HUD_BUFFER_SIZE - 1) g_HudQrBg[bgPos++] = '\n';
        if (fgPos + 1 < QR_HUD_BUFFER_SIZE - 1) g_HudQrFg[fgPos++] = '\n';
    }

    g_HudQrBg[bgPos] = '\0';
    g_HudQrFg[fgPos] = '\0';
}

/**
 * Sends the pre-built HUD buffers to a single in-game client using two
 * overlapping HUD channels:
 *   Channel QR_HUD_BG_CHANNEL (white)  – solid white background fill
 *   Channel QR_HUD_FG_CHANNEL (black)  – dark modules rendered on top
 *
 * The caller must invoke BuildHudBuffers() before calling this function.
 */
void ShowQRHudToClient(int client)
{
    // White background fill on channel BG
    SetHudTextParams(0.01, 0.01, QR_HUD_HOLD_TIME, 255, 255, 255, 255);
    ShowHudText(client, QR_HUD_BG_CHANNEL, "%s", g_HudQrBg);

    // Dark module overlay on channel FG (rendered on top of BG channel)
    SetHudTextParams(0.01, 0.01, QR_HUD_HOLD_TIME, 0, 0, 0, 255);
    ShowHudText(client, QR_HUD_FG_CHANNEL, "%s", g_HudQrFg);
}

bool IsCommandAllowed(QRCommand command)
{
    if (!g_CvarEnabled.BoolValue)
        return false;

    if (command == QRCommand_Main)
        return g_CvarMainEnabled.BoolValue;

    if (command == QRCommand_HudMain)
        return g_CvarHudEnabled.BoolValue;

    if (command == QRCommand_HudAlias)
        return g_CvarHudAliasEnabled.BoolValue;

    return g_CvarAliasEnabled.BoolValue;
}

bool CanClientUseQrCommand(int client)
{
    if (client == 0)
        return true;

    if (g_CvarAllowPublic.BoolValue)
        return true;

    return CheckCommandAccess(client, "sm_qrcode_access", GetRequiredFlagsBits());
}

Action SetCommandState(int client, int args, bool enabled)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: %s <sm_qrcode|sm_qr|all>", enabled ? "sm_qrcode_allowcmd" : "sm_qrcode_disallowcmd");
        return Plugin_Handled;
    }

    char target[32];
    GetCmdArg(1, target, sizeof(target));
    TrimString(target);

    bool changeMain = false;
    bool changeAlias = false;
    if (!ParseCommandTarget(target, changeMain, changeAlias))
    {
        ReplyToCommand(client, "[QR] Invalid command target: %s", target);
        return Plugin_Handled;
    }

    if (changeMain)
        g_CvarMainEnabled.SetBool(enabled);
    if (changeAlias)
        g_CvarAliasEnabled.SetBool(enabled);

    char actor[64];
    if (client > 0)
    {
        if (IsClientInGame(client))
            GetClientName(client, actor, sizeof(actor));
        else
            Format(actor, sizeof(actor), "Client#%d", client);
    }
    else
    {
        strcopy(actor, sizeof(actor), "Console");
    }

    LogAction(client, -1, "[QR] %s set command state %s => %d", actor, target, enabled ? 1 : 0);
    ReplyToCommand(client, "[QR] Updated %s to %s", target, enabled ? "enabled" : "disabled");
    return Plugin_Handled;
}

bool ParseCommandTarget(const char[] target, bool &changeMain, bool &changeAlias)
{
    if (StrEqual(target, "sm_qrcode", false) || StrEqual(target, "qrcode", false))
    {
        changeMain = true;
        return true;
    }
    if (StrEqual(target, "sm_qr", false) || StrEqual(target, "qr", false))
    {
        changeAlias = true;
        return true;
    }
    if (StrEqual(target, "all", false) || StrEqual(target, "*", false))
    {
        changeMain = true;
        changeAlias = true;
        return true;
    }
    return false;
}

void GetRequiredFlagsString(char[] buffer, int maxlen)
{
    g_CvarRequiredFlag.GetString(buffer, maxlen);
    TrimString(buffer);
    if (buffer[0] == '\0')
        strcopy(buffer, maxlen, QR_DEFAULT_REQUIRED_FLAG);
}

int GetRequiredFlagsBits()
{
    char flags[32];
    GetRequiredFlagsString(flags, sizeof(flags));

    int bits = 0;
    if (!ReadFlagString(flags, bits) || bits == 0)
        ReadFlagString(QR_DEFAULT_REQUIRED_FLAG, bits);
    if (bits == 0)
        bits = ADMFLAG_GENERIC;

    return bits;
}

bool EncodeQrPayload(const char[] text, int textLen, int codewords[QR_MAX_RAW_CODEWORDS], int &version, int &qrSize, bool &usedAlphanumeric)
{
    int mode = QR_MODE_BYTE;
    usedAlphanumeric = IsAlphanumericText(text);
    if (usedAlphanumeric)
        mode = QR_MODE_ALPHANUMERIC;

    if (usedAlphanumeric && textLen > QR_MAX_PIX_ALPHANUMERIC_CHARS)
        return false;

    if (!usedAlphanumeric && textLen > QR_MAX_BYTE_CHARS)
        return false;

    int dataCodewords = 0;
    int rawCodewords = 0;
    for (version = 1; version <= QR_MAX_VERSION; version++)
    {
        int charCountBits = NumCharCountBits(mode, version);
        if (textLen >= (1 << charCountBits))
            continue;

        int payloadBits = SegmentPayloadBits(mode, textLen);
        int totalBits = 4 + charCountBits + payloadBits;

        dataCodewords = GetNumDataCodewords(version);
        int capacityBits = dataCodewords * 8;
        if (totalBits <= capacityBits)
        {
            rawCodewords = GetNumRawDataModules(version) / 8;
            break;
        }
    }

    if (version > QR_MAX_VERSION)
        return false;

    qrSize = version * 4 + 17;

    int data[QR_MAX_DATA_CODEWORDS];
    for (int i = 0; i < dataCodewords; i++)
        data[i] = 0;

    int bitLen = 0;
    AppendBitsToBuffer(mode, 4, data, dataCodewords, bitLen);
    AppendBitsToBuffer(textLen, NumCharCountBits(mode, version), data, dataCodewords, bitLen);

    if (usedAlphanumeric)
    {
        int firstValue = -1;

        for (int i = 0; i < textLen; i++)
        {
            int val = AlphanumericValue(text[i]);

            if (firstValue < 0)
            {
                firstValue = val;
            }
            else
            {
                AppendBitsToBuffer((firstValue * 45) + val, 11, data, dataCodewords, bitLen);
                firstValue = -1;
            }
        }

        if (firstValue >= 0)
            AppendBitsToBuffer(firstValue, 6, data, dataCodewords, bitLen);
    }
    else
    {
        for (int i = 0; i < textLen; i++)
            AppendBitsToBuffer(text[i] & 0xFF, 8, data, dataCodewords, bitLen);
    }

    int dataCapacityBits = dataCodewords * 8;
    int terminatorBits = dataCapacityBits - bitLen;
    if (terminatorBits > 4)
        terminatorBits = 4;

    AppendBitsToBuffer(0, terminatorBits, data, dataCodewords, bitLen);
    AppendBitsToBuffer(0, (8 - (bitLen % 8)) % 8, data, dataCodewords, bitLen);

    int padByte = QR_PAD_BYTE_A;
    while (bitLen < dataCapacityBits)
    {
        AppendBitsToBuffer(padByte, 8, data, dataCodewords, bitLen);
        padByte = (padByte == QR_PAD_BYTE_A) ? QR_PAD_BYTE_B : QR_PAD_BYTE_A;
    }

    AddEccAndInterleave(data, dataCodewords, rawCodewords, version, codewords);
    return true;
}

bool IsAlphanumericText(const char[] text)
{
    int len = strlen(text);
    for (int i = 0; i < len; i++)
    {
        if (AlphanumericValue(text[i]) < 0)
            return false;
    }
    return true;
}

int AlphanumericValue(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'A' && c <= 'Z')
        return c - 'A' + 10;

    switch (c)
    {
        case ' ': return 36;
        case '$': return 37;
        case '%': return 38;
        case '*': return 39;
        case '+': return 40;
        case '-': return 41;
        case '.': return 42;
        case '/': return 43;
        case ':': return 44;
    }

    return -1;
}

int NumCharCountBits(int mode, int version)
{
    int group = (version <= 9) ? 0 : 1;

    if (mode == QR_MODE_ALPHANUMERIC)
    {
        static const int alphanumericBits[2] = {9, 11};
        return alphanumericBits[group];
    }

    static const int byteBits[2] = {8, 16};
    return byteBits[group];
}

int SegmentPayloadBits(int mode, int length)
{
    if (mode == QR_MODE_ALPHANUMERIC)
        return (length / 2) * 11 + (length % 2) * 6;

    return length * 8;
}

int GetNumRawDataModules(int version)
{
    int result = (16 * version + 128) * version + 64;
    if (version >= 2)
    {
        int numAlign = version / 7 + 2;
        result -= (25 * numAlign - 10) * numAlign - 55;
        if (version >= 7)
            result -= 36;
    }

    return result;
}

int GetNumDataCodewords(int version)
{
    return GetNumRawDataModules(version) / 8 - (QR_ECC_CODEWORDS_PER_BLOCK_LOW[version] * QR_NUM_ERROR_CORRECTION_BLOCKS_LOW[version]);
}

void AppendBitsToBuffer(int value, int numBits, int buffer[QR_MAX_DATA_CODEWORDS], int maxBytes, int &bitLen)
{
    for (int i = numBits - 1; i >= 0; i--)
    {
        if (bitLen >= maxBytes * 8)
            return;

        if (((value >> i) & 1) != 0)
            buffer[bitLen >> 3] |= 1 << (7 - (bitLen & 7));

        bitLen++;
    }
}

void AddEccAndInterleave(const int data[QR_MAX_DATA_CODEWORDS], int dataLen, int rawCodewords, int version, int result[QR_MAX_RAW_CODEWORDS])
{
    int numBlocks = QR_NUM_ERROR_CORRECTION_BLOCKS_LOW[version];
    int blockEccLen = QR_ECC_CODEWORDS_PER_BLOCK_LOW[version];
    int numShorterBlocks = numBlocks - (rawCodewords % numBlocks);
    int shortBlockDataLen = rawCodewords / numBlocks - blockEccLen;

    for (int i = 0; i < rawCodewords; i++)
        result[i] = 0;

    int generator[QR_MAX_ECC_CODEWORDS];
    ReedSolomonComputeDivisor(blockEccLen, generator);

    int dataOffset = 0;
    for (int i = 0; i < numBlocks; i++)
    {
        int dataBlockLen = shortBlockDataLen + (i < numShorterBlocks ? 0 : 1);
        int ecc[QR_MAX_ECC_CODEWORDS];
        ReedSolomonComputeRemainder(data, dataOffset, dataBlockLen, generator, blockEccLen, ecc);

        for (int j = 0, k = i; j < dataBlockLen; j++, k += numBlocks)
        {
            if (j == shortBlockDataLen)
                k -= numShorterBlocks;
            result[k] = data[dataOffset + j];
        }

        for (int j = 0, k = dataLen + i; j < blockEccLen; j++, k += numBlocks)
            result[k] = ecc[j];

        dataOffset += dataBlockLen;
    }
}

void ReedSolomonComputeDivisor(int degree, int result[QR_MAX_ECC_CODEWORDS])
{
    for (int i = 0; i < degree; i++)
        result[i] = 0;

    result[degree - 1] = 1;
    int root = 1;

    for (int i = 0; i < degree; i++)
    {
        for (int j = 0; j < degree; j++)
        {
            result[j] = ReedSolomonMultiply(result[j], root);
            if (j + 1 < degree)
                result[j] ^= result[j + 1];
        }
        root = ReedSolomonMultiply(root, 0x02);
    }
}

void ReedSolomonComputeRemainder(const int data[QR_MAX_DATA_CODEWORDS], int dataOffset, int dataLen, const int generator[QR_MAX_ECC_CODEWORDS], int degree, int result[QR_MAX_ECC_CODEWORDS])
{
    for (int i = 0; i < degree; i++)
        result[i] = 0;

    for (int i = 0; i < dataLen; i++)
    {
        int factor = data[dataOffset + i] ^ result[0];

        for (int j = 0; j < degree - 1; j++)
            result[j] = result[j + 1];

        result[degree - 1] = 0;
        for (int j = 0; j < degree; j++)
            result[j] ^= ReedSolomonMultiply(generator[j], factor);
    }
}

int ReedSolomonMultiply(int x, int y)
{
    int z = 0;
    for (int i = 7; i >= 0; i--)
    {
        z = ((z << 1) ^ (((z >> 7) & 1) * QR_GF256_PRIMITIVE)) & 0xFF;
        z ^= ((y >> i) & 1) * x;
    }
    return z & 0xFF;
}

void BuildMatrix(const int codewords[QR_MAX_RAW_CODEWORDS], int version, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    InitializeFunctionModules(version, qrSize, modules, functionModules);
    DrawCodewords(codewords, GetNumRawDataModules(version) / 8, qrSize, modules, functionModules);
    DrawFormatBits(QR_MASK, qrSize, modules, functionModules);
    if (version >= 7)
        DrawVersionBits(version, qrSize, modules, functionModules);
}

void InitializeFunctionModules(int version, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    for (int y = 0; y < qrSize; y++)
    {
        for (int x = 0; x < qrSize; x++)
        {
            modules[y][x] = 0;
            functionModules[y][x] = false;
        }
    }

    DrawFinderPattern(3, 3, qrSize, modules, functionModules);
    DrawFinderPattern(qrSize - 4, 3, qrSize, modules, functionModules);
    DrawFinderPattern(3, qrSize - 4, qrSize, modules, functionModules);

    for (int i = 0; i < qrSize; i++)
    {
        SetFunctionModule(6, i, (i % 2) == 0, qrSize, modules, functionModules);
        SetFunctionModule(i, 6, (i % 2) == 0, qrSize, modules, functionModules);
    }

    int alignPos[QR_MAX_ALIGNMENT_POSITIONS];
    int numAlign = GetAlignmentPatternPositions(version, alignPos);
    for (int i = 0; i < numAlign; i++)
    {
        for (int j = 0; j < numAlign; j++)
        {
            if ((i == 0 && j == 0) || (i == 0 && j == numAlign - 1) || (i == numAlign - 1 && j == 0))
                continue;
            DrawAlignmentPattern(alignPos[i], alignPos[j], qrSize, modules, functionModules);
        }
    }

    SetFunctionModule(8, qrSize - 8, true, qrSize, modules, functionModules);

    for (int i = 0; i <= 5; i++)
        SetFunctionModule(8, i, false, qrSize, modules, functionModules);
    SetFunctionModule(8, 7, false, qrSize, modules, functionModules);
    SetFunctionModule(8, 8, false, qrSize, modules, functionModules);
    SetFunctionModule(7, 8, false, qrSize, modules, functionModules);
    for (int i = 9; i < 15; i++)
        SetFunctionModule(14 - i, 8, false, qrSize, modules, functionModules);

    for (int i = 0; i < 8; i++)
        SetFunctionModule(qrSize - 1 - i, 8, false, qrSize, modules, functionModules);
    for (int i = 8; i < 15; i++)
        SetFunctionModule(8, qrSize - 15 + i, false, qrSize, modules, functionModules);

    if (version >= 7)
    {
        for (int i = 0; i < 6; i++)
        {
            for (int j = 0; j < 3; j++)
            {
                SetFunctionModule(qrSize - 11 + j, i, false, qrSize, modules, functionModules);
                SetFunctionModule(i, qrSize - 11 + j, false, qrSize, modules, functionModules);
            }
        }
    }
}

void DrawFinderPattern(int centerX, int centerY, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    for (int dy = -4; dy <= 4; dy++)
    {
        for (int dx = -4; dx <= 4; dx++)
        {
            int x = centerX + dx;
            int y = centerY + dy;
            if (x < 0 || x >= qrSize || y < 0 || y >= qrSize)
                continue;

            int dist = IntAbs(dx);
            if (IntAbs(dy) > dist)
                dist = IntAbs(dy);

            bool dark = (dist != 2 && dist != 4);
            SetFunctionModule(x, y, dark, qrSize, modules, functionModules);
        }
    }
}

void DrawAlignmentPattern(int centerX, int centerY, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    for (int dy = -2; dy <= 2; dy++)
    {
        for (int dx = -2; dx <= 2; dx++)
        {
            int dist = IntAbs(dx);
            if (IntAbs(dy) > dist)
                dist = IntAbs(dy);

            bool dark = (dist != 1);
            SetFunctionModule(centerX + dx, centerY + dy, dark, qrSize, modules, functionModules);
        }
    }
}

int GetAlignmentPatternPositions(int version, int result[QR_MAX_ALIGNMENT_POSITIONS])
{
    if (version == 1)
        return 0;

    int numAlign = version / 7 + 2;
    int step = ((version * 8 + numAlign * 3 + 5) / (numAlign * 4 - 4)) * 2;

    int pos = version * 4 + 10;
    for (int i = numAlign - 1; i >= 1; i--)
    {
        result[i] = pos;
        pos -= step;
    }

    result[0] = 6;
    return numAlign;
}

void DrawCodewords(const int codewords[QR_MAX_RAW_CODEWORDS], int rawCodewords, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    int bitIndex = 0;
    int bitLen = rawCodewords * 8;

    for (int right = qrSize - 1; right >= 1; right -= 2)
    {
        if (right == 6)
            right = 5;

        for (int vert = 0; vert < qrSize; vert++)
        {
            bool upward = ((right + 1) & 2) == 0;
            int y = upward ? (qrSize - 1 - vert) : vert;

            for (int j = 0; j < 2; j++)
            {
                int x = right - j;
                if (functionModules[y][x])
                    continue;

                int dark = 0;
                if (bitIndex < bitLen)
                    dark = (codewords[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1;

                if (IsMask0Inverted(x, y))
                    dark ^= 1;

                modules[y][x] = dark;
                bitIndex++;
            }
        }
    }
}

void DrawFormatBits(int mask, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    int data = (QR_ECC_LEVEL_LOW_FORMAT_BITS << 3) | (mask & 0x7);
    int rem = data;
    for (int i = 0; i < 10; i++)
        rem = (rem << 1) ^ ((rem >> 9) * QR_FORMAT_POLYNOMIAL);

    int bits = ((data << 10) | rem) ^ QR_FORMAT_MASK;

    for (int i = 0; i <= 5; i++)
        SetFunctionModule(8, i, GetBit(bits, i), qrSize, modules, functionModules);
    SetFunctionModule(8, 7, GetBit(bits, 6), qrSize, modules, functionModules);
    SetFunctionModule(8, 8, GetBit(bits, 7), qrSize, modules, functionModules);
    SetFunctionModule(7, 8, GetBit(bits, 8), qrSize, modules, functionModules);
    for (int i = 9; i < 15; i++)
        SetFunctionModule(14 - i, 8, GetBit(bits, i), qrSize, modules, functionModules);

    for (int i = 0; i < 8; i++)
        SetFunctionModule(qrSize - 1 - i, 8, GetBit(bits, i), qrSize, modules, functionModules);
    for (int i = 8; i < 15; i++)
        SetFunctionModule(8, qrSize - 15 + i, GetBit(bits, i), qrSize, modules, functionModules);

    SetFunctionModule(8, qrSize - 8, true, qrSize, modules, functionModules);
}

void DrawVersionBits(int version, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    int rem = version;
    for (int i = 0; i < 12; i++)
        rem = (rem << 1) ^ ((rem >> 11) * QR_VERSION_POLYNOMIAL);

    int bits = (version << 12) | rem;

    for (int i = 0; i < 6; i++)
    {
        for (int j = 0; j < 3; j++)
        {
            bool dark = (bits & 1) != 0;
            SetFunctionModule(qrSize - 11 + j, i, dark, qrSize, modules, functionModules);
            SetFunctionModule(i, qrSize - 11 + j, dark, qrSize, modules, functionModules);
            bits >>= 1;
        }
    }
}

bool GetBit(int value, int i)
{
    return ((value >> i) & 1) != 0;
}

bool IsMask0Inverted(int x, int y)
{
    return ((x + y) % 2) == 0;
}

void SetFunctionModule(int x, int y, bool dark, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE], bool functionModules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    if (x < 0 || x >= qrSize || y < 0 || y >= qrSize)
        return;

    modules[y][x] = dark ? 1 : 0;
    functionModules[y][x] = true;
}

int IntAbs(int value)
{
    return value < 0 ? -value : value;
}

void PrintMatrixToConsole(int client, int qrSize, int modules[QR_MAX_SIZE][QR_MAX_SIZE])
{
    int quiet = QR_QUIET_ZONE;
    char line[QR_PRINT_LINE_LEN];

    PrintConsoleLine(client, "");

    for (int y = -quiet; y < qrSize + quiet; y++)
    {
        int pos = 0;

        for (int x = -quiet; x < qrSize + quiet; x++)
        {
            bool dark = (x >= 0 && x < qrSize && y >= 0 && y < qrSize && modules[y][x] == 1);
            for (int i = 0; i < QR_CONSOLE_MODULE_WIDTH; i++)
            {
                if (dark)
                {
                    // U+2588 FULL BLOCK (█), UTF-8: 0xE2 0x96 0x88
                    line[pos++] = 0xE2;
                    line[pos++] = 0x96;
                    line[pos++] = 0x88;
                }
                else
                {
                    line[pos++] = ' ';
                }
            }
        }

        line[pos] = '\0';
        PrintConsoleLine(client, line);
    }

    PrintConsoleLine(client, "");
}

void PrintConsoleLine(int client, const char[] message)
{
    if (client > 0)
        PrintToConsole(client, "%s", message);
    else
        PrintToServer("%s", message);
}
