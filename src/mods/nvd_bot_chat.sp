#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <nvd_core>

#pragma semicolon 1
#pragma newdecls required

#define CHAT_COOLDOWN 12.0
#define EVENT_CHANCE 45

ConVar g_CvarEnabled;
ConVar g_CvarCooldown;
ConVar g_CvarChance;

float g_LastBotChat;
Handle g_RoundStartTimer;
int g_CurrentRound;
int g_BombPlanted;

public Plugin myinfo =
{
	name = "NVD Bot Chat",
	author = "OpenCode",
	description = "AI-powered contextual chat and roasting for bots",
	version = "2.0.0",
	url = "https://github.com/coolstuffinc/docker-nvd-css-server"
};

public void OnPluginStart()
{
	g_CvarEnabled = CreateConVar("nvd_bot_chat", "1", "Enable AI bot chat messages");
	g_CvarCooldown = CreateConVar("nvd_bot_chat_cooldown", "12.0", "Min seconds between bot messages");
	g_CvarChance = CreateConVar("nvd_bot_chat_chance", "45", "Percent chance to react to an event (0-100)");
	AutoExecConfig(true, "nvd_bot_chat");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_say", Event_PlayerSay);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("bomb_planted", Event_BombPlanted);
	HookEvent("bomb_defused", Event_BombDefused);
	HookEvent("cs_win_panel_round", Event_WinPanel);

	// Polling timer for AI responses (every 500ms)
	CreateTimer(0.5, Timer_PollResponses, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	g_LastBotChat = 0.0;
	g_CurrentRound = 0;
	g_BombPlanted = 0;
}

// ============================================================================
// CONTEXT BUILDER
// ============================================================================

// Mapa de armas para nomes mais amigaveis
void FriendlyWeaponName(const char[] weapon, char[] output, int maxlen)
{
	char base[32];
	strcopy(base, sizeof(base), weapon);
	
	bool headshot = false;
	int hsPos = StrContains(base, " HS");
	if (hsPos != -1)
	{
		base[hsPos] = '\0';
		headshot = true;
	}
	
	if (StrEqual(base, "ak47")) strcopy(output, maxlen, "AK");
	else if (StrEqual(base, "m4a1")) strcopy(output, maxlen, "M4");
	else if (StrEqual(base, "awp")) strcopy(output, maxlen, "AWP");
	else if (StrEqual(base, "deagle")) strcopy(output, maxlen, "deagle");
	else if (StrEqual(base, "glock")) strcopy(output, maxlen, "glock");
	else if (StrEqual(base, "usp")) strcopy(output, maxlen, "usp");
	else if (StrEqual(base, "p228")) strcopy(output, maxlen, "p228");
	else if (StrEqual(base, "hegrenade")) strcopy(output, maxlen, "granada");
	else if (StrEqual(base, "flashbang")) strcopy(output, maxlen, "flash");
	else if (StrEqual(base, "smokegrenade")) strcopy(output, maxlen, "smoke");
	else if (StrEqual(base, "knife")) strcopy(output, maxlen, "faca");
	else if (StrEqual(base, "scout")) strcopy(output, maxlen, "scout");
	else if (StrEqual(base, "sg552")) strcopy(output, maxlen, "SG");
	else if (StrEqual(base, "aug")) strcopy(output, maxlen, "AUG");
	else if (StrEqual(base, "m249")) strcopy(output, maxlen, "M249");
	else if (StrEqual(base, "tmp")) strcopy(output, maxlen, "TMP");
	else if (StrEqual(base, "mac10")) strcopy(output, maxlen, "MAC10");
	else if (StrEqual(base, "ump45")) strcopy(output, maxlen, "UMP");
	else if (StrEqual(base, "mp5navy")) strcopy(output, maxlen, "MP5");
	else if (StrEqual(base, "p90")) strcopy(output, maxlen, "P90");
	else if (StrEqual(base, "famas")) strcopy(output, maxlen, "famas");
	else if (StrEqual(base, "galil")) strcopy(output, maxlen, "galil");
	else if (StrEqual(base, "m3")) strcopy(output, maxlen, "doze");
	else if (StrEqual(base, "xm1014")) strcopy(output, maxlen, "doze");
	else strcopy(output, maxlen, base);
	
	if (headshot)
		Format(output, maxlen, "%s na cabeca", output);
}

// Pega o nome da area/andar do mapa onde o jogador esta
void GetPlayerLocation(int client, char[] buffer, int maxlen)
{
	if (client > 0 && IsClientInGame(client))
	{
		GetEntPropString(client, Prop_Send, "m_szLastPlaceName", buffer, maxlen);
		if (buffer[0] == '\0')
			strcopy(buffer, maxlen, "");
	}
	else
	{
		buffer[0] = '\0';
	}
}

void BuildContext(char[] buffer, int maxlen, const char[] event, 
	int mainClient = -1, int targetClient = -1, const char[] weapon = "")
{
	int ctScore = CS_GetTeamScore(CS_TEAM_CT);
	int tScore = CS_GetTeamScore(CS_TEAM_T);
	
	char timeStr[64];
	int timeLeft = RoundFloat(GetGameTime());
	int mins = timeLeft / 60;
	int secs = timeLeft % 60;
	Format(timeStr, sizeof(timeStr), "%d minuto(s) e %d segundos de jogo", mins, secs);
	
	int ctAlive = 0, tAlive = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
		if (GetClientTeam(i) == 2) tAlive++;
		else if (GetClientTeam(i) == 3) ctAlive++;
	}
	
	// Detectar clutch (1 vs N) quando o 1 for um player real
	char clutchTag[32];
	clutchTag[0] = '\0';
	
	// Encontrar player real
	int humanClient = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
		{
			humanClient = i;
			break;
		}
	}
	
	if (humanClient > 0)
	{
		int humanTeam = GetClientTeam(humanClient);
		bool humanAlive = IsPlayerAlive(humanClient);
		
		// Player real e o unico vivo do time em situacao 1vN
		if (humanAlive && ((humanTeam == CS_TEAM_T && tAlive == 1 && ctAlive >= 2) ||
			(humanTeam == CS_TEAM_CT && ctAlive == 1 && tAlive >= 2)))
		{
			strcopy(clutchTag, sizeof(clutchTag), " CLUTCH");
		}
	}
	
	char mainName[32], targetName[32];
	if (mainClient > 0 && IsClientInGame(mainClient))
	{
		GetClientName(mainClient, mainName, sizeof(mainName));
	}
	else
	{
		mainName[0] = '\0';
	}
	
	if (targetClient > 0 && IsClientInGame(targetClient))
	{
		GetClientName(targetClient, targetName, sizeof(targetName));
	}
	
	int pos = 0;
	
	// Evento (quem fez o que) vem primeiro
	if (mainName[0])
	{
		pos += Format(buffer[pos], maxlen - pos, "@%s %s", mainName, event);
		if (targetName[0] && targetClient != mainClient)
			pos += Format(buffer[pos], maxlen - pos, " @%s", targetName);
		if (weapon[0])
		{
			char friendlyWeapon[32];
			FriendlyWeaponName(weapon, friendlyWeapon, sizeof(friendlyWeapon));
			pos += Format(buffer[pos], maxlen - pos, " com \"%s\"", friendlyWeapon);
		}
		pos += Format(buffer[pos], maxlen - pos, ". ");
	}
	else if (event[0])
	{
		// Sem jogador especifico: "O CT venceu o round."
		pos += Format(buffer[pos], maxlen - pos, "%s ", event);
	}
	
	// Depois o estado da partida
	char mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));
	
	pos += Format(buffer[pos], maxlen - pos, 
		"Mapa %s, Round %d, o placar agora e %d a %d, %s, %d TR vivo(s) contra %d CT vivo(s)", 
		mapName, g_CurrentRound, tScore, ctScore, timeStr, tAlive, ctAlive);
	
	if (g_BombPlanted > 0)
		pos += Format(buffer[pos], maxlen - pos, ", bomba plantada");
	
	pos += Format(buffer[pos], maxlen - pos, "%s.", clutchTag);
}

