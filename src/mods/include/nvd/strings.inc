#if defined _nvd_strings_included
 #endinput
#endif
#define _nvd_strings_included

#include <sourcemod>

/**
 * Registers a plugin for centralized string management.
 * O core tentará carregar: configs/[prefix]_strings_default.txt 
 * e configs/[prefix]_strings_[lang].txt
 */
native void NVD_RegisterStrings(const char[] prefix);

/**
 * Busca uma string traduzida.
 * section: Seção no KV.
 * key: Chave da string.
 * fallback: Valor se não encontrar.
 */
native void NVD_GetStr(const char[] prefix, const char[] section, const char[] key, char[] buffer, int maxlen, const char[] fallback = "");

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
}
#endif
