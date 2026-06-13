import re
import json

def process_templates(text, context):
    # Simula ProcessTemplates
    text = text.replace("|bot|", context.get("bot", "Bot"))
    text = text.replace("|team|", context.get("team", "Team"))
    text = text.replace("|enemies|", str(context.get("enemies", 0)))
    text = text.replace("|allies|", str(context.get("allies", 0)))
    text = text.replace("|server_lang|", "Portuguese (PT-BR)")
    text = text.replace("|prompt_lang|", "Chinese (ZH)")
    return text

def test_prompt(template, context):
    print(f"Template: {template}")
    final_prompt = process_templates(template, context)
    print(f"Final Prompt: {final_prompt}")
    print("-" * 20)

# Simulação de um evento
context = {"bot": "s1mple", "team": "TR", "enemies": 3, "allies": 2}

# Template de sistema com a restrição de idioma
system_template = "|bot| from |team|. Rules: Do not narrate. |critical| Respond ONLY in |server_lang|."

# Exemplo de teste
test_prompt(system_template, context)