// ============================================================================
// EVENTS
// ============================================================================
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_CurrentRound++;
	g_BombPlanted = 0;
	delete g_RoundStartTimer;
	g_RoundStartTimer = CreateTimer(3.0, Timer_RoundStartMsg, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundStartMsg(Handle timer)
{
	g_RoundStartTimer = null;
	if (!CanBotChat()) return Plugin_Stop;
	
	// Round events: 20% chance (menos interessante)
	if (GetRandomInt(1, 100) > 20) return Plugin_Stop;
	
	char ctx[512];
	if (g_CurrentRound > 1)
		BuildContext(ctx, sizeof(ctx), "O round iniciou.");
	else
		BuildContext(ctx, sizeof(ctx), "A partida iniciou!");
	AskBotChat(ctx);
	return Plugin_Stop;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	delete g_RoundStartTimer;
	
	int winner = event.GetInt("winner");
	
	if (!CanBotChat()) return;
	
	// Round events: 20% chance
	if (GetRandomInt(1, 100) > 20) return;
	
	char ctx[512];
	if (winner == 2)
		BuildContext(ctx, sizeof(ctx), "O TR venceu o round.");
	else if (winner == 3)  
		BuildContext(ctx, sizeof(ctx), "O CT venceu o round.");
	else
		return;
	AskBotChat(ctx);
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
	g_BombPlanted = GetGameTime();
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat())
	{
		// Bomb events: 50% chance
		if (GetRandomInt(1, 100) > 50) return;
		
		char ctx[512];
		BuildContext(ctx, sizeof(ctx), "plantou a bomba!", client);
		char loc[64];
		GetPlayerLocation(client, loc, sizeof(loc));
		if (loc[0])
		{
			char tmp[640];
			Format(tmp, sizeof(tmp), "%s Local: %s.", ctx, loc);
			strcopy(ctx, sizeof(ctx), tmp);
		}
		AskBotChat(ctx, client);
	}
}

