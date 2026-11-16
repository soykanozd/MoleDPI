# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in real root-worker crash test. macOS administrator approval is required.
Only the authenticated test app's exact worker PID/UUID is eligible for SIGKILL.
No packet capture or arbitrary process termination; no raw details in reports.
"""
import json
import os
from pathlib import Path
import selectors
import shlex
import subprocess
import time
import uuid

from quic_release import APP, PRIV, configuration, owned_usage


def main():
    if subprocess.run(["pgrep","-f","^"+APP+"$"],stdout=subprocess.DEVNULL).returncode == 0:
        raise SystemExit("Quit the ordinary MoleDPI copy first.")
    before = configuration()
    previous = set(Path("/var/run/moledpi").glob("*/status.json"))
    child = subprocess.Popen([APP,"--verify-quic-session"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL,text=True,bufsize=1)
    report = {}
    selector = selectors.DefaultSelector(); selector.register(child.stdout,selectors.EVENT_READ)
    try:
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            if selector.select(.25):
                line=child.stdout.readline()
                if line.strip()=="QUIC_SESSION_READY": break
            if child.poll() is not None: raise RuntimeError("Test client exited before readiness")
        else: raise TimeoutError("Test readiness timed out")
        new=set(Path("/var/run/moledpi").glob("*/status.json"))-previous
        assert len(new)==1
        status_file=new.pop(); session=status_file.parent.name
        assert str(uuid.UUID(session)).upper()==session
        state=json.loads(status_file.read_text()); worker=state["pid"]
        assert type(worker) is int and worker>1 and state["uid"]==os.getuid()
        assert status_file.stat().st_uid==0 and not status_file.stat().st_mode & 0o022
        prefix=PRIV+"moledpi-pf "+str(os.getuid())+" "+str(child.pid)+" "+session+" "
        # Revalidate the command, uid and UUID immediately before signalling.
        script="\n".join(["set -eu",
            "[ \"$(/bin/ps -p "+str(worker)+" -o uid= | /usr/bin/tr -d ' ')\" = '0' ]",
            "cmd=$(/bin/ps -p "+str(worker)+" -o command=)",
            "case \"$cmd\" in "+shlex.quote(prefix)+"*) ;; *) exit 75;; esac",
            "/bin/kill -KILL "+str(worker)])
        quoted='"'+script.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')+'"'
        subprocess.run(["/usr/bin/osascript","-e","do shell script "+quoted+
            ' with prompt "Test recovery of only MoleDPI’s own network worker." with administrator privileges'],
            check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=120)
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            state=json.loads(status_file.read_text())
            if state.get("phase")=="stopped" and "pfToken" not in state: break
            time.sleep(.05)
        else: raise RuntimeError("Automatic worker repair did not finish")
        report["automatic_worker_crash_recovery"]=True
    except Exception as error:
        report["failure_type"]=type(error).__name__
    finally:
        selector.close()
        if child.poll() is None:
            try: child.stdin.write("stop\n"); child.stdin.flush()
            except BrokenPipeError: pass
        try:
            output,_=child.communicate(timeout=60)
            report["clean_test_client_exit"]=child.returncode==0 and "PASS QUIC session stopped and network restored" in output
        except subprocess.TimeoutExpired: report["clean_test_client_exit"]=False
        deadline=time.monotonic()+8
        while time.monotonic()<deadline and (configuration()!=before or owned_usage()["processes"]): time.sleep(.15)
        report["network_restored"]=configuration()==before
        report["no_owned_processes_left"]=owned_usage()["processes"]==0
    web=subprocess.run(["/usr/bin/curl","--disable","--proxy","","--noproxy","*","--fail","--silent",
                        "--output","/dev/null","--max-time","12","https://example.com/"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    report["https_after_recovery"]=web.returncode==0
    report["result"]="pass" if ("failure_type" not in report and all(report.values())) else "fail"
    Path(".build/worker-crash-report.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report),flush=True)
    raise SystemExit(0 if report["result"]=="pass" else 1)


if __name__=="__main__": main()
