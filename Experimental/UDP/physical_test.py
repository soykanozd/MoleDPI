#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in real macOS utun/PF test. One administrator authorization is required.
Captures only this user's UDP to this Mac's dedicated test endpoint. No default
route, DNS, global PF rules or installed MoleDPI files are modified.
"""
from pathlib import Path
import hashlib
import json
import os
import select
import shutil
import shlex
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from pipeline_test import BUILD, LOCAL
from quic_test import openssl

FAKE=b'MOLEDPI_PHYSICAL_LAB_FAKE'
SCENARIOS=['normal','crash-engine','crash-tunnel','caller-loss','quic','crash-supervisor']

def configuration():
    # Snapshots stay in memory and are never printed or uploaded.
    return (Path('/etc/pf.conf').read_bytes(),
            subprocess.check_output(['/usr/sbin/scutil','--proxy']),
            subprocess.check_output(['/usr/sbin/scutil','--dns']),
            set(socket.if_nameindex()))

def apple_string(value):
    return '"'+value.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')+'"'

def main():
    before=configuration()
    uid=os.getuid()
    assert uid>=500 and os.geteuid()!=0, 'Start as the normal signed-in user'
    clients=[]; launcher=None; quic_server=None
    with tempfile.TemporaryDirectory(prefix='moledpi-physical-',dir='/private/tmp') as temporary, socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as endpoint:
        folder=Path(temporary); endpoint.bind((LOCAL,0));endpoint.settimeout(.1)
        finished=threading.Event()
        token=b'LAB-'+os.urandom(24)
        passed=set()
        def echo():
            while not finished.is_set():
                try: data,peer=endpoint.recvfrom(2048)
                except socket.timeout: continue
                if data==FAKE: passed.add(peer)
                elif data==token and peer in passed: endpoint.sendto(data,peer)
        worker=threading.Thread(target=echo,daemon=True);worker.start()
        openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',folder/'key.pem','-out',folder/'cert.pem','-subj','/CN=localhost','-days','1')
        openssl('x509','-in',folder/'cert.pem','-outform','DER','-out',folder/'cert.der')
        openssl('pkcs12','-export','-inkey',folder/'key.pem','-in',folder/'cert.pem','-out',folder/'identity.p12','-passout','pass:local-test')
        quic_server=subprocess.Popen([str(BUILD/'quic-fixture'),'server',str(folder/'identity.p12'),LOCAL],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
        assert select.select([quic_server.stdout],[],[],5)[0], 'QUIC fixture startup timed out'
        ready=quic_server.stdout.readline().strip()
        assert ready.startswith('READY '), 'QUIC fixture identity failed'
        quic_port=int(ready.split()[1])
        sessions=[]
        for mode in SCENARIOS:
            client=subprocess.Popen(['/bin/sleep','180'])
            clients.append(client)
            nonce=str(uuid.uuid4()).upper()
            control=folder/(nonce+'.control')
            control.write_text(nonce+' wait');control.chmod(0o600)
            sessions.append((mode,client,nonce,control,quic_port if mode=="quic" else endpoint.getsockname()[1]))
        q=shlex.quote
        script=['set -eu','export PATH=/usr/bin:/bin:/usr/sbin:/sbin','umask 077',
                'stage=$(mktemp -d /private/var/root/moledpi-udp-lab.XXXXXXXX)',
                "complete=0",
                'trap \'if [ "$complete" = 1 ]; then rm -rf "$stage"; else printf "Root recovery artifacts retained: %s\\n" "$stage" >&2; fi\' EXIT']
        for name,source in [('physical-supervisor',BUILD/'physical-supervisor'),('ciadpi',BUILD/'byedpi/ciadpi'),('tunnel-runner',BUILD/'tunnel-runner')]:
            payload=folder/name
            shutil.copyfile(source,payload)
            payload.chmod(0o500)
            digest=hashlib.sha256(payload.read_bytes()).hexdigest()
            script += ['/usr/bin/install -m 500 '+q(str(payload))+' "$stage/'+name+'"',
                       '[ "$(/usr/bin/shasum -a 256 "$stage/'+name+'" | /usr/bin/cut -d\' \' -f1)" = '+q(digest)+' ]']
        for mode,client,nonce,control,target_port in sessions:
            # Every value is separately shell-quoted; the root executable validates them.
            argv=[str(uid),str(os.getpid()),str(client.pid),LOCAL,str(target_port),nonce,str(control),mode]
            command='"$stage/physical-supervisor" '+' '.join(q(value) for value in argv)
            if mode=='crash-supervisor':
                script += ['if '+command+'; then exit 90; else "$stage/physical-supervisor" --recover '+q(nonce)+'; fi']
            else:
                script += ['if '+command+'; then :; else "$stage/physical-supervisor" --recover '+q(nonce)+'; exit 91; fi']
        script += ['complete=1']
        root_script='\n'.join(script)
        try:
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as direct:
                direct.settimeout(.15);direct.connect(endpoint.getsockname());direct.send(token)
                try: direct.recv(2048)
                except socket.timeout: pass
                else: raise AssertionError('Controlled filter incorrectly allowed a direct packet')
            launcher=subprocess.Popen(['/usr/bin/osascript','-e','do shell script '+apple_string(root_script)+' with administrator privileges'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            total_end=time.monotonic()+150
            for mode,client,nonce,control,target_port in sessions:
                state=Path('/var/run/moledpi-udp-lab-'+nonce)/'status.json'
                def read():
                    try:
                        data=json.loads(state.read_text())
                        assert state.stat().st_uid==0 and data['session']==nonce
                        return data
                    except (FileNotFoundError,PermissionError): return {}
                deadline=min(total_end,time.monotonic()+100)
                while time.monotonic()<deadline:
                    value=read()
                    if value.get('phase') in ['active','failed']: break
                    if launcher.poll() is not None:
                        stdout,stderr=launcher.communicate()
                        (BUILD/'physical-launcher.log').write_text(stdout+'\n'+stderr)
                        raise AssertionError('Administrator authorization or physical supervisor failed; local stage log saved')
                    time.sleep(.05)
                else: raise AssertionError('Physical startup/authorization timed out')
                assert value.get('phase')=='active', 'Physical setup failed: '+str(value.get('problem','unknown'))
                if mode=='quic':
                    result=subprocess.run([str(BUILD/'quic-fixture'),'client',str(target_port),str(folder/'cert.der'),LOCAL],capture_output=True,text=True,timeout=18)
                    assert result.returncode==0 and result.stdout.startswith('PASS real QUIC'), 'Physical certificate-pinned QUIC handshake failed'
                else:
                    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as probe:
                        probe.connect(endpoint.getsockname());probe.settimeout(.2)
                        end=time.monotonic()+5;received=False
                        while time.monotonic()<end:
                            probe.send(token)
                            try: response=probe.recv(2048)
                            except socket.timeout: continue
                            assert response==token
                            received=True;break
                        if not received:
                            control.write_text(nonce+' stop')
                            raise AssertionError('No transparent UDP reply through physical PF/utun pipeline')
                counter_end=time.monotonic()+3
                while time.monotonic()<counter_end and read().get('packets',0)==0: time.sleep(.05)
                assert read().get('packets',0)>0, 'PF did not count test packets'
                if mode=='caller-loss':
                    client.terminate();client.wait(timeout=2)
                else: control.write_text(nonce+(' stop' if mode in ['normal','quic'] else ' crash'))
                end=time.monotonic()+12
                while time.monotonic()<end:
                    value=read()
                    if value.get('phase') in ['stopped','failed']: break
                    time.sleep(.05)
                control.write_text(nonce+' ack')
                assert value.get('phase')=='stopped' and value.get('packets',0)>0, 'Physical cleanup/scenario failed: '+str(value.get('problem','unknown'))
                assert configuration()==before, 'PF file, DNS, proxy or interface set differs after cleanup'
                print('PASS real macOS PF/utun capture, '+('certificate-pinned QUIC' if mode=='quic' else 'fake-gated UDP')+' and restored settings:',mode,flush=True)
            stdout,stderr=launcher.communicate(timeout=12)
            assert launcher.returncode==0, 'Root supervisor reported a failure'
            print('PASS root supervisors and owned network engines exited')
        finally:
            # Let the root watchdog remove its own rules before temporary controls disappear.
            for _,client,nonce,control,_ in sessions:
                control.write_text(nonce+' stop')
                if client.poll() is None: client.terminate()
                client.wait(timeout=2)
            if quic_server is not None:
                if quic_server.poll() is None: quic_server.terminate()
                quic_server.wait(timeout=3)
            finished.set();worker.join(timeout=1)
            if launcher is not None and launcher.poll() is None:
                try: launcher.communicate(timeout=15)
                except subprocess.TimeoutExpired:
                    print('ATTENTION root test cleanup/authorization is still pending; do not force-kill its supervisor',flush=True)

if __name__=='__main__':main()
