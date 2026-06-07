#!/usr/bin/env python3
import socket
import sys
import struct
import random
import uuid

def recv_exact(sock, size):
    """Recebe exatamente 'size' bytes do socket, garantindo que o pacote não venha truncado."""
    data = b''
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("Conexão fechada pelo servidor")
        data += chunk
    return data

def read_rcon_packet(sock):
    """Lê e parseia um pacote RCON completo, extraindo apenas o texto útil."""
    # 1. Lê o tamanho do pacote (4 bytes iniciais)
    size_data = recv_exact(sock, 4)
    size = struct.unpack('<i', size_data)[0]
    
    # 2. Lê o payload completo do pacote
    payload = recv_exact(sock, size)
    
    # 3. Extrai o Request ID e o Type (primeiros 8 bytes)
    req_id, pkt_type = struct.unpack('<ii', payload[:8])
    
    # 4. O corpo (texto) vai do byte 8 até o primeiro byte nulo (\x00)
    body_end = payload.find(b'\x00', 8)
    if body_end != -1:
        body = payload[8:body_end]
    else:
        body = payload[8:]
        
    return req_id, pkt_type, body

def rcon_exec(host, port, password, command):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10) # Timeout inicial para conectar e autenticar
    
    try:
        sock.connect((host, port))
    except Exception as e:
        print(f"Erro ao conectar: {e}")
        return

    req_id = random.randint(0, 2**31 - 1)

    # --- 1. AUTENTICAÇÃO (SERVERDATA_AUTH = 3) ---
    auth_payload = struct.pack('<ii', req_id, 3) + password.encode('utf-8') + b'\x00\x00'
    sock.send(struct.pack('<i', len(auth_payload)) + auth_payload)

    try:
        res_id, res_type, body = read_rcon_packet(sock)
        if res_id == -1:
            print("Erro: Autenticação falhou (senha incorreta).")
            sock.close()
            return
    except Exception as e:
        print(f"Erro na autenticação: {e}")
        sock.close()
        return

    # --- 2. GERAR TOKEN DE FIM DE RESPOSTA ---
    # Criamos um token único para saber quando o servidor terminou de falar
    end_token = f"__END_RCON_{uuid.uuid4().hex[:8]}__"
    
    # --- 3. ENVIAR COMANDO REAL (SERVERDATA_EXECCOMMAND = 2) ---
    exec_payload = struct.pack('<ii', req_id + 1, 2) + command.encode('utf-8') + b'\x00\x00'
    sock.send(struct.pack('<i', len(exec_payload)) + exec_payload)
    
    # --- 4. ENVIAR COMANDO ECHO COM O TOKEN ---
    # O servidor vai processar o comando real e depois vai "ecoar" o token
    echo_cmd = f"echo {end_token}"
    echo_payload = struct.pack('<ii', req_id + 2, 2) + echo_cmd.encode('utf-8') + b'\x00\x00'
    sock.send(struct.pack('<i', len(echo_payload)) + echo_payload)

    # --- 5. LER RESPOSTAS ATÉ ENCONTRAR O TOKEN ---
    full_response = b''
    token_bytes = end_token.encode('utf-8')
    
    while True:
        try:
            res_id, res_type, body = read_rcon_packet(sock)
            
            # Se o token aparecer, o servidor terminou de enviar a resposta do comando real
            if token_bytes in body:
                # Remove o próprio texto do echo que veio junto com o token
                parts = body.split(token_bytes)
                full_response += parts[0]
                break
                
            # Concatena o corpo do pacote (agora limpo, sem os cabeçalhos binários)
            if body:
                full_response += body + b'\n'
                
        except socket.timeout:
            print("\nAviso: Timeout ao aguardar resposta do servidor.")
            break
        except ConnectionError:
            break
        except Exception as e:
            print(f"\nErro ao ler pacote: {e}")
            break

    sock.close()
    
    # Decodifica e imprime a resposta limpa
    response_text = full_response.decode('utf-8', errors='replace').strip()
    if response_text:
        print(response_text)
    else:
        print("(Comando executado com sucesso, sem saída)")

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print(f"Usage: {sys.argv[0]} <host> <port> <password> <command>")
        sys.exit(1)
    
    rcon_exec(sys.argv[1], int(sys.argv[2]), sys.argv[3], ' '.join(sys.argv[4:]))
