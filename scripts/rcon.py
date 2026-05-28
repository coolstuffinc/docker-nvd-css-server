#!/usr/bin/env python3
import sys
import os

# Add scripts directory to path to find rcon_lib
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from rcon_lib.client import RCONClient

def main():
    if len(sys.argv) < 2:
        print("Usage: rcon <command>")
        sys.exit(1)
    
    password = os.getenv("RCON_PASSWORD", "defaultpassword")
    host = "127.0.0.1"
    port = 27015
    command = " ".join(sys.argv[1:])

    try:
        with RCONClient(host, port, password) as client:
            response = client.run(command)
            print(response)
    except Exception as e:
        print(f"RCON Error: {e}")

if __name__ == "__main__":
    main()
