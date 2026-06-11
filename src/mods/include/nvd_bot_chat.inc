#if defined _nvd_bot_chat_included
  #endinput
#endif
#define _nvd_bot_chat_included

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
native void NVD_SubmitChatEvent(const char[] context, int preferredBot = -1, int priority = 50, const char[] eventType = "");

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