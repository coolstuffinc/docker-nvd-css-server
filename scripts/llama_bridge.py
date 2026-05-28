import os
import time
import subprocess
import requests
import json
import re

# Configuration
LOG_PATH = "/var/lib/css-server/cstrike/logs"
OLLAMA_URL = "http://127.0.0.1:11435/v1/chat/completions" # Using the proxy
MODEL = "llama3.2:1b"
RCON_PASSWORD = os.getenv("RCON_PASSWORD", "defaultpassword")
SERVER_IP = "127.0.0.1"
SERVER_PORT = 27015

def send_rcon(command):
    # Using simple rcon CLI if available or a python implementation
    # For now, let's use the docker exec approach which is reliable
    cmd = f"sudo docker exec css-server /home/steam/css/srcds_run -game cstrike +rcon_password {RCON_PASSWORD} +rcon {command}"
    subprocess.run(cmd, shell=True)

def ask_llama(question):
    try:
        payload = {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": "You are a friendly and helpful Counter-Strike: Source server admin named Llama. Keep answers concise (max 2 sentences). You are helping users on the NVD Mix Server."},
                {"role": "user", "content": question}
            ]
        }
        response = requests.post(OLLAMA_URL, json=payload, timeout=30)
        data = response.json()
        return data['choices'][0]['message']['content']
    except Exception as e:
        return f"Error connecting to brain: {str(e)}"

def tail_f(path):
    # Find newest log file
    while True:
        logs = [os.path.join(path, f) for f in os.listdir(path) if f.endswith(".log")]
        if not logs:
            time.sleep(5)
            continue
        newest_log = max(logs, key=os.path.getmtime)
        print(f"Tailing {newest_log}")
        
        with open(newest_log, 'r', errors='replace') as f:
            f.seek(0, os.SEEK_END)
            while True:
                line = f.readline()
                if not line:
                    # Check if a newer file exists
                    current_newest = max([os.path.join(path, f) for f in os.listdir(path) if f.endswith(".log")], key=os.path.getmtime)
                    if current_newest != newest_log:
                        break
                    time.sleep(0.5)
                    continue
                yield line

def main():
    print("Llama Bridge started...")
    if not os.path.exists(LOG_PATH):
        print(f"Waiting for log directory {LOG_PATH}...")
        while not os.path.exists(LOG_PATH):
            time.sleep(5)

    for line in tail_f(LOG_PATH):
        # Format: L 05/27/2026 - 22:34:39: [LLAMA_QUERY] Name: Question
        match = re.search(r"\[LLAMA_QUERY\] (.*?): (.*)", line)
        if match:
            user = match.group(1)
            question = match.group(2)
            print(f"Query from {user}: {question}")
            
            answer = ask_llama(question)
            print(f"Llama: {answer}")
            
            # Clean answer for SourcePawn (no quotes, single line)
            clean_answer = answer.replace('"', "'").replace('\n', ' ')
            send_rcon(f'sm_say [Llama] {user}: {clean_answer}')

if __name__ == "__main__":
    main()
