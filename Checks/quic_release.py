# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in installed-app acceptance driver. Run with the HTTP/3 development venv.

Close the ordinary MoleDPI copy first. macOS may request the normal one-time
helper approval for a changed build. No password/token is read by this script.
Reports exclude addresses, network names, process IDs and raw configuration.
"""
import argparse
import asyncio
import json
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import time

from http3_acceptance import run

APP = "/Applications/MoleDPI.app/Contents/MacOS/MoleDPI"
PRIV = "/Library/PrivilegedHelperTools/local.moledpi/"
OWNED = {APP, *(PRIV + name for name in ["moledpi-service", "moledpi-pf", "tpws", "ciadpi",
                                       "tunnel-runner", "moledpi-udp"])}


def configuration():
    return (Path("/etc/pf.conf").read_bytes(),
            subprocess.check_output(["/usr/sbin/scutil", "--proxy"]),
            subprocess.check_output(["/usr/sbin/scutil", "--dns"]))


def owned_usage():
    rows = subprocess.check_output(["/bin/ps", "-axo", "%cpu=,rss=,comm="], text=True).splitlines()
    cpu, rss, count = 0., 0, 0
    for row in rows:
        fields = row.split(None, 2)
        if len(fields) == 3 and fields[2] in OWNED:
            cpu += float(fields[0]); rss += int(fields[1]); count += 1
    return {"cpu_percent": round(cpu, 2), "rss_kib": rss, "processes": count}


async def traffic(duration):
    reports = []
    samples = []
    done = asyncio.Event()
    async def sample():
        while not done.is_set():
            samples.append(owned_usage())
            await asyncio.sleep(1)
    task = asyncio.create_task(sample())
    try:
        for family in [socket.AF_INET, socket.AF_INET6]:
            if family == socket.AF_INET6:
                try:
                    with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as sock:
                        sock.connect(("2606:4700:4700::1111", 443))
                except OSError:
                    reports.append({"family": "IPv6", "result": "not_available", "reason": "no public IPv6 route"})
                    continue
            try:
                report = await run(family, duration)
            except Exception as error:
                report = {"family": "IPv6" if family == socket.AF_INET6 else "IPv4", "result": "fail",
                          "failure_type": type(error).__name__, "tcp_fallback": False}
            reports.append(report)
            print(json.dumps(report), flush=True)
    finally:
        done.set(); await task
    return reports, {"peak_sampled_cpu_percent": max((x["cpu_percent"] for x in samples), default=0),
                     "peak_sampled_rss_kib": max((x["rss_kib"] for x in samples), default=0),
                     "sample_interval_seconds": 1}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=int, choices=range(0, 301), default=60)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if subprocess.run(["/usr/bin/pgrep", "-f", "^" + APP + "$"], stdout=subprocess.DEVNULL).returncode == 0:
        raise SystemExit("Quit the ordinary MoleDPI copy before this opt-in check.")
    before = configuration()
    previous = set(Path("/var/run/moledpi").glob("*/status.json"))
    proc = subprocess.Popen([APP, "--verify-quic-session"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    report = {"isp_bypass": "not tested", "physical_wifi_roaming_or_sleep": "not tested"}
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if selector.select(.25):
                line = proc.stdout.readline()
                if line.strip() == "QUIC_SESSION_READY": break
                if not line and proc.poll() is not None: raise RuntimeError("Verification app exited before readiness")
            if proc.poll() is not None: raise RuntimeError("Verification app did not start")
        else: raise TimeoutError("Normal helper approval or session readiness timed out")
        print("Installed QUIC session ready", flush=True)
        current = set(Path("/var/run/moledpi").glob("*/status.json")) - previous
        assert len(current) == 1, "Expected exactly one owned session"
        session_file = current.pop()
        session = session_file.parent.name
        udp_status = Path("/var/run/moledpi-udp-" + session + "/status.json")
        initial = json.loads(udp_status.read_text())["packets"]
        report["http3"], report["sampled_usage"] = asyncio.run(traffic(args.duration))
        time.sleep(.6)  # Counter publication interval, not an application connect delay.
        end = json.loads(udp_status.read_text())
        assert end["phase"] == "active" and end["packets"] > initial, "Owned UDP routing was not observed"
        report["owned_udp_packet_increase"] = end["packets"] - initial
    except Exception as error:
        report["driver_failure_type"] = type(error).__name__
    finally:
        selector.close()
        if proc.poll() is None:
            try: proc.stdin.write("stop\n"); proc.stdin.flush()
            except BrokenPipeError: pass
        # A timeout is a failure; do not kill arbitrary workers or count forced exit as success.
        try:
            output, _ = proc.communicate(timeout=45)
            report["clean_exit"] = proc.returncode == 0 and "PASS QUIC session stopped and network restored" in output
        except subprocess.TimeoutExpired:
            report["clean_exit"] = False
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and (configuration() != before or owned_usage()["processes"]):
            time.sleep(.15)
        report["network_restored"] = configuration() == before
        report["no_owned_processes_left"] = owned_usage()["processes"] == 0
    report["result"] = "pass" if (not report.get("driver_failure_type") and report["clean_exit"] and
        report["network_restored"] and report["no_owned_processes_left"] and
        any(x["result"] == "pass" for x in report.get("http3", [])) and
        all(x["result"] in ["pass", "not_available"] for x in report.get("http3", []))) else "fail"
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)
    raise SystemExit(0 if report["result"] == "pass" else 1)


if __name__ == "__main__": main()