public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
	g_BombPlanted = 0;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsFakeClient(client) && CanBotChat())
	{
		// Bomb events: 50% chance
		if (GetRandomInt(1, 100) > 50) return;
		
		char ctx[512];
		BuildContext(ctx, sizeof(ctx), "desarmou a bomba!", client);
		char loc[64];
		GetPlayerLocation(client, loc, sizeof(loc));
		if (loc[0])
		{
			char tmp[640];
			Format(tmp, sizeof(tmp), "%s Local: %s.", ctx, loc);
			strcopy(ctx, sizeof(ctx), tmp);
		}
		AskBotChat(ctx, client);
	}
}

public void Event_WinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat() || GetRandomInt(1, 100) > 40) return;
	
	char funfact[128];
	event.GetString("funfact_token", funfact, sizeof(funfact));
	if (funfact[0] == '\0') return;
	
	int player = event.GetInt("funfact_player");
	int data1 = event.GetInt("funfact_data1");
	
	char playerName[32];
	if (player > 0 && IsClientInGame(player))
		GetClientName(player, playerName, sizeof(playerName));
	else
		strcopy(playerName, sizeof(playerName), "alguem");
	
	char ctx[512];
	if (StrContains(funfact, "SpentMostMoney") != -1)
		Format(ctx, sizeof(ctx), "@%s gastou $%d neste round", playerName, data1);
	else if (StrContains(funfact, "MostKills") != -1)
		Format(ctx, sizeof(ctx), "@%s fez mais kills: %d", playerName, data1);
	else if (StrContains(funfact, "MostDamage") != -1)
		Format(ctx, sizeof(ctx), "@%s deu mais dano: %d", playerName, data1);
	else if (StrContains(funfact, "Clutch") != -1)
		Format(ctx, sizeof(ctx), "@%s clutchou: %d kills", playerName, data1);
	else if (StrContains(funfact, "knife") != -1)
		Format(ctx, sizeof(ctx), "@%s matou alguem com a faca", playerName);
	else if (StrContains(funfact, "no_scope") != -1)
		Format(ctx, sizeof(ctx), "@%s matou sem mirar (no scope)", playerName);
	else if (StrContains(funfact, "one_shot") != -1)
		Format(ctx, sizeof(ctx), "@%s matou com um tiro so", playerName);
	else if (StrContains(funfact, "grenade") != -1 || StrContains(funfact, "he") != -1)
		Format(ctx, sizeof(ctx), "@%s matou com granada", playerName);
	else
		Format(ctx, sizeof(ctx), "@%s: %s (%d)", playerName, funfact, data1);
	
	int preferred = IsFakeClient(player) ? player : -1;
	AskBotChat(ctx, preferred);
}

