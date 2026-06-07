#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

Database g_Db;
bool g_DbReady;

public Plugin myinfo =
{
	name = "NVD RankMe Console",
	author = "OpenCode",
	description = "RankMe data viewer for console/RCON",
	version = "1.3.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_top10", Cmd_Top10, "Show top 10 players");
	RegConsoleCmd("sm_rankme", Cmd_RankMe, "Show rank info for a player");
	
	// Sintaxe clássica e 100% compatível para array 2D fixo
	char rankmeCmds[14][32] = {
		"sm_top", "sm_rank", "sm_session", "sm_statsme", "sm_next",
		"sm_topkills", "sm_topdeaths", "sm_tophs", "sm_topknife", 
		"sm_topnade", "sm_topacc", "sm_toptime", "sm_weaponme", "sm_hitbox"
	};
	
	for (int i = 0; i < sizeof(rankmeCmds); i++)
	{
		AddCommandListener(OnRankMeCommand, rankmeCmds[i]);
	}
	
	ConnectDB();
}

public Action OnRankMeCommand(int client, const char[] command, int argc)
{
	if (client != 0)
		return Plugin_Continue;
		
	if (!g_DbReady)
	{
		ReplyToCommand(client, "[NVD] Database not ready. Check server console/logs for details.");
		return Plugin_Handled;
	}
	
	char args[256];
	GetCmdArgString(args, sizeof(args));
	
	char column[32];
	bool needsName = false;
	
	if (StrEqual(command, "sm_top", false)) Format(column, sizeof(column), "score");
	else if (StrEqual(command, "sm_topkills", false)) Format(column, sizeof(column), "kills");
	else if (StrEqual(command, "sm_topdeaths", false)) Format(column, sizeof(column), "deaths");
	else if (StrEqual(command, "sm_tophs", false)) Format(column, sizeof(column), "headshots");
	else if (StrEqual(command, "sm_toptime", false)) Format(column, sizeof(column), "connected");
	else if (StrEqual(command, "sm_rank", false) || StrEqual(command, "sm_statsme", false)) 
	{
		needsName = true;
	}
	else 
	{
		ReplyToCommand(client, "[NVD] Command '%s' via RCON is not mapped yet.", command);
		return Plugin_Handled; 
	}
	
	if (needsName)
	{
		if (args[0] == '\0')
		{
			ReplyToCommand(client, "[NVD] Usage: %s <name>", command);
			return Plugin_Handled;
		}
		
		char escapedArgs[512];
		g_Db.Escape(args, escapedArgs, sizeof(escapedArgs));
		
		char query[512];
		Format(query, sizeof(query), 
			"SELECT name, score, kills, deaths, shots, hits, headshots, connected FROM rankme WHERE name LIKE '%%%s%%' ORDER BY score DESC LIMIT 5", 
			escapedArgs);
			
		g_Db.Query(SQL_RankMeCallback, query, client);
	}
	else
	{
		int limit = 10;
		if (args[0] != '\0')
		{
			int parsedLimit = StringToInt(args);
			if (parsedLimit > 0 && parsedLimit <= 50)
				limit = parsedLimit;
		}
		
		char query[256];
		Format(query, sizeof(query), 
			"SELECT name, %s FROM rankme ORDER BY %s DESC LIMIT %d", 
			column, column, limit);
			
		DataPack pack = new DataPack();
		pack.WriteString(column);
		pack.WriteCell(client);
		pack.Reset();
		
		g_Db.Query(SQL_TopCallback, query, pack);
	}
	
	return Plugin_Handled;
}

public void SQL_TopCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	pack.Reset();
	char column[32];
	pack.ReadString(column, sizeof(column));
	int client = pack.ReadCell();
	delete pack;
	
	if (results == null)
	{
		ReplyToCommand(client, "[NVD] Query failed: %s", error);
		return;
	}
	
	ReplyToCommand(client, "--- TOP by %s ---", column);
	int rank = 1;
	while (results.FetchRow())
	{
		char name[64];
		results.FetchString(0, name, sizeof(name));
		int value = results.FetchInt(1);
		ReplyToCommand(client, "#%d  %s  %s:%d", rank, name, column, value);
		rank++;
	}
	ReplyToCommand(client, "---");
}

void ConnectDB()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/sqlite/rankme.sq3");
	
	if (!FileExists(path))
	{
		LogError("[NVD_RANKME] Database file not found at: %s", path);
		LogError("[NVD_RANKME] Check if RankMe is configured to use a different database name or path.");
		return;
	}
	
	char error[255];
	Database db;
	if (SQL_CheckConfig("rankme"))
		db = SQL_Connect("rankme", true, error, sizeof(error));
	else
		db = SQL_Connect("default", true, error, sizeof(error));
	
	if (db == null)
	{
		LogError("[NVD_RANKME] Failed to connect to database: %s", error);
		return;
	}
	
	g_Db = db;
	g_Db.SetCharset("utf8");
	g_DbReady = true;
	PrintToServer("[NVD_RANKME] Successfully connected to rankme database.");
}

public Action Cmd_Top10(int client, int args)
{
	if (!g_DbReady)
	{
		ReplyToCommand(client, "[NVD] Database not ready. Check server console/logs for details.");
		return Plugin_Handled;
	}
	
	char query[256];
	Format(query, sizeof(query), "SELECT name, score, kills, deaths FROM rankme ORDER BY score DESC LIMIT 10");
	g_Db.Query(SQL_Top10Callback, query, client);
	return Plugin_Handled;
}

public void SQL_Top10Callback(Database db, DBResultSet results, const char[] error, any client)
{
	if (results == null)
	{
		ReplyToCommand(client, "[NVD] Query failed: %s", error);
		return;
	}
	
	ReplyToCommand(client, "--- TOP 10 ---");
	int rank = 1;
	while (results.FetchRow())
	{
		char name[64];
		results.FetchString(0, name, sizeof(name));
		int score = results.FetchInt(1);
		int kills = results.FetchInt(2);
		int deaths = results.FetchInt(3);
		float kdr = deaths > 0 ? float(kills) / float(deaths) : float(kills);
		ReplyToCommand(client, "#%d  %s  Score:%d  K:%d D:%d KDR:%.2f", rank, name, score, kills, deaths, kdr);
		rank++;
	}
	ReplyToCommand(client, "---");
}

public Action Cmd_RankMe(int client, int args)
{
	if (!g_DbReady)
	{
		ReplyToCommand(client, "[NVD] Database not ready. Check server console/logs for details.");
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		ReplyToCommand(client, "[NVD] Usage: !rankme <name>");
		return Plugin_Handled;
	}
	
	char search[64];
	GetCmdArgString(search, sizeof(search));
	
	char query[512];
	Format(query, sizeof(query),
		"SELECT name, score, kills, deaths, shots, hits, headshots, connected FROM rankme WHERE name LIKE '%%%s%%' ORDER BY score DESC LIMIT 5",
		search);
	
	g_Db.Query(SQL_RankMeCallback, query, client);
	return Plugin_Handled;
}

public void SQL_RankMeCallback(Database db, DBResultSet results, const char[] error, any client)
{
	if (results == null)
	{
		ReplyToCommand(client, "[NVD] Not found or error: %s", error);
		return;
	}
	
	int count;
	while (results.FetchRow())
	{
		char name[64];
		results.FetchString(0, name, sizeof(name));
		int score = results.FetchInt(1);
		int kills = results.FetchInt(2);
		int deaths = results.FetchInt(3);
		int shots = results.FetchInt(4);
		int hits = results.FetchInt(5);
		int headshots = results.FetchInt(6);
		int connected = results.FetchInt(7);
		
		float kdr = deaths > 0 ? float(kills) / float(deaths) : float(kills);
		float acc = shots > 0 ? float(hits) / float(shots) * 100.0 : 0.0;
		float hsPct = kills > 0 ? float(headshots) / float(kills) * 100.0 : 0.0;
		char timeStr[64];
		int h = connected / 3600;
		int m = (connected % 3600) / 60;
		Format(timeStr, sizeof(timeStr), "%dh %dm", h, m);
		
		ReplyToCommand(client, "[NVD] %s | Score:%d K/D:%.2f(%d/%d) Acc:%.1f%% HS:%.1f%% Time:%s",
			name, score, kdr, kills, deaths, acc, hsPct, timeStr);
		count++;
	}
	
	if (count == 0)
		ReplyToCommand(client, "[NVD] No players found matching that name");
}
