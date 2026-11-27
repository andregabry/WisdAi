#!/usr/bin/env python3
"""
WisdAI CLI Agent - Autonomous Software Engineering Agent for Windows (Python Runtime)
"""

import os
import sys
import json
import subprocess
import urllib.request
import urllib.error

CONFIG_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "WisdAI")
API_KEYS_PATH = os.path.join(CONFIG_DIR, "api_keys.json")


def get_api_key(provider: str) -> str:
    if os.path.exists(API_KEYS_PATH):
        try:
            with open(API_KEYS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if provider in data and data[provider]:
                    return data[provider]
        except Exception:
            pass

    env_map = {
        "openai": "OPENAI_API_KEY",
        "gemini": "GEMINI_API_KEY",
        "anthropic": "ANTHROPIC_API_KEY",
        "deepseek": "DEEPSEEK_API_KEY"
    }
    return os.environ.get(env_map.get(provider, ""), "")


def execute_command(cmd: str):
    print("\033[34m> Executando no terminal Windows...\033[0m")
    try:
        shell = "powershell.exe" if os.name == "nt" else "/bin/sh"
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        if res.stdout:
            print(res.stdout)
        if res.stderr:
            print("\033[31m" + res.stderr + "\033[0m")
    except Exception as e:
        print(f"\033[31m[Erro]: {e}\033[0m")


def query_openai(prompt: str, key: str, model: str = "gpt-4o") -> str:
    url = "https://api.openai.com/v1/chat/completions"
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "Você é o WisdAI CLI Agent no Windows. Forneça respostas técnicas precisas, passos acionáveis e código de alta qualidade."},
            {"role": "user", "content": prompt}
        ]
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {key}"
        }
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"]


def repl():
    print("\033[1;36m")
    print("╔══════════════════════════════════════════════════════════╗")
    print("║        WisdAI Agent - Terminal Windows (Python)          ║")
    print("║   Agente Autônomo de Engenharia de Software no Windows   ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print("\033[0m")
    print(f"Workspace: \033[33m{os.getcwd()}\033[0m")
    print("Comandos: '$ <comando>', 'help', 'exit' ou faça uma pergunta.\n")

    while True:
        try:
            user_input = input("\033[1;32mwisdai>\033[0m ").strip()
            if not user_input:
                continue

            if user_input.lower() in ("exit", "quit", "sair"):
                print("\033[90mAté logo!\033[0m")
                break

            if user_input.lower() in ("help", "ajuda"):
                print("""
Comandos:
  $ <comando>    Executa comandos no terminal nativo (PowerShell/cmd)
  help           Exibe esta ajuda
  exit           Encerra o agente
""")
                continue

            if user_input.startswith("$ "):
                execute_command(user_input[2:])
                continue

            key = get_api_key("openai") or get_api_key("deepseek")
            if key:
                print("\033[36mPensando...\033[0m", end="\r")
                reply = query_openai(user_input, key)
                print(f"\r\033[1;34m[WisdAI]:\033[0m\n{reply}\n")
            else:
                print(f"\033[33m[Modo Local]:\033[0m Instrução: '{user_input}'")
                print("Para habilitar raciocínio por IA, configure OPENAI_API_KEY ou %APPDATA%\\WisdAI\\api_keys.json.")
                print("Use '$ <comando>' para executar tarefas locais no Windows.\n")

        except KeyboardInterrupt:
            print("\nOperação cancelada.")
            break
        except Exception as e:
            print(f"\033[31m[Erro]: {e}\033[0m\n")


def main():
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
        key = get_api_key("openai")
        if key:
            print(query_openai(prompt, key))
        else:
            print(f"[WisdAI Agent]: {prompt}")
    else:
        repl()


if __name__ == "__main__":
    main()
