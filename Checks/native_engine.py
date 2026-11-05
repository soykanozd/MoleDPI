#!/usr/bin/env python3
"""Opt-in real HTTPS + SOCKS UDP capability check; never modifies PF."""
import os, socket, subprocess, time
from pathlib import Path
binary = Path(__file__).resolve().parents[1] / '.build/native/tpws'
engine = subprocess.Popen([str(binary), '--socks', '--bind-addr=127.0.0.1', '--port=18081', '--maxconn=128', '--filter-tcp=80,443', '--filter-l7=http,tls', '--split-pos=host+1', '--tlsrec=host+1'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env={'PATH':'/usr/bin:/bin','MOLEDPI_SPLIT_DELAY_US':'0'})
try:
    for attempt in range(50):
        if engine.poll() is not None:
            raise RuntimeError('tpws exited; port may be occupied')
        try:
            with socket.create_connection(('127.0.0.1',18081), timeout=.2) as s:
                s.sendall(b'\x05\x01\x00')
                assert s.recv(2) == b'\x05\x00'
            break
        except OSError:
            time.sleep(.1)
    else:
        raise RuntimeError('SOCKS listener never became ready')
    for host in ['example.com','discord.com','www.roblox.com']:
        result = subprocess.run(['/usr/bin/curl','--disable','--silent','--show-error','--fail','--max-time','10','--noproxy','','--proxy','socks5h://127.0.0.1:18081','-o','/dev/null','https://'+host+'/'], capture_output=True, text=True)
        assert result.returncode == 0, f'{host}: {result.stderr}'
        assert engine.poll() is None, 'our process must still be alive'
        print(f'PASS: source-built arm64 tpws, no added delay, HTTPS {host}', flush=True)
    with socket.create_connection(('127.0.0.1',18081), timeout=2) as s:
        s.sendall(b'\x05\x01\x00'); assert s.recv(2) == b'\x05\x00'
        s.sendall(b'\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00')
        reply = s.recv(32)
        assert not reply or (len(reply) >= 2 and reply[1] != 0), f'Unexpected UDP acceptance: {reply!r}'
        print(f'CONFIRMED LIMIT: SOCKS UDP ASSOCIATE rejected ({reply.hex()}); voice/game UDP not supported', flush=True)
finally:
    engine.terminate()
    try: engine.wait(timeout=3)
    except subprocess.TimeoutExpired: engine.kill(); engine.wait()