public void Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat() || GetRandomInt(1, 100) > 15) return;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || IsFakeClient(client) || IsClientSourceTV(client)) return;
	
	char text[128];
	event.GetString("text", text, sizeof(text));
	if (text[0] == '!' || text[0] == '/') return; // Comandos
	
	char mainName[32];
	GetClientName(client, mainName, sizeof(mainName));
	
	char ctx[640];
	Format(ctx, sizeof(ctx), "@%s falou no chat: \"%s\"", mainName, text);
	AskBotChat(ctx);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat() || GetRandomInt(1, 100) > 25) return;
	
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	// SÃ³ friendly fire: mesmo time
	if (attacker < 1 || victim < 1) return;
	if (GetClientTeam(attacker) != GetClientTeam(victim)) return;
	if (attacker == victim) return;
	
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));
	
	// Prioriza bot que sofreu FF
	int preferred;
	char ctx[512];
	if (IsFakeClient(victim))
	{
		// Bot tomou friendly fire → prefer bot que tomou
		preferred = victim;
		BuildContext(ctx, sizeof(ctx), "tomou friendly fire de", victim, attacker, weapon);
	}
	else if (IsFakeClient(attacker))
	{
		// Bot deu friendly fire → prefer bot que deu
		preferred = attacker;
		BuildContext(ctx, sizeof(ctx), "deu friendly fire em", attacker, victim, weapon);
	}
	else
		return;
	
	AskBotChat(ctx, preferred);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!CanBotChat()) return;

	int killer = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int headshot = event.GetInt("headshot");
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));

	if (headshot)
		Format(weapon, sizeof(weapon), "%s HS", weapon);

	if (killer < 1 || (!IsFakeClient(killer) && !IsFakeClient(victim)))
		return;

	// Peso varia conforme o envolvimento de player real
	int chance;
	if (IsFakeClient(killer) && !IsFakeClient(victim))
		chance = 70; // Bot matou player: MUITO interessante
	else if (!IsFakeClient(killer) && IsFakeClient(victim))
		chance = 60; // Player matou bot: interessante
	else
		chance = 30; // Bot matou bot: menos interessante
	
	if (GetRandomInt(1, 100) > chance) return;

	int dominated = event.GetInt("dominated");
	int revenge = event.GetInt("revenge");

	char ctx[512];
	if (revenge)
		BuildContext(ctx, sizeof(ctx), "se vingou de", killer, victim, weapon);
	else if (dominated)
		BuildContext(ctx, sizeof(ctx), "domina", killer, victim, weapon);
	else if (IsFakeClient(killer) && !IsFakeClient(victim))
		BuildContext(ctx, sizeof(ctx), "eliminou", killer, victim, weapon);
	else if (IsFakeClient(victim) && !IsFakeClient(killer))
		BuildContext(ctx, sizeof(ctx), "morreu para", victim, killer, weapon);
	else if (IsFakeClient(killer) && IsFakeClient(victim))
		BuildContext(ctx, sizeof(ctx), "eliminou", killer, victim, weapon);
	else
		return;

	// Adiciona localizacao do assassino
	char location[64];
	GetPlayerLocation(killer, location, sizeof(location));
	if (location[0] != '\0')
	{
		char withLoc[640];
		Format(withLoc, sizeof(withLoc), "%s Local: %s.", ctx, location);
		strcopy(ctx, sizeof(ctx), withLoc);
	}

	AskBotChat(ctx, IsFakeClient(killer) ? killer : victim);
}

