#if defined _nvd_core_included
 #endinput
#endif
#define _nvd_core_included

#include <sourcemod>

// Callback for when AI responds: response (string), data (any)
typedef NVD_ResponseCallback = function void (const char[] response, any data);

/**
 * Sends a query to the AI.
 * prompt: What you want to ask/say.
 * systemPrompt: Context/rules for the AI.
 * callback: Function to be called when AI responds.
 * data: Extra data to pass to the callback.
 * historyJSON: (optional) Previous messages as JSON array.
 * priority: (optional) Priority for the queue.
 * timeout: (optional) Timeout in seconds.
 * contextJSON: (optional) JSON string with raw event context (type, description, target, weapon, scores, enemies, allies).
 *              When set, prompts are lazily built from template at processing time.
 */
native int NVD_AskAI(const char[] prompt, const char[] systemPrompt, NVD_ResponseCallback callback, any data, const char[] historyJSON = "", int priority = 0, float timeout = 120.0, const char[] ownerName = "", const char[] contextJSON = "");

/**
 * Checks if a player can make a request (rate limit).
 */
native bool NVD_CanRequest(int client);

/**
 * Polls for a pending AI response.
 */
native bool NVD_PollResponse(char[] reply, int maxlen, any &cbData);

/**
 * Sets a global metadata snippet (e.g. [rules], [behavior]).
 * Placeholders in brackets will be replaced automatically.
 */
native void NVD_SetMeta(const char[] key, const char[] value);

public SharedPlugin __pl_nvd_core = 
{
	name = "nvd_core",
	file = "ollama.smx",
	required = 1,
};

#if !defined REQUIRE_PLUGIN
public void __pl_nvd_core_SetNTVOptional()
{
	MarkNativeAsOptional("NVD_AskAI");
	MarkNativeAsOptional("NVD_CanRequest");
	MarkNativeAsOptional("NVD_PollResponse");
	MarkNativeAsOptional("NVD_SetMeta");
}
#endif
