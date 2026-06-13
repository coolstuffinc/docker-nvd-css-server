#include <sourcemod>
#include <nvd/strings>

#pragma semicolon 1
#pragma newdecls required

enum struct PluginStrings
{
	char prefix[64];
	KeyValues kvDefault;
	KeyValues kvLang;
}

PluginStrings g_Plugins[16];
int g_Count = 0;
ConVar g_LangCvar;

public Plugin myinfo = { name = "NVD Strings Manager", author = "OpenCode", description = "Centralized string management for NVD plugins", version = "1.0.0" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("nvd_strings");
	CreateNative("NVD_RegisterStrings", Native_RegisterStrings);
	CreateNative("NVD_GetStr", Native_GetStr);
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_LangCvar = CreateConVar("nvd_language", "default", "Global language for all NVD plugins");
	g_LangCvar.AddChangeHook(OnLanguageChanged);
}

public void OnLanguageChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
	for (int i = 0; i < g_Count; i++) LoadStrings(i);
	PrintToServer("[NVD Strings] Language changed to '%s', reloaded %d plugins", newVal, g_Count);
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
	char prefix[64], section[64], key[64], fallback[512];
	GetNativeString(1, prefix, sizeof(prefix));
	GetNativeString(2, section, sizeof(section));
	GetNativeString(3, key, sizeof(key));
	int maxlen = GetNativeCell(5);
	GetNativeString(6, fallback, sizeof(fallback));

	for (int i = 0; i < g_Count; i++) {
		if (StrEqual(g_Plugins[i].prefix, prefix)) {
			char buffer[1024];
			bool found = false;

			if (!found && g_Plugins[i].kvLang != null) {
				g_Plugins[i].kvLang.Rewind();
				if (g_Plugins[i].kvLang.JumpToKey(section) && g_Plugins[i].kvLang.GetString(key, buffer, sizeof(buffer))) found = true;
			}

			if (!found && g_Plugins[i].kvDefault != null) {
				g_Plugins[i].kvDefault.Rewind();
				if (g_Plugins[i].kvDefault.JumpToKey(section) && g_Plugins[i].kvDefault.GetString(key, buffer, sizeof(buffer))) found = true;
			}

			if (found) SetNativeString(4, buffer, maxlen);
			else SetNativeString(4, fallback, maxlen);
			return 0;
		}
	}
	SetNativeString(4, fallback, maxlen);
	return 0;
}

void LoadStrings(int idx)
{
	if (g_Plugins[idx].kvDefault != null) delete g_Plugins[idx].kvDefault;
	if (g_Plugins[idx].kvLang != null) delete g_Plugins[idx].kvLang;
	g_Plugins[idx].kvDefault = null;
	g_Plugins[idx].kvLang = null;

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_default.txt", g_Plugins[idx].prefix);
	if (FileExists(path)) {
		g_Plugins[idx].kvDefault = new KeyValues("Strings");
		if (!g_Plugins[idx].kvDefault.ImportFromFile(path)) {
			delete g_Plugins[idx].kvDefault;
			g_Plugins[idx].kvDefault = new KeyValues("BotChatStrings");
			g_Plugins[idx].kvDefault.ImportFromFile(path);
		}
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
		}
	}
}