// ============================================================================
// AI INTEGRATION
// ============================================================================
bool CanBotChat()
{
	if (!g_CvarEnabled.BoolValue) return false;
	float delay = g_CvarCooldown.FloatValue;
	if (GetGameTime() - g_LastBotChat < delay) return false;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
			return true;
	return false;
}

void AskBotChat(const char[] context, int preferredClient = -1)
{
    if (!g_CvarEnabled.BoolValue) return;

    int botClient;
    
    // Se tem preferredClient e e um bot valido, usa ele
    if (preferredClient >= 1 && preferredClient <= MaxClients &&
        IsClientInGame(preferredClient) && IsFakeClient(preferredClient))
    {
        botClient = preferredClient;
    }
    else
    {
        int botClients[MAXPLAYERS + 1];
        int botCount = 0;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
                botClients[botCount++] = i;
        }
        if (botCount == 0) return;
        botClient = botClients[GetRandomInt(0, botCount - 1)];
    }
    char botName[32];
    GetClientName(botClient, botName, sizeof(botName));

    char botTeamName[32];
    int team = GetClientTeam(botClient);
    if (team == CS_TEAM_T)
        strcopy(botTeamName, sizeof(botTeamName), "Time TR");
    else if (team == CS_TEAM_CT)
        strcopy(botTeamName, sizeof(botTeamName), "Time CT");
    else
        strcopy(botTeamName, sizeof(botTeamName), "Time ?");

    // Prompt natural: quem é + contexto
    char localContext[768];
    strcopy(localContext, sizeof(localContext), context);
    
    // Time do bot: ganhando ou perdendo?
    int tScore = CS_GetTeamScore(CS_TEAM_T);
    int ctScore = CS_GetTeamScore(CS_TEAM_CT);
    char scoreStatus[64];
    if (team == CS_TEAM_T && tScore > ctScore)
        strcopy(scoreStatus, sizeof(scoreStatus), " Voce esta ganhando.");
    else if (team == CS_TEAM_T && tScore < ctScore)
        strcopy(scoreStatus, sizeof(scoreStatus), " Voce esta perdendo.");
    else if (team == CS_TEAM_CT && ctScore > tScore)
        strcopy(scoreStatus, sizeof(scoreStatus), " Voce esta ganhando.");
    else if (team == CS_TEAM_CT && ctScore < tScore)
        strcopy(scoreStatus, sizeof(scoreStatus), " Voce esta perdendo.");
    else
        strcopy(scoreStatus, sizeof(scoreStatus), "");
    
    // Mood baseado no evento
    char mood[128];
    
    // Extrai @alvo do contexto (pula o nome do proprio bot)
    char targetMention[64];
    targetMention[0] = '\0';
    
    int searchPos = 0;
    while (searchPos < strlen(localContext))
    {
        int atPos = StrContains(localContext[searchPos], "@");
        if (atPos == -1) break;
        
        atPos += searchPos;
        int endPos = atPos + 1;
        while (endPos < strlen(localContext) && localContext[endPos] != ' ' && localContext[endPos] != '.' && localContext[endPos] != ',')
            endPos++;
        
        if (endPos > atPos + 1)
        {
            char mention[64];
            strcopy(mention, sizeof(mention), localContext[atPos]);
            // Trunca
            int sp = StrContains(mention, " ");
            if (sp != -1) mention[sp] = '\0';
            int dt = StrContains(mention, ".");
            if (dt != -1) mention[dt] = '\0';
            
            // Se nao e o proprio bot, usa
            if (StrContains(mention, botName) == -1)
            {
                strcopy(targetMention, sizeof(targetMention), mention);
                break;
            }
        }
        
        searchPos = endPos;
    }
    
    if (StrContains(localContext, "friendly fire") != -1)
    {
        if (StrContains(localContext, "deu friendly fire") != -1)
            strcopy(mood, sizeof(mood), "Foi mal, foi sem querer");
        else
            strcopy(mood, sizeof(mood), "Reclama do colega de time");
    }
    else if (StrContains(localContext, "eliminou") != -1)
    {
        if (targetMention[0])
            Format(mood, sizeof(mood), "Zoe %s", targetMention);
        else
            strcopy(mood, sizeof(mood), "Zoe o inimigo");
    }
    else if (StrContains(localContext, "morreu") != -1)
    {
        if (targetMention[0])
            Format(mood, sizeof(mood), "Brigue de brincadeira com %s", targetMention);
        else
            strcopy(mood, sizeof(mood), "Brigue de brincadeira");
    }
    else if (StrContains(localContext, "venceu") != -1)
    {
        if ((StrContains(localContext, "TR venceu") != -1 && StrContains(botTeamName, "TR") != -1) ||
            (StrContains(localContext, "CT venceu") != -1 && StrContains(botTeamName, "CT") != -1))
            strcopy(mood, sizeof(mood), "Comemore");
        else
            strcopy(mood, sizeof(mood), "Reclame da derrota");
    }
    else
        strcopy(mood, sizeof(mood), "Reaja");
    
    // Remove estado do jogo do user prompt (ja esta no system prompt)
    char eventOnly[768];
    strcopy(eventOnly, sizeof(eventOnly), localContext);
    int mapaPos = StrContains(eventOnly, ". Mapa");
    if (mapaPos != -1)
        eventOnly[mapaPos] = '\0';
    
    char fullPrompt[1024];
    if (eventOnly[0])
        Format(fullPrompt, sizeof(fullPrompt),
            "%s%s Mood: %s.", eventOnly, scoreStatus, mood);
    else
        Format(fullPrompt, sizeof(fullPrompt),
            "%s%s Mood: %s.", localContext, scoreStatus, mood);
    
    // System: inclui estado da partida
    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));
    
    char gameState[64];
    if (scoreStatus[0] != '\0')
        strcopy(gameState, sizeof(gameState), scoreStatus[1]); // Pula espaco inicial
    else
        gameState[0] = '\0';
    
    char sysPrompt[640];
    Format(sysPrompt, sizeof(sysPrompt),
        "You are %s (%s) in CS:Source. Mapa %s. Round %d, placar %d a %d. %s React with ONE short sentence. ALWAYS use @Nome for OTHERS. Never yourself. PORTUGUESE only.",
        botName, botTeamName, mapName, g_CurrentRound, tScore, ctScore, gameState);

    char timeBuf[32];
    FormatTime(timeBuf, sizeof(timeBuf), "%H:%M:%S");

    NVD_AskAI(fullPrompt, sysPrompt, OnPollingDummy, botClient);
    PrintToServer("[BOT_CHAT] [%s] 🤖 Asked bot %s (%s): %s", timeBuf, botName, botTeamName, context);
    PrintToServer("[BOT_CHAT] [%s] 📝 Prompt >> system: \"%s\" | user: \"%s\"", timeBuf, sysPrompt, fullPrompt);
}

