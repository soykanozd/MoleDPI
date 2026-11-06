"""Opt-in, real macOS application termination tests. Close the other GUI copy first."""
import json
from pathlib import Path
import socket
import subprocess
import time

app = '/Applications/MoleDPI.app/Contents/MacOS/MoleDPI'
priv = '/Library/PrivilegedHelperTools/local.moledpi/'
runtime = Path('/var/run/moledpi')
def config():
    return (Path('/etc/pf.conf').read_bytes(),
            subprocess.check_output(['/usr/sbin/scutil', '--proxy']),
            subprocess.check_output(['/usr/sbin/scutil', '--dns']))
def workers():
    commands = subprocess.check_output(['/bin/ps', '-axo', 'comm='], text=True).splitlines()
    return [x.strip() for x in commands if x.strip() in
            [app, priv+'moledpi-service', priv+'moledpi-pf', priv+'tpws',priv+'moledpi-udp',priv+'ciadpi',priv+'tunnel-runner',
             '/Applications/MoleDPI.app/Contents/Resources/tpws']]
for scenario in ['connected', 'idle', 'immediate', 'connecting', 'starting-worker', 'disconnecting', 'engine-failure', 'connected']:
    before = config()
    old = set(runtime.glob('*/status.json'))
    blocker = None
    if scenario == 'engine-failure':
        blocker = socket.socket()
        blocker.bind(('127.0.0.1',18081))
        blocker.listen()
    try:
        # Timeout is a test failure, never count a forced kill as a clean exit.
        p = subprocess.Popen([app, '--verify-quit', scenario])
        assert p.wait(timeout=120) == 0, scenario
    finally:
        if blocker: blocker.close()
    assert before == config(), 'Configuration changed: ' + scenario
    new = set(runtime.glob('*/status.json')) - old
    if scenario in ['connected','starting-worker','disconnecting']: assert new, 'Missing worker journal'
    for path in new:
        data = json.loads(path.read_text())
        assert data['phase'] in ('stopped','failed') and 'pfToken' not in data, data
    deadline = time.monotonic()+7
    while workers() and time.monotonic()<deadline: time.sleep(.15)
    assert not workers(), workers()
    subprocess.run(['/usr/bin/curl','--disable','--proxy','','--fail','--silent','--output','/dev/null',
                    '--max-time','12','https://example.com/'], check=True)
    print('PASS',scenario,'process exit, network restored, HTTPS reachable, no workers', flush=True)
