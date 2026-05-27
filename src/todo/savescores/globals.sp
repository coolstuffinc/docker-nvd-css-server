#define GAME_ANY 0
#define GAME_CS 1
#define GAME_TF 2
#define GAME_HL 3
#define GAME_DOD 4

// CVars' handles
new Handle:cvar_save_scores = INVALID_HANDLE;
new Handle:cvar_save_scores_tracking_time = INVALID_HANDLE;
new Handle:cvar_save_scores_forever = INVALID_HANDLE;
new Handle:cvar_save_scores_allow_reset = INVALID_HANDLE;
new Handle:cvar_lan = INVALID_HANDLE;

// Commands' handles
new Handle:cvar_restartgame = INVALID_HANDLE;
new Handle:cvar_restartround = INVALID_HANDLE;

// Cvars' variables
new bool:save_scores = true;
new save_scores_tracking_time = 20;
new bool:save_scores_forever = false;
new bool:save_scores_allow_reset = true;
new bool:isLAN = false;

// DB handle
new Handle:g_hDB = INVALID_HANDLE;

// Other stuff
new bool:onlyCash[MAXPLAYERS+1] = {false, ...};
new bool:justConnected[MAXPLAYERS+1] = {true, ...};
new Game = GAME_ANY;
new bool:isNewGameTimer = false;
new Handle:g_hNewGameTimer = INVALID_HANDLE;
new bool:g_NextRoundNewGame = false;
new bool:g_isMenuItemCreated = false;

// Players info
new g_iPlayerScore[MAXPLAYERS+1];
new g_iPlayerDeaths[MAXPLAYERS+1];
new g_iPlayerCash[MAXPLAYERS+1];
