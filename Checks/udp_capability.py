#!/usr/bin/env python3
"""Opt-in local capability check. No root, PF changes or external destinations.
This does not test censorship bypass, real voice/game traffic or system-wide UDP.
"""
from pathlib import Path
import socket
import subprocess
import time

binary = Path(__file__).resolve().parents[1] / '.build/native/tpws'

def receive(sock, count):
    result = b''
    while len(result) < count:
        block = sock.recv(count - len(result))
        if not block:
            raise RuntimeError('Unexpected SOCKS EOF')
        result += block
    return result

# Keep a bound local port until immediately before launch; fail if occupied
# rather than silently accepting another process as our test engine.
with socket.socket() as reserved:
    reserved.bind(('127.0.0.1', 0))
    port = reserved.getsockname()[1]
engine = subprocess.Popen([str(binary), '--socks', '--bind-addr=127.0.0.1',
                           '--port=' + str(port), '--maxconn=16'],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    deadline = time.monotonic() + 3
    while True:
        if engine.poll() is not None:
            raise RuntimeError('Test engine exited before readiness')
        try:
            control = socket.create_connection(('127.0.0.1', port), timeout=.2)
            break
        except OSError:
            if time.monotonic() > deadline:
                raise RuntimeError('Test listener did not become ready')
            time.sleep(.02)
    with control:
        control.settimeout(2)
        control.sendall(b'\x05\x01\x00')
        assert receive(control, 2) == b'\x05\x00'
        control.sendall(b'\x05\x03\x00\x01' + b'\x00' * 6)
        assert receive(control, 2) == b'\x05\x07', 'UDP capability changed; review documentation'
        assert engine.poll() is None
        print('PASS tpws explicitly rejects SOCKS UDP ASSOCIATE (reply 0x07)')
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server, \
            socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        server.bind(('127.0.0.1', 0))
        server.settimeout(2); client.settimeout(2)
        for payload in [b'a', b'local-udp-check', bytes(range(256)) * 4]:
            client.sendto(payload, server.getsockname())
            received, peer = server.recvfrom(2048)
            assert received == payload
            server.sendto(received, peer)
            assert client.recv(2048) == payload
        print('PASS direct loopback UDP datagrams remain intact while test engine runs')
    print('SCOPE local protocol capability only; no UDP/QUIC censorship bypass demonstrated')
finally:
    engine.terminate()
    try:
        engine.wait(timeout=3)
    except subprocess.TimeoutExpired:
        engine.kill(); engine.wait()
