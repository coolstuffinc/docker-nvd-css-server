#if defined _nvd_strings_included
 #endinput
#endif
#define _nvd_strings_included

#include <sourcemod>

/**
 * Registers a plugin for centralized string management.
 * Loads: configs/[prefix]_strings_default.txt and configs/[prefix]_strings_[lang].txt
 */
native void NVD_RegisterStrings(const char[] prefix);

/**
 * Retrieves a translated string using dot-notation path.
 * Example: NVD_GetStr("nvd.bot_chat.events.kill", buffer, sizeof(buffer));
 */
native void NVD_GetStr(const char[] path, char[] buffer, int maxlen);

/**
 * Checks if a string path exists.
 */
native bool NVD_HasStr(const char[] path);

public SharedPlugin __pl_nvd_strings = 
{
	name = "nvd_strings",
	file = "strings.smx",
	required = 1,
};

#if !defined REQUIRE_PLUGIN
public void __pl_nvd_strings_SetNTVOptional()
{
	MarkNativeAsOptional("NVD_RegisterStrings");
	MarkNativeAsOptional("NVD_GetStr");
	MarkNativeAsOptional("NVD_HasStr");
}
#endif
