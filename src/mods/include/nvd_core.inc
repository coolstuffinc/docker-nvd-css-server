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
 * client: (opcional) ID do jogador para rate limiting (-1 = sem rate limit)
 */
native int NVD_AskAI(const char[] prompt, const char[] systemPrompt, NVD_ResponseCallback callback, any data, int client = -1, float timeout = 0.0);

/**
 * Verifica se o jogador pode fazer uma requisição (rate limit).
 * Retorna true se pode, false se excedeu o limite.
 */
native bool NVD_CanRequest(int client);

/**
 * Polls for a pending AI response.
 * Returns true if a response was available, false otherwise.
 */
native bool NVD_PollResponse(char[] reply, int maxlen, any &cbData);

public SharedPlugin __pl_nvd_core = 
{
	name = "nvd_core",
	file = "nvd_ollama.smx",
	required = 1,
};
