#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

enum struct PluginStrings {
    char prefix[64];
    KeyValues kvDefault;
    KeyValues kvLang;
    KeyValues kvPromptLang;
}
PluginStrings g_Plugins[16];
int g_Count = 0;
ConVar g_LangCvar, g_PromptLangCvar;

public Plugin myinfo = { name = "NVD Strings Manager", author = "OpenCode", description = "Dot-notation strings", version = "1.5.0" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    RegPluginLibrary("nvd_strings");
    CreateNative("NVD_RegisterStrings", Native_RegisterStrings);
    CreateNative("NVD_GetStr", Native_GetStr);
    CreateNative("NVD_HasStr", Native_HasStr);
    return APLRes_Success;
}

public void OnPluginStart() {
    g_LangCvar = CreateConVar("nvd_language", "default", "Global language");
    g_PromptLangCvar = CreateConVar("nvd_prompt_language", "default", "Prompt language");
    g_LangCvar.AddChangeHook(OnLanguageChanged);
    g_PromptLangCvar.AddChangeHook(OnLanguageChanged);
}

public void OnLanguageChanged(ConVar convar, const char[] oldVal, const char[] newVal) {
    for (int i = 0; i < g_Count; i++) LoadStrings(i);
}

public int Native_RegisterStrings(Handle plugin, int numParams) {
    char prefix[64]; GetNativeString(1, prefix, sizeof(prefix));
    for (int i = 0; i < g_Count; i++) if (StrEqual(g_Plugins[i].prefix, prefix)) return 0;
    if (g_Count < 16) {
        strcopy(g_Plugins[g_Count].prefix, 64, prefix);
        LoadStrings(g_Count);
        g_Count++;
    }
    return 0;
}

// Parse "nvd.bot_chat.events.kill" -> parts=["nvd","bot_chat","events"], key="kill"
void ParsePath(const char[] path, char[][] parts, int &count, char[] key, int keySize) {
    char buf[256];
    strcopy(buf, sizeof(buf), path);
    char tmp[8][32];
    int n = ExplodeString(buf, ".", tmp, 8, 32);
    strcopy(key, keySize, tmp[n-1]);
    count = n - 1;
    for (int i = 0; i < count; i++) strcopy(parts[i], 32, tmp[i]);
}

bool GetStringFromKV(KeyValues kv, const char[][] parts, int count, const char[] key, char[] buffer, int maxlen) {
    kv.Rewind();
    for (int i = 0; i < count; i++) {
        if (!kv.JumpToKey(parts[i])) return false;
    }
    buffer[0] = '\0';
    kv.GetString(key, buffer, maxlen);
    return buffer[0] != '\0';
}

public int Native_GetStr(Handle plugin, int numParams) {
    char path[256];
    GetNativeString(1, path, sizeof(path));

    char parts[8][32], key[64];
    int count;
    ParsePath(path, parts, count, key, sizeof(key));

    int maxlen = GetNativeCell(3);
    char buffer[1024];
    SetNativeString(2, buffer, maxlen);

    for (int i = 0; i < g_Count; i++) {
        KeyValues kv = (g_Plugins[i].kvPromptLang != null) ? g_Plugins[i].kvPromptLang : g_Plugins[i].kvLang;
        if (kv != null && GetStringFromKV(kv, parts, count, key, buffer, sizeof(buffer))) {
            SetNativeString(2, buffer, maxlen);
            return 0;
        }
        if (g_Plugins[i].kvDefault != null && GetStringFromKV(g_Plugins[i].kvDefault, parts, count, key, buffer, sizeof(buffer))) {
            SetNativeString(2, buffer, maxlen);
            return 0;
        }
    }
    ThrowNativeError(SP_ERROR_NATIVE, "String key not found: '%s'", path);
    return 0;
}

public int Native_HasStr(Handle plugin, int numParams) {
    char path[256];
    GetNativeString(1, path, sizeof(path));

    char parts[8][32], key[64];
    int count;
    ParsePath(path, parts, count, key, sizeof(key));

    char val[4];
    for (int i = 0; i < g_Count; i++) {
        KeyValues kv = (g_Plugins[i].kvPromptLang != null) ? g_Plugins[i].kvPromptLang : g_Plugins[i].kvLang;
        if (kv != null && GetStringFromKV(kv, parts, count, key, val, sizeof(val))) return true;
        if (g_Plugins[i].kvDefault != null && GetStringFromKV(g_Plugins[i].kvDefault, parts, count, key, val, sizeof(val))) return true;
    }
    return false;
}

void LoadStrings(int idx) {
    if (g_Plugins[idx].kvDefault != null) delete g_Plugins[idx].kvDefault;
    if (g_Plugins[idx].kvLang != null) delete g_Plugins[idx].kvLang;
    if (g_Plugins[idx].kvPromptLang != null) delete g_Plugins[idx].kvPromptLang;
    g_Plugins[idx].kvDefault = null; g_Plugins[idx].kvLang = null; g_Plugins[idx].kvPromptLang = null;

    char path[PLATFORM_MAX_PATH], lang[32], promptLang[32];
    g_LangCvar.GetString(lang, sizeof(lang));
    g_PromptLangCvar.GetString(promptLang, sizeof(promptLang));

    BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_default.txt", g_Plugins[idx].prefix);
    if (FileExists(path)) {
        g_Plugins[idx].kvDefault = new KeyValues("Strings");
        g_Plugins[idx].kvDefault.ImportFromFile(path);
    }
    if (!StrEqual(lang, "default")) {
        BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_%s.txt", g_Plugins[idx].prefix, lang);
        if (FileExists(path)) {
            g_Plugins[idx].kvLang = new KeyValues("Strings");
            g_Plugins[idx].kvLang.ImportFromFile(path);
        }
    }
    if (!StrEqual(promptLang, "default") && !StrEqual(promptLang, lang)) {
        BuildPath(Path_SM, path, sizeof(path), "configs/%s_strings_%s.txt", g_Plugins[idx].prefix, promptLang);
        if (FileExists(path)) {
            g_Plugins[idx].kvPromptLang = new KeyValues("Strings");
            g_Plugins[idx].kvPromptLang.ImportFromFile(path);
        }
    }
}
