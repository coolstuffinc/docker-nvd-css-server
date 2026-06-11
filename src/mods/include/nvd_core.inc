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
 * historyBlock: (opcional) Mensagens anteriores separadas por ||| para injetar como assistant
 */
native int NVD_AskAI(const char[] prompt, const char[] systemPrompt, NVD_ResponseCallback callback, any data, const char[] historyBlock = "", int priority = 0, float timeout = 60.0);

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

/**
 * Define um snippet de metadados global (Ex: [rules], [behavior]).
 * Placeholders entre colchetes serão substituídos automaticamente em todos os prompts.
 */
native void NVD_SetMeta(const char[] key, const char[] value);

/**
 * Registra o plugin para gestão centralizada de strings.
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

public SharedPlugin __pl_nvd_core = 
{
	name = "nvd_core",
	file = "nvd_ollama.smx",
	required = 1,
};
