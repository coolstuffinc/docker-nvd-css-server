#include <sourcemod>
#include <cstrike>
#include "qrcode/nayuki"

#pragma semicolon 1
#pragma newdecls required

#define QR_PLUGIN_VERSION "2.0.0"
#define QR_INPUT_BUFFER_SIZE 1024

#define QR_MAX_VERSION 12
#define QR_MAX_SIZE ((QR_MAX_VERSION * 4) + 17)

// HUD
#define QR_HUD_MAX_SIZE 12
#define QR_HUD_BUFFER_SIZE 16384
#define QR_HUD_MAX_CHARS (QR_HUD_MAX_SIZE * 4 + 17)           // 65
#define QR_HUD_CONTENT_SIZE (QR_HUD_MAX_CHARS + (2 * 2))       // 69

enum QRCommand {
	QRCommand_Main,
	QRCommand_Alias,
	QRCommand_HudMain,
	QRCommand_HudAlias,
};

enum QRHudTarget {
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
ConVar g_CvarInvert;
ConVar g_CvarMinVer;
ConVar g_CvarEcl;

int g_QrModules[QR_MAX_SIZE][QR_MAX_SIZE];

char g_HudQrBg[QR_HUD_BUFFER_SIZE];
char g_HudQrFg[QR_HUD_BUFFER_SIZE];

// Console streaming (timer-based, one row per tick)
Handle g_QrStreamPack = INVALID_HANDLE;
Handle g_QrStreamTimer = INVALID_HANDLE;
int g_QrStreamClient;
bool g_QrStreamFirstRead = true;

public Plugin myinfo = {
	name = "QR Code",
	author = "coolstuffinc / Nayuki",
	description = "QR code generator using Nayuki library",
	version = QR_PLUGIN_VERSION
};

public void OnPluginStart()
{
	CreateConVar("sm_qrcode_version", QR_PLUGIN_VERSION, "qrcode version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_CvarEnabled = CreateConVar("sm_qrcode_enable", "1", "Enable plugin (1=on, 0=off)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_CvarAllowPublic = CreateConVar("sm_qrcode_allow_public", "1", "Allow all players (1=all, 0=admins)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_CvarRequiredFlag = CreateConVar("sm_qrcode_required_flag", "", "Admin flag required when allow_public=0", FCVAR_PLUGIN);
	g_CvarMainEnabled = CreateConVar("sm_qrcode_cmd_qrcode", "1", "Enable sm_qrcode", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_CvarAliasEnabled = CreateConVar("sm_qrcode_cmd_qr", "1", "Enable sm_qr", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_CvarHudEnabled = CreateConVar("sm_qrcode_cmd_qrhud", "1", "Enable sm_qrhud", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_CvarHudAliasEnabled = CreateConVar("sm_qrcode_cmd_qr_hud", "1", "Enable sm_qr_hud", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_CvarInvert = CreateConVar("sm_qr_invert_setting", "0", "Invert QR (0=normal, 1=inverted)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_CvarMinVer = CreateConVar("sm_qr_minver", "0", "Minimum QR version (0=auto, 1-12)", FCVAR_PLUGIN, true, 0.0, true, 12.0);
	g_CvarEcl = CreateConVar("sm_qr_ecl", "0", "Error correction (0=auto, 1=L, 2=M, 3=Q, 4=H)", FCVAR_PLUGIN, true, 0.0, true, 4.0);

	RegConsoleCmd("sm_qrcode", Command_QRCodeMain, "Print QR code in console");
	RegConsoleCmd("sm_qr", Command_QRCodeAlias, "Alias for sm_qrcode");
	RegConsoleCmd("sm_qr_invert", Command_QRInvert, "Toggle QR color inversion");
	RegAdminCmd("sm_qrcode_allowcmd", Command_QRCodeAllowCmd, ADMFLAG_GENERIC, "Allow/disallow commands");
	RegAdminCmd("sm_qrcode_disallowcmd", Command_QRCodeDisallowCmd, ADMFLAG_GENERIC, "Disallow commands");
	RegAdminCmd("sm_qrcode_listcmd", Command_QRCodeListCmd, ADMFLAG_GENERIC, "List command status");

	RegConsoleCmd("sm_qrhud", Command_QRHudMain, "Show QR on HUD");
	RegConsoleCmd("sm_qr_hud", Command_QRHudAlias, "Alias for sm_qrhud");

	AutoExecConfig(true, "plugin.qrcode");
}

// ---- Commands ----

public Action Command_QRInvert(int client, int args)
{
	bool cur = GetConVarBool(g_CvarInvert);
	if (args < 1) {
		SetConVarBool(g_CvarInvert, !cur);
		ReplyToCommand(client, "[QR] Invert toggled %s", !cur ? "ON" : "OFF");
	} else {
		char arg[8]; GetCmdArg(1, arg, sizeof(arg));
		int val = StringToInt(arg);
		SetConVarBool(g_CvarInvert, val != 0);
		ReplyToCommand(client, "[QR] Invert is now %s", val != 0 ? "ON" : "OFF");
	}
	return Plugin_Handled;
}

public Action Command_QRCodeMain(int client, int args) { return Command_QRCode(client, args, QRCommand_Main); }
public Action Command_QRCodeAlias(int client, int args) { return Command_QRCode(client, args, QRCommand_Alias); }
public Action Command_QRHudMain(int client, int args) { return Command_QRHud(client, args, QRCommand_HudMain); }
public Action Command_QRHudAlias(int client, int args) { return Command_QRHud(client, args, QRCommand_HudAlias); }

static bool IsCommandEnabled(QRCommand cmd) {
	switch (cmd) {
		case QRCommand_Main:     return GetConVarBool(g_CvarMainEnabled);
		case QRCommand_Alias:    return GetConVarBool(g_CvarAliasEnabled);
		case QRCommand_HudMain:  return GetConVarBool(g_CvarHudEnabled);
		case QRCommand_HudAlias: return GetConVarBool(g_CvarHudAliasEnabled);
	}
	return false;
}

static bool HasAccess(int client) {
	if (!GetConVarBool(g_CvarEnabled)) return false;
	if (!GetConVarBool(g_CvarAllowPublic)) {
		char flag[32]; GetConVarString(g_CvarRequiredFlag, flag, sizeof(flag));
		if (strlen(flag) > 0 && !CheckCommandAccess(client, "sm_qrcode_admin", ReadFlagString(flag)))
			return false;
	}
	return true;
}

public Action Command_QRCode(int client, int args, QRCommand cmd)
{
	if (!IsCommandEnabled(cmd)) { ReplyToCommand(client, "[QR] Command disabled."); return Plugin_Handled; }
	if (!HasAccess(client)) { ReplyToCommand(client, "[QR] No access."); return Plugin_Handled; }
	if (args < 1) { ReplyToCommand(client, "Usage: sm_qr <text>"); return Plugin_Handled; }

	char text[QR_INPUT_BUFFER_SIZE];
	GetCmdArgString(text, sizeof(text));
	TrimString(text);
	StripQuotes(text);

	int minVer = GetConVarInt(g_CvarMinVer);
	int eclCvar = GetConVarInt(g_CvarEcl);
	int forceEcl = (eclCvar >= 1 && eclCvar <= 4) ? eclCvar - 1 : -1;
	if (forceEcl == -1 && eclCvar != 0) {
		ReplyToCommand(client, "[QR] Invalid ECC. Use 0=auto, 1=L, 2=M, 3=Q, 4=H.");
		return Plugin_Handled;
	}

	int ver, mode, ecl;
	if (!Nayuki_QrEncodeEx(text, g_QrModules, ver, mode, ecl, minVer, forceEcl)) {
		ReplyToCommand(client, "[QR] Payload too large.");
		return Plugin_Handled;
	}

	static const char MODE_NAMES[][] = {"", "numeric", "alpha", "", "byte"};
	static const char ECL_NAMES[][] = {"L", "M", "Q", "H"};
	char status[256];
	Format(status, sizeof(status), "[QR] %s (v%d %s %s)", text, ver, MODE_NAMES[mode], ECL_NAMES[ecl]);
	int actualSize = ver * 4 + 17;
	PrintMatrixToConsole(client, actualSize, g_QrModules, status);
	return Plugin_Handled;
}

public Action Command_QRHud(int client, int args, QRCommand cmd)
{
	if (!IsCommandEnabled(cmd)) { ReplyToCommand(client, "[QR] Command disabled."); return Plugin_Handled; }
	if (!HasAccess(client)) { ReplyToCommand(client, "[QR] No access."); return Plugin_Handled; }
	if (args < 1) { ReplyToCommand(client, "Usage: sm_qrhud [@all|@ct|@t|@me] <text>"); return Plugin_Handled; }

	QRHudTarget target = QRHudTarget_Me;
	char text[QR_INPUT_BUFFER_SIZE];
	GetCmdArgString(text, sizeof(text));
	TrimString(text);
	StripQuotes(text);

	char firstArg[32];
	int argLen = BreakString(text, firstArg, sizeof(firstArg));
	if (argLen != -1) {
		if (StrEqual(firstArg, "@all", false))      { target = QRHudTarget_All;  argLen = -1; }
		else if (StrEqual(firstArg, "@ct", false))   { target = QRHudTarget_CT;   argLen = -1; }
		else if (StrEqual(firstArg, "@t", false))    { target = QRHudTarget_T;    argLen = -1; }
		else if (StrEqual(firstArg, "@me", false))   { target = QRHudTarget_Me;   argLen = -1; }
		else { argLen = -1; } // No target prefix, use full text
	}
	if (argLen > 0) {
		int skip = strlen(firstArg) + 1;
		strcopy(text, sizeof(text), text[skip]);
	}

	int ver;
	if (!Nayuki_QrEncode(text, g_QrModules, ver)) {
		ReplyToCommand(client, "[QR] Payload too large.");
		return Plugin_Handled;
	}

	// HUD only works on CSGO+ (buffer too small on CSS)
	BuildHudBuffers(ver * 4 + 17, g_QrModules);
	ShowQrOnHud(client, target);
	return Plugin_Handled;
}

// ---- Console streaming (timer-based, one row per tick) ----

void PrintMatrixToConsole(int client, int qrSize, const int modules[][QR_MAX_SIZE], const char[] status)
{
	if (g_QrStreamTimer != INVALID_HANDLE) { KillTimer(g_QrStreamTimer); g_QrStreamTimer = INVALID_HANDLE; }
	if (g_QrStreamPack != INVALID_HANDLE) { CloseHandle(g_QrStreamPack); g_QrStreamPack = INVALID_HANDLE; }

	g_QrStreamClient = client;
	g_QrStreamFirstRead = true;
	g_QrStreamPack = CreateDataPack();
	WritePackCell(g_QrStreamPack, client);

	int quiet = 2;
	int qlen = qrSize + quiet * 2;
	int termRows = (qlen + 1) / 2;
	for (int ty = 0; ty < termRows; ty++) {
		char row[QR_MAX_SIZE * 8 + 16];
		int pos = 0;

		int rowNum = ty + 1;
		char prefix[8];
		Format(prefix, sizeof(prefix), "R%02d ", rowNum);
		for (int i = 0; prefix[i] != '\0'; i++)
			row[pos++] = prefix[i];

		bool invert = GetConVarBool(g_CvarInvert);
		for (int x = -quiet; x < qrSize + quiet; x++) {
			int yTop = ty * 2 - quiet;
			int yBot = ty * 2 + 1 - quiet;
			bool topDark = (x >= 0 && x < qrSize && yTop >= 0 && yTop < qrSize && modules[yTop][x] == 1);
			bool botDark = (x >= 0 && x < qrSize && yBot >= 0 && yBot < qrSize && modules[yBot][x] == 1);
			if (invert) { topDark = !topDark; botDark = !botDark; }
			if (topDark && botDark) { row[pos++] = 0xE2; row[pos++] = 0x96; row[pos++] = 0x88; }
			else if (topDark)       { row[pos++] = 0xE2; row[pos++] = 0x96; row[pos++] = 0x80; }
			else if (botDark)       { row[pos++] = 0xE2; row[pos++] = 0x96; row[pos++] = 0x84; }
			else                    { row[pos++] = ' '; }
		}
		row[pos] = '\0';
		WritePackString(g_QrStreamPack, row);
	}

	if (strlen(status) > 0)
		WritePackString(g_QrStreamPack, status);

	ResetPack(g_QrStreamPack, false);
	g_QrStreamTimer = CreateTimer(0.0, Timer_PrintQrRow, INVALID_HANDLE, TIMER_REPEAT);
}

public Action Timer_PrintQrRow(Handle timer)
{
	if (g_QrStreamPack == INVALID_HANDLE) { g_QrStreamTimer = INVALID_HANDLE; return Plugin_Stop; }

	if (g_QrStreamFirstRead) {
		g_QrStreamClient = ReadPackCell(g_QrStreamPack);
		g_QrStreamFirstRead = false;
	}

	char row[QR_MAX_SIZE * 4 + 64];
	if (!ReadPackString(g_QrStreamPack, row, sizeof(row))) {
		CloseHandle(g_QrStreamPack); g_QrStreamPack = INVALID_HANDLE;
		g_QrStreamTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (g_QrStreamClient > 0 && IsClientInGame(g_QrStreamClient))
		PrintToConsole(g_QrStreamClient, "%s", row);

	return Plugin_Continue;
}

// ---- HUD ----

void BuildHudBuffers(int qrSize, const int modules[][QR_MAX_SIZE])
{
	int quiet = 2;

	// Initialize with all spaces
	for (int i = 0; i < sizeof(g_HudQrBg); i++) g_HudQrBg[i] = ' ';
	for (int i = 0; i < sizeof(g_HudQrFg); i++) g_HudQrFg[i] = ' ';
	g_HudQrBg[sizeof(g_HudQrBg)-1] = '\0';
	g_HudQrFg[sizeof(g_HudQrFg)-1] = '\0';

	int pos = 0;
	bool invert = GetConVarBool(g_CvarInvert);
	for (int y = -quiet; y < qrSize + quiet && pos < sizeof(g_HudQrBg) - 1; y++) {
		for (int x = -quiet; x < qrSize + quiet && pos < sizeof(g_HudQrBg) - 1; x++) {
			bool dark = (x >= 0 && x < qrSize && y >= 0 && y < qrSize && modules[y][x] == 1);
			if (invert) dark = !dark;
			g_HudQrBg[pos] = '#';
			g_HudQrFg[pos] = dark ? '#' : ' ';
			pos++;
		}
		if (pos < sizeof(g_HudQrBg) - 1) {
			g_HudQrBg[pos] = '\n';
			g_HudQrFg[pos] = '\n';
			pos++;
		}
	}
}

void ShowQrOnHud(int client, QRHudTarget target)
{
	if (GetEngineVersion() != Engine_CSGO) {
		ReplyToCommand(client, "[QR] HUD display not supported on this engine. Use !qr for console output.");
		return;
	}

	int buffers[2];
	buffers[0] = sizeof(g_HudQrBg);
	buffers[1] = sizeof(g_HudQrFg);

	int[] targets = new int[MaxClients + 1];
	int targetCount = 0;

	switch (target) {
		case QRHudTarget_Me:
			if (client > 0 && IsClientInGame(client))
				targets[targetCount++] = client;
		case QRHudTarget_All:
			for (int i = 1; i <= MaxClients; i++)
				if (IsClientInGame(i))
					targets[targetCount++] = i;
		case QRHudTarget_CT:
			for (int i = 1; i <= MaxClients; i++)
				if (IsClientInGame(i) && GetClientTeam(i) == 3)
					targets[targetCount++] = i;
		case QRHudTarget_T:
			for (int i = 1; i <= MaxClients; i++)
				if (IsClientInGame(i) && GetClientTeam(i) == 2)
					targets[targetCount++] = i;
	}

	// Send via repeated ShowHudText calls (2 channels, alternating)
	Handle timerData = CreateDataPack();
	WritePackCell(timerData, targetCount);
	for (int i = 0; i < targetCount; i++)
		WritePackCell(timerData, targets[i]);

	// Start a repeating timer for HUD refresh
	CreateTimer(0.5, Timer_RefreshHud, timerData, TIMER_REPEAT);
}

public Action Timer_RefreshHud(Handle timer, Handle data)
{
	ResetPack(data, false);
	int count = ReadPackCell(data);

	// Alternate between bg and fg each tick
	static int toggle = 0;
	toggle ^= 1;

	for (int i = 0; i < count; i++) {
		int cl = ReadPackCell(data);
		if (cl > 0 && IsClientInGame(cl)) {
			if (toggle == 0)
				ShowHudText(cl, 4, "%s", g_HudQrBg);
			else
				ShowHudText(cl, 5, "%s", g_HudQrFg);
		}
	}

	ReReadPackCell(data);
	// Keep running for 30 seconds, then stop
	static int tickCount = 0;
	tickCount++;
	if (tickCount > 60) {
		tickCount = 0;
		CloseHandle(data);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

static void ReReadPackCell(Handle pack)
{
	SetPackPosition(pack, view_as<DataPackPos>(0));
}

// ---- Admin commands ----

public Action Command_QRCodeAllowCmd(int client, int args) { return SetCommandState(client, args, true); }
public Action Command_QRCodeDisallowCmd(int client, int args) { return SetCommandState(client, args, false); }

public Action SetCommandState(int client, int args, bool allow)
{
	if (args < 1) {
		ReplyToCommand(client, "Usage: sm_qrcode_allowcmd <sm_qrcode|sm_qr|sm_qrhud|sm_qr_hud|all>");
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if (StrEqual(arg, "all", false)) {
		SetConVarBool(g_CvarMainEnabled, allow);
		SetConVarBool(g_CvarAliasEnabled, allow);
		SetConVarBool(g_CvarHudEnabled, allow);
		SetConVarBool(g_CvarHudAliasEnabled, allow);
		ReplyToCommand(client, "[QR] %s all commands.", allow ? "Allowed" : "Disallowed");
	} else if (StrEqual(arg, "sm_qrcode", false)) {
		SetConVarBool(g_CvarMainEnabled, allow);
		ReplyToCommand(client, "[QR] %s sm_qrcode.", allow ? "Allowed" : "Disallowed");
	} else if (StrEqual(arg, "sm_qr", false)) {
		SetConVarBool(g_CvarAliasEnabled, allow);
		ReplyToCommand(client, "[QR] %s sm_qr.", allow ? "Allowed" : "Disallowed");
	} else if (StrEqual(arg, "sm_qrhud", false)) {
		SetConVarBool(g_CvarHudEnabled, allow);
		ReplyToCommand(client, "[QR] %s sm_qrhud.", allow ? "Allowed" : "Disallowed");
	} else if (StrEqual(arg, "sm_qr_hud", false)) {
		SetConVarBool(g_CvarHudAliasEnabled, allow);
		ReplyToCommand(client, "[QR] %s sm_qr_hud.", allow ? "Allowed" : "Disallowed");
	} else {
		ReplyToCommand(client, "[QR] Unknown command: %s", arg);
	}
	return Plugin_Handled;
}

public Action Command_QRCodeListCmd(int client, int args)
{
	ReplyToCommand(client, "[QR] Command status:");
	ReplyToCommand(client, "  sm_qrcode: %s", GetConVarBool(g_CvarMainEnabled) ? "enabled" : "disabled");
	ReplyToCommand(client, "  sm_qr: %s", GetConVarBool(g_CvarAliasEnabled) ? "enabled" : "disabled");
	ReplyToCommand(client, "  sm_qrhud: %s", GetConVarBool(g_CvarHudEnabled) ? "enabled" : "disabled");
	ReplyToCommand(client, "  sm_qr_hud: %s", GetConVarBool(g_CvarHudAliasEnabled) ? "enabled" : "disabled");
	return Plugin_Handled;
}
