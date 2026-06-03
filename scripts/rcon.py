#!/usr/bin/env python3
import socket
import sys
import hashlib
import struct
import random

def rcon_exec(host, port, password, command):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect((host, port))

    req_id = random.randint(0, 2**31)

    # SERVERDATA_AUTH
    payload = struct.pack('<ii', 10, 1) + password.encode('utf-8') + b'\x00' + command.encode('utf-8') + b'\x00'
    pkt = struct.pack('<i', req_id) + struct.pack('<i', 3) + password.encode() + b'\x00\x00'
    sock.send(struct.pack('<i', len(pkt)) + pkt)

    # read auth response
    raw = sock.recv(4096)

    # SERVERDATA_EXECCOMMAND
    pkt2 = struct.pack('<i', req_id + 1) + struct.pack('<i', 2) + command.encode() + b'\x00\x00'
    sock.send(struct.pack('<i', len(pkt2)) + pkt2)

    raw = b''
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            raw += chunk
    except:
        pass

    sock.close()
    print(raw.decode('utf-8', errors='replace'))

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print(f"Usage: {sys.argv[0]} <host> <port> <password> <command>")
        sys.exit(1)
    rcon_exec(sys.argv[1], int(sys.argv[2]), sys.argv[3], ' '.join(sys.argv[4:]))