// No-op callback — responses come through NVD_PollResponse polling
public void OnPollingDummy(const char[] response, any data)
{
}

// ── Polling timer ─────────────────────────────────────────────────────
public Action Timer_PollResponses(Handle timer)
{
    PollBotResponses();
    return Plugin_Continue;
}

void PollBotResponses()
{
    char reply[2048];
    any botClient;
    char ts[32];
    FormatTime(ts, sizeof(ts), "%H:%M:%S");

    while (NVD_PollResponse(reply, sizeof(reply), botClient))
    {
        PrintToServer("[BOT_CHAT] [%s] 📥 Polled response for bot %d: \"%s\"", ts, botClient, reply);

        // Check for explicit error responses
        if (StrContains(reply, "ERROR_") != -1)
        {
            LogError("[BOT_CHAT] ❌ Ollama error received: %s", reply);
            continue;
        }

        if (reply[0] == '\0') continue;
        if (!g_CvarEnabled.BoolValue) continue;

        char botName[32];

        // If the original bot is invalid (morto ainda pode falar), find another
        if (botClient == 0 || !IsClientInGame(botClient) || !IsFakeClient(botClient))
        {
            int activeBots[MAXPLAYERS + 1];
            int activeBotCount = 0;
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
                {
                    activeBots[activeBotCount++] = i;
                }
            }

            if (activeBotCount == 0)
            {
                PrintToServer("[BOT_CHAT] ⏭ Dropped (no active bots): \"%s\"", reply);
                continue;
            }

            char oldName[32];
            if (botClient > 0 && IsClientInGame(botClient))
                GetClientName(botClient, oldName, sizeof(oldName));
            else
                strcopy(oldName, sizeof(oldName), "desconhecido");

            botClient = activeBots[GetRandomInt(0, activeBotCount - 1)];
            char newName[32];
            GetClientName(botClient, newName, sizeof(newName));
            PrintToServer("[BOT_CHAT] 🔄 Resposta de %s redirecionada para %s (original invalido)", oldName, newName);
        }

        GetClientName(botClient, botName, sizeof(botName));

        char cleanMsg[320];
        strcopy(cleanMsg, sizeof(cleanMsg), reply);
        ReplaceString(cleanMsg, sizeof(cleanMsg), "\"", "");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "[", "");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "]", "");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "\\n", " ");
        ReplaceString(cleanMsg, sizeof(cleanMsg), "\\r", " ");
        TrimString(cleanMsg);

        // Remove bot name prefix if model repeated it (e.g. "TACO: mensagem" or "TACO mensagem")
        char namePattern[64];
        Format(namePattern, sizeof(namePattern), "%s", botName);
        if (StrContains(cleanMsg, namePattern) == 0)
        {
            int nameLen = strlen(namePattern);
            int rest = strlen(cleanMsg) - nameLen;
            if (rest > 0)
            {
                char tmp[256];
                int start = nameLen;
                // Skip colon and space after name
                while (start < strlen(cleanMsg) && (cleanMsg[start] == ':' || cleanMsg[start] == ' '))
                    start++;
                strcopy(tmp, sizeof(tmp), cleanMsg[start]);
                strcopy(cleanMsg, sizeof(cleanMsg), tmp);
                TrimString(cleanMsg);
            }
        }

        // Remove leftover "chat:" prefix
        if (StrContains(cleanMsg, "chat:") == 0 || StrContains(cleanMsg, "chat :") == 0)
        {
            int pos = StrContains(cleanMsg, ":");
            if (pos >= 0)
            {
                char tmp[256];
                strcopy(tmp, sizeof(tmp), cleanMsg[pos + 1]);
                strcopy(cleanMsg, sizeof(cleanMsg), tmp);
                TrimString(cleanMsg);
            }
        }

        if (cleanMsg[0] == '\0')
        {
            PrintToServer("[BOT_CHAT] ⏭ Dropped (empty after clean): \"%s\"", reply);
            continue;
        }

        PrintToServer("[BOT_CHAT] [%s] ✅ Sent: [BOT %s] %s", ts, botName, cleanMsg);

        // Bot-to-bot reply: 15% chance de outro bot responder
        if (GetRandomInt(1, 100) <= 15)
        {
            int otherBots[MAXPLAYERS + 1];
            int otherCount = 0;
            for (int i = 1; i <= MaxClients; i++)
            {
                if (i != botClient && IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
                    otherBots[otherCount++] = i;
            }
            if (otherCount > 0)
            {
                int replyBot = otherBots[GetRandomInt(0, otherCount - 1)];
                char replyBotName[32];
                GetClientName(replyBot, replyBotName, sizeof(replyBotName));
                char replyCtx[640];
                Format(replyCtx, sizeof(replyCtx), "%s disse: \"%s\" Mood: Reaja.", botName, cleanMsg);
                // Forca rate limit manual
                g_LastBotChat = 0.0;
                AskBotChat(replyCtx, replyBot);
            }
        }

        // Bot speaks via say command (RP: actual bot chat, not server message)
        FakeClientCommand(botClient, "say %s", cleanMsg);
        g_LastBotChat = GetGameTime();
    }
}
