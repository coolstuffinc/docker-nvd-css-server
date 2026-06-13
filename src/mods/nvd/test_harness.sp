#include <sourcemod>
#include <nvd_bot_chat>
#include <ripext>

public Plugin myinfo = {
    name = "NVD Test Harness",
    author = "OpenCode",
    description = "Ferramenta de testes para NVD",
    version = "1.0.0"
};

public void OnPluginStart() {
    RegAdminCmd("sm_nvd_test", Command_Test, ADMFLAG_ROOT);
}

public Action Command_Test(int client, int args) {
    if (args < 1) {
        ReplyToCommand(client, "Uso: sm_nvd_test <prompt|event> ...");
        return Plugin_Handled;
    }

    char subCmd[32];
    GetCmdArg(1, subCmd, sizeof(subCmd));

    if (StrEqual(subCmd, "prompt")) {
        char type[32];
        if (args < 2) strcopy(type, sizeof(type), "default");
        else GetCmdArg(2, type, sizeof(type));

        JSONObject ctx = new JSONObject();
        ctx.SetString("type", type);
        ctx.SetString("description", "test");
        ctx.SetString("target", "jks");
        ctx.SetString("weapon", "ak47");
        ctx.SetInt("tScore", 10);
        ctx.SetInt("ctScore", 5);
        ctx.SetInt("enemies", 2);
        ctx.SetInt("allies", 3);
        
        char json[1024];
        ctx.ToString(json, sizeof(json));
        delete ctx;
        
        ReplyToCommand(client, "[NVD_TEST] JSON: %s", json);

        char sysP[2048], fullP[1024];
        int testBotId = (client > 0 && IsClientInGame(client)) ? client : 1;
        NVD_BuildPrompts(json, "both", testBotId, sysP, sizeof(sysP), fullP, sizeof(fullP));

        ReplyToCommand(client, "[NVD_TEST] Prompt Construído:");
        ReplyToCommand(client, "System: %s", sysP);
        ReplyToCommand(client, "User: %s", fullP);
    } else if (StrEqual(subCmd, "event")) {
        char ctx[256], type[32];
        GetCmdArg(2, ctx, sizeof(ctx));
        GetCmdArg(3, type, sizeof(type));

        ReplyToCommand(client, "[NVD_TEST] Disparando evento: %s (%s)", type, ctx);
        NVD_SubmitChatEvent(ctx, client, 100, type);
    } else {
        ReplyToCommand(client, "Subcomando inválido. Use 'prompt' ou 'event'.");
    }
    return Plugin_Handled;
}
