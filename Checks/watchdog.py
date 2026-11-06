#!/usr/bin/env python3
"""Opt-in test of an installed and approved build: restart, connect and crash this test client."""
import hashlib
import json
from pathlib import Path
import subprocess
import time

app = '/Applications/MoleDPI.app/Contents/MacOS/MoleDPI'
journal_dir = Path('/var/run/moledpi')
old = set(journal_dir.glob('*/status.json'))
def config():
    return hashlib.sha256(Path('/etc/pf.conf').read_bytes()).digest(), subprocess.check_output(['/usr/sbin/scutil','--proxy'])
before = config()
client = subprocess.Popen([app, '--verify-network'])
try:
    deadline = time.monotonic() + 90
    active = None
    while client.poll() is None and time.monotonic() < deadline:
        for path in set(journal_dir.glob('*/status.json')) - old:
            status = json.loads(path.read_bytes())
            if status.get('phase') == 'active':
                # Only kill the client whose own worker wrote this exact journal.
                worker = subprocess.check_output(['/bin/ps','-o','command=','-p',str(status['pid'])],text=True)
                if str(client.pid) in worker.split() and path.parent.name in worker.split():
                    active = path
                    break
        if active:
            break
        time.sleep(.05)
    assert active, 'Restarted client did not establish its own active PF session'
finally:
    if client.poll() is None:
        client.kill()
    client.wait()
deadline = time.monotonic() + 12
while time.monotonic() < deadline:
    status = json.loads(active.read_bytes())
    if status.get('phase') == 'stopped' and 'pfToken' not in status:
        break
    time.sleep(.15)
else:
    raise RuntimeError('PF recovery did not finish after client death')
assert config() == before
print('PASS: restarted client used installed service; watchdog restored network after SIGKILL')

end = time.monotonic()+8
names = ['/Library/PrivilegedHelperTools/local.moledpi/'+n for n in ['moledpi-pf','tpws','moledpi-udp','ciadpi','tunnel-runner','moledpi-service']]
while time.monotonic()<end:
    commands=subprocess.check_output(['/bin/ps','-axo','comm='],text=True).splitlines()
    if not any(line.strip() in names for line in commands): break
    time.sleep(.1)
else: raise RuntimeError('Owned engines remained after client crash')
print('PASS all TCP/UDP/tunnel processes exited after app crash')
