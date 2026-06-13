#if defined _nvd_bot_chat_included
  #endinput
#endif
#define _nvd_bot_chat_included

#include <sourcemod>

/**
 * Submits a custom event for an AI bot to potentially comment on.
 * Use this from other plugins (RankMe, mixmod, etc.) to feed events
 * into the bot chat system.
 *
 * @param context      Event description text (e.g., "Reached rank #1!")
 * @param preferredBot Client index of preferred bot, or -1 for random
 * @param priority     Interest score 0-100 (higher = more likely to be chosen)
 * @param eventType    Template event type for prompt, or "" for "default"
 */
native void NVD_SubmitChatEvent(const char[] context, int preferredBot = -1, int priority = 50, const char[] eventType = "", int enemies = 0, int allies = 0);

/**
 * Retrieves a cached AI response for a given bot and (enemies, allies) scenario.
 * Returns true and fills the buffer if a cached response exists.
 */
native bool NVD_GetCachedResponse(int bot, int enemies, int allies, char[] buffer, int maxlen);

/**
 * Builds system and user prompts from a context JSON string.
 * Format: {"type":str, "description":str, "target":str, "weapon":str,
 *          "tScore":int, "ctScore":int, "enemies":int, "allies":int}.
 *
 * @param json    Context JSON string
 * @param section "system", "user", or "both"
 * @param botId   Client index of the bot
 * @param sysP    Output buffer for system prompt
 * @param fullP   Output buffer for user prompt
 * @param sysLen  Size of sysP buffer
 * @param fullLen Size of fullP buffer
 */
native void NVD_BuildPrompts(const char[] json, const char[] section, int botId,
    char[] sysP, int sysLen, char[] fullP, int fullLen);

public SharedPlugin __pl_nvd_bot_chat =
{
    name = "nvd_bot_chat",
    file = "nvd_bot_chat.smx",
    #if defined REQUIRE_PLUGIN
    required = 1,
    #else
    required = 0,
    #endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_nvd_bot_chat_SetNTVOptional()
{
    MarkNativeAsOptional("NVD_SubmitChatEvent");
    MarkNativeAsOptional("NVD_GetCachedResponse");
    MarkNativeAsOptional("NVD_BuildPrompts");
}
#endif