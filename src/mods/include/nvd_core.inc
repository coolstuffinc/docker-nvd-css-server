#if defined _nvd_core_included
 #endinput
#endif
#define _nvd_core_included

// Callback para quando a IA responder: response (string), data (any)
typedef NVD_ResponseCallback = function void (const char[] response, any data);

/**
 * Envia uma consulta para a IA.
 * prompt: O que você quer perguntar/falar.
 * systemPrompt: Contexto/regras da IA.
 * callback: Função que será chamada quando a IA responder.
 * data: Dados extra para passar para o callback.
 */
native void NVD_AskAI(const char[] prompt, const char[] systemPrompt, NVD_ResponseCallback callback, any data);

public SharedPlugin __pl_nvd_core = 
{
	name = "nvd_core",
	file = "nvd_core.smx",
	required = 1,
};
