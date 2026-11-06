#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Real macOS QUIC over the source-built local packet -> SOCKS -> UDP pipeline.
Only this Mac's assigned address and loopback sockets; no routing modifications.
"""
from pathlib import Path
import select
import socket
import subprocess
import tempfile
import time
from pipeline_test import BUILD, LOCAL, LOCAL6, child, packet, payload, pipeline

def openssl(*args):
    subprocess.run(['/usr/bin/openssl',*map(str,args)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def check(fake, family=socket.AF_INET):
    with tempfile.TemporaryDirectory(prefix='moledpi-quic-') as folder:
        folder=Path(folder)
        openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',folder/'key.pem','-out',folder/'cert.pem','-subj','/CN=localhost','-days','1')
        openssl('x509','-in',folder/'cert.pem','-outform','DER','-out',folder/'cert.der')
        openssl('pkcs12','-export','-inkey',folder/'key.pem','-in',folder/'cert.pem','-out',folder/'identity.p12','-passout','pass:local-test')
        server=subprocess.Popen([str(BUILD/'quic-fixture'),'server',str(folder/'identity.p12'),LOCAL6 if family==socket.AF_INET6 else LOCAL],stdout=subprocess.PIPE,text=True,stderr=subprocess.DEVNULL)
        try:
            assert select.select([server.stdout],[],[],5)[0], 'QUIC server startup timed out'
            ready=server.stdout.readline().strip()
            assert ready.startswith('READY '), 'QUIC identity/listener setup failed'
            destination=int(ready.split()[1])
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as bridge, pipeline(fake,quic=True) as (tun,engine,tunnel):
                bridge.bind(('127.0.0.1',0))
                client=subprocess.Popen([str(BUILD/'quic-fixture'),'client',str(bridge.getsockname()[1]),str(folder/'cert.der')],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
                peer=None; outbound=0; inbound=0
                try:
                    end=time.monotonic()+18
                    while client.poll() is None and time.monotonic()<end:
                        assert engine.poll() is None and tunnel.poll() is None, 'UDP pipeline exited'
                        readable,_,_=select.select([bridge,tun],[],[],.05)
                        for sock in readable:
                            if sock is bridge:
                                data,peer=bridge.recvfrom(65535)
                                assert peer[0]=='127.0.0.1'
                                tun.send(packet(data,destination,family=family,source_port=35100));outbound+=1
                            else:
                                data=payload(tun.recv(65535))
                                if data is not None and peer:
                                    bridge.sendto(data,peer);inbound+=1
                    if client.poll() is None: raise AssertionError('QUIC pipeline timeout')
                    output=client.stdout.read()
                    assert client.returncode==0 and output.startswith('PASS real QUIC'), 'QUIC handshake/echo failed'
                    assert outbound>0 and inbound>0, 'No real packets crossed the local tunnel'
                    print('PASS '+('IPv6' if family==socket.AF_INET6 else 'IPv4')+' certificate-pinned QUIC handshake and stream echo via HEV + ByeDPI; UDP fakes '+('enabled' if fake else 'disabled'),flush=True)
                finally:
                    if client.poll() is None: client.terminate()
                    client.wait(timeout=3)
        finally:
            if server.poll() is None: server.terminate()
            server.wait(timeout=3)

if __name__=='__main__':
    for fake in [False,True]:
        check(fake)
        if LOCAL6: check(fake,socket.AF_INET6)
    print('SCOPE real local QUIC transport, not HTTP/3 compatibility or real ISP censorship bypass')
