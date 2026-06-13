#include <sourcemod>
#include <nvd/strings>

#pragma semicolon 1
#pragma newdecls required

enum struct PluginStrings
{
	char prefix[64];
	KeyValues kvDefault;
	KeyValues kvLang;
	KeyValues kvPromptLang;
}

PluginStrings g_Plugins[16];
int g_Count = 0;
ConVar g_LangCvar;
ConVar g_PromptLangCvar;

public Plugin myinfo = { name = "NVD Strings Manager", author = "OpenCode", description = "Centralized string management for NVD plugins", version = "1.1.0" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("nvd_strings");
	CreateNative("NVD_RegisterStrings", Native_RegisterStrings);
	CreateNative("NVD_GetStr", Native_GetStr);
	CreateNative("NVD_HasStr", Native_HasStr);
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_LangCvar = CreateConVar("nvd_language", "default", "Global output language for all NVD plugins");
	g_PromptLangCvar = CreateConVar("nvd_prompt_language", "default", "Language for prompts section (default uses nvd_language)");
	g_LangCvar.AddChangeHook(OnLanguageChanged);
	g_PromptLangCvar.AddChangeHook(OnLanguageChanged);
}

public void OnLanguageChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
	for (int i = 0; i < g_Count; i++) LoadStrings(i);
	PrintToServer("[NVD Strings] Language settings changed, reloaded %d plugins", g_Count);
}

public int Native_RegisterStrings(Handle plugin, int numParams)
{
	char prefix[64];
	GetNativeString(1, prefix, sizeof(prefix));

	for (int i = 0; i < g_Count; i++) {
		if (StrEqual(g_Plugins[i].prefix, prefix)) return 0;
	}

	if (g_Count < 16) {
		strcopy(g_Plugins[g_Count].prefix, 64, prefix);
		LoadStrings(g_Count);
		g_Count++;
	}
	return 0;
}

public int Native_GetStr(Handle plugin, int numParams)
{
    char path[128], key[64], buffer[1024];
    GetNativeString(1, path, sizeof(path));
    GetNativeString(2, key, sizeof(key));
    int maxlen = GetNativeCell(4);

    char parts[8][32];
    int count = ExplodeString(path, ".", parts, 8, 32);

    for (int i = 0; i < g_Count; i++) {
        // Tenta buscar no arquivo de idioma principal (prompt lang ou lang)
        KeyValues kv = (g_Plugins[i].kvPromptLang != null) ? g_Plugins[i].kvPromptLang : g_Plugins[i].kvLang;
        if (kv != null) {
            kv.Rewind();
            bool found = true;
            for (int j = 0; j < count; j++) {
                if (!kv.JumpToKey(parts[j])) { found = false; break; }
            }
            if (found && kv.GetString(key, buffer, sizeof(buffer))) {
                SetNativeString(3, buffer, maxlen);
                return 0;
            }
        }

        // Tenta buscar no arquivo default
        if (g_Plugins[i].kvDefault != null) {
            g_Plugins[i].kvDefault.Rewind();
            bool found = true;
            for (int j = 0; j < count; j++) {
                if (!g_Plugins[i].kvDefault.JumpToKey(parts[j])) { found = false; break; }
            }
            if (found && g_Plugins[i].kvDefault.GetString(key, buffer, sizeof(buffer))) {
                SetNativeString(3, buffer, maxlen);
                return 0;
            }
        }
    }
    ThrowNativeError(SP_ERROR_NATIVE, "String key '%s' not found in path '%s'", key, path);
    return 0;
}

public int Native_HasStr(Handle plugin, int numParams)
{
	char path[128], key[64];
	GetNativeString(1, path, sizeof(path));
	GetNativeString(2, key, sizeof(key));

	char parts[8][32];
	int count = ExplodeString(path, ".", parts, 8, 32);

	for (int i = 0; i < g_Count; i++) {
			// Try Lang
			if (g_Plugins[i].kvLang != null) {
				g_Plugins[i].kvLang.Rewind();
				KeyValues kv = g_Plugins[i].kvLang;
				bool found = true;
				for (int j = 0; j < count; j++) {
					if (!kv.JumpToKey(parts[j])) { found = false; break; }
				}
				if (found && kv.JumpToKey(key)) return true;
			}
			// Try Default
			if (g_Plugins[i].kvDefault != null) {
				g_Plugins[i].kvDefault.Rewind();
				KeyValues kv = g_Plugins[i].kvDefault;
				bool found = true;
				for (int j = 0; j < count; j++) {
					if (!kv.JumpToKey(parts[j])) { found = false; break; }
				}
				if (found && kv.JumpToKey(key)) return true;
			}
	}
	return false;
}

void LoadStrings(int idx)
{
	LogMessage("Loading strings for prefix '%s' (idx %d)", g_Plugins[idx].prefix, idx);
	if (g_Plugins[idx].kvDefault != null) delete g_Plugins[idx].kvDefault;
	if (g_Plugins[idx].kvLang != null) delete g_Plugins[idx].kvLang;
	if (g_Plugins[idx].kvPromptLang != null) delete g_Plugins[idx].kvPromptLang;
	g_Plugins[idx].kvDefault = null;
	g_Plugins[idx].kvLang = null;
	g_Plugins[idx].kvPromptLang = null;

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_default.txt", g_Plugins[idx].prefix);
	if (FileExists(path)) {
		g_Plugins[idx].kvDefault = new KeyValues("Strings");
		if (!g_Plugins[idx].kvDefault.ImportFromFile(path)) {
			delete g_Plugins[idx].kvDefault;
			g_Plugins[idx].kvDefault = new KeyValues("BotChatStrings");
			g_Plugins[idx].kvDefault.ImportFromFile(path);
		}
		LogMessage("Loaded default strings from %s", path);
	}

	char lang[32]; g_LangCvar.GetString(lang, sizeof(lang));
	if (!StrEqual(lang, "default")) {
		BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_%s.txt", g_Plugins[idx].prefix, lang);
		if (FileExists(path)) {
			g_Plugins[idx].kvLang = new KeyValues("Strings");
			if (!g_Plugins[idx].kvLang.ImportFromFile(path)) {
				delete g_Plugins[idx].kvLang;
				g_Plugins[idx].kvLang = new KeyValues("BotChatStrings");
				g_Plugins[idx].kvLang.ImportFromFile(path);
			}
			LogMessage("Loaded language strings (%s) from %s", lang, path);
		}
	}

	char promptLang[32]; g_PromptLangCvar.GetString(promptLang, sizeof(promptLang));
	if (!StrEqual(promptLang, "default") && !StrEqual(promptLang, lang)) {
		BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_%s.txt", g_Plugins[idx].prefix, promptLang);
		if (FileExists(path)) {
			g_Plugins[idx].kvPromptLang = new KeyValues("Strings");
			if (!g_Plugins[idx].kvPromptLang.ImportFromFile(path)) {
				delete g_Plugins[idx].kvPromptLang;
				g_Plugins[idx].kvPromptLang = new KeyValues("BotChatStrings");
				g_Plugins[idx].kvPromptLang.ImportFromFile(path);
			}
			LogMessage("Loaded prompt language strings (%s) from %s", promptLang, path);
		}
	}
}
