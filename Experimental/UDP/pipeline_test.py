#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Real source-built engine pipeline, synthetic packets, loopback destinations only.
No root, routes, PF, DNS settings, packet capture or external traffic.
"""
import contextlib
import ipaddress
import re
import os
from pathlib import Path
import select
import signal
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / '.build/udp-lab'
FAKE = b'MoleDPI-lab-fake-not-application-data'
def local_address():
    # Only addresses already assigned to this Mac. Never contact DNS or public endpoints.
    for _, name in socket.if_nameindex():
        if not name.startswith(('en','bridge')): continue
        result=subprocess.run(['/usr/sbin/ipconfig','getifaddr',name],capture_output=True,text=True)
        address=result.stdout.strip()
        if result.returncode==0 and address:
            socket.inet_pton(socket.AF_INET,address)
            return address
    raise RuntimeError('An active local IPv4 interface is needed for this fixture')
LOCAL = local_address()
def local_ipv6():
    for _, name in socket.if_nameindex():
        if name.startswith('lo'): continue
        text=subprocess.run(['/sbin/ifconfig',name],capture_output=True,text=True).stdout
        for address in re.findall(r'inet6\s+([0-9a-f:]+)',text):
            ip=ipaddress.IPv6Address(address)
            if not ip.is_link_local and not ip.is_loopback and not ip.is_unspecified:
                return address
    return None
LOCAL6 = local_ipv6()

def checksum(data):
    if len(data) % 2: data += b'\x00'
    value = sum(struct.unpack('!%dH' % (len(data)//2), data))
    while value >> 16: value = (value & 65535) + (value >> 16)
    return (~value) & 65535

def packet(data, port, family=socket.AF_INET, source_port=35000):
    v6 = family == socket.AF_INET6
    src = socket.inet_pton(family, 'fd00::2' if v6 else '198.18.0.2')
    dst = socket.inet_pton(family, LOCAL6 if v6 else LOCAL)
    udp = struct.pack('!HHHH', source_port, port, len(data)+8, 0) + data
    pseudo = src+dst+(struct.pack('!I3xB',len(udp),17) if v6 else struct.pack('!BBH',0,17,len(udp)))
    udp = udp[:6] + struct.pack('!H', checksum(pseudo+udp) or 65535) + udp[8:]
    if v6: ip = struct.pack('!IHBB16s16s',6<<28,len(udp),17,64,src,dst)
    else:
        ip = struct.pack('!BBHHHBBH4s4s',0x45,0,20+len(udp),1,0,64,17,0,src,dst)
        ip = ip[:10]+struct.pack('!H',checksum(ip))+ip[12:]
    return struct.pack('!I',family)+ip+udp

def payload(frame):
    family = struct.unpack('!I',frame[:4])[0]
    ip = frame[4:]
    offset = 40 if family == socket.AF_INET6 else (ip[0]&15)*4
    if (ip[6] if family == socket.AF_INET6 else ip[9]) != 17: return None
    return ip[offset+8:]

@contextlib.contextmanager
def child(args, **kw):
    p = subprocess.Popen([str(a) for a in args],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,**kw)
    try: yield p
    finally:
        if p.poll() is None: p.terminate()
        try: p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            p.kill(); p.wait(timeout=3)
            raise AssertionError('Test process needed forced shutdown')
        assert p.returncode == 0, 'Test process did not shut down cleanly'

@contextlib.contextmanager
def pipeline(fake=False, quic=False):
    with tempfile.TemporaryDirectory(prefix='moledpi-udp-') as temp, socket.socket() as reserved:
        reserved.bind(('127.0.0.1',0)); port=reserved.getsockname()[1]; reserved.close()
        args=[BUILD/'byedpi/ciadpi','--ip','127.0.0.1','--port',str(port), '--max-conn','32']
        if fake:
            args += ['--proto','udp','--udp-fake','1','--ttl','1']
            if not quic: args += ['--fake-data',':'+FAKE.decode()]
        config=Path(temp)/'tunnel.yml'
        config.write_text('tunnel:\n  mtu: 1500\n  ipv4: 198.18.0.1\n  ipv6: "fd00::1"\nsocks5:\n  address: 127.0.0.1\n  port: '+str(port)+'\n  udp: udp\nmisc:\n  log-level: error\n  max-session-count: 32\n  udp-read-write-timeout: 2000\n')
        with child(args) as engine:
            deadline=time.monotonic()+3
            while True:
                assert engine.poll() is None, 'ByeDPI exited'
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.1): break
                except OSError:
                    if time.monotonic()>deadline: raise AssertionError('Engine startup timeout')
                    time.sleep(.01)
            parent,tun = socket.socketpair(socket.AF_UNIX,socket.SOCK_DGRAM)
            with parent, tun, child([BUILD/'tunnel-runner',config,str(tun.fileno())],pass_fds=(tun.fileno(),)) as tunnel:
                # Packet submission retries are bounded: no arbitrary startup sleep.
                yield parent,engine,tunnel

def test_roundtrip(fake, family):
    with socket.socket(family,socket.SOCK_DGRAM) as endpoint, pipeline(fake) as (tun,engine,tunnel):
        endpoint.bind((LOCAL6 if family==socket.AF_INET6 else LOCAL,0))
        time.sleep(.6)  # Regression: idle poll slices must not terminate the engine.
        test=b'actual-udp-payload-'+bytes(range(256))*4
        frame=packet(test,endpoint.getsockname()[1],family)
        end=time.monotonic()+5
        saw_fake=False; returned=False
        next_send=0
        while time.monotonic()<end and not returned:
            assert engine.poll() is None and tunnel.poll() is None, 'Pipeline process exited'
            if time.monotonic()>=next_send:
                tun.send(frame); next_send=time.monotonic()+.15
            ready,_,_=select.select([endpoint,tun],[],[],.1)
            for sock in ready:
                if sock is endpoint:
                    data,peer=endpoint.recvfrom(65535)
                    if data==FAKE:
                        saw_fake=True
                    else:
                        assert data==test, 'Application datagram changed'
                        # Controlled filter only accepts traffic after the fake.
                        if not fake or saw_fake: endpoint.sendto(data,peer)
                else:
                    reply=payload(tun.recv(65535))
                    if reply is not None:
                        assert reply==test, 'Reverse datagram changed'
                        returned=True
        assert returned, 'UDP tunnel roundtrip timed out'
        assert not fake or saw_fake, 'UDP fake was not emitted'
        print('PASS', 'IPv6' if family==socket.AF_INET6 else 'IPv4',
              'fake-gated UDP' if fake else 'UDP relay', 'through HEV + ByeDPI; payload intact',flush=True)

if __name__=='__main__':
    for fake in [False,True]:
        test_roundtrip(fake,socket.AF_INET)
        if LOCAL6: test_roundtrip(fake,socket.AF_INET6)
    print('SCOPE local assigned-address packet pipeline and controlled filter, not an ISP bypass test')
    if not LOCAL6: print('SKIP native IPv6: no assigned non-link-local IPv6 endpoint')
