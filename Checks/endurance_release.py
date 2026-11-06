# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in 100-cycle test of the installed authenticated app. No traffic capture.
Run with the same development venv as quic_release.py, after quitting the GUI.
"""
import json
from pathlib import Path
import re
import statistics
import subprocess
import time

from quic_release import APP, configuration, owned_usage


def main():
    if subprocess.run(["pgrep", "-f", "^" + APP + "$"], stdout=subprocess.DEVNULL).returncode == 0:
        raise SystemExit("Quit the ordinary MoleDPI copy first.")
    before = configuration()
    destination = Path(".build/endurance-native.log")
    samples = []
    with destination.open("w") as output:
        proc = subprocess.Popen([APP, "--verify-endurance"], stdout=output, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 900
        while proc.poll() is None and time.monotonic() < deadline:
            samples.append(owned_usage())
            time.sleep(.5)
        if proc.poll() is None:
            # Kill only this known test child. This is a failed test and exercises
            # guardian recovery; it is never counted as a normal clean exit.
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=5)
    contents = destination.read_text()
    durations = [float(x) for x in re.findall(r"MEASURE connect_ms ([0-9.]+)", contents)]
    cycles = len(re.findall(r"PASS: verified HTTPS and restored network, cycle [0-9]+", contents))
    settle = time.monotonic() + 8
    while time.monotonic() < settle and (configuration() != before or owned_usage()["processes"]):
        time.sleep(.15)
    report = {"cycles": cycles, "verified_connections": len(durations), "clean_exit": proc.poll() == 0,
              "network_restored": configuration() == before,
              "no_owned_processes_left": owned_usage()["processes"] == 0,
              "connect_mean_ms": round(statistics.mean(durations), 2) if durations else None,
              "connect_median_ms": round(statistics.median(durations), 2) if durations else None,
              "connect_slowest_ms": max(durations) if durations else None,
              "peak_sampled_cpu_percent": max((x["cpu_percent"] for x in samples), default=0),
              "peak_sampled_rss_kib": max((x["rss_kib"] for x in samples), default=0),
              "sample_interval_seconds": .5, "physical_network_changes": "not tested"}
    report["result"] = "pass" if (cycles == len(durations) == 100 and report["clean_exit"] and
        report["network_restored"] and report["no_owned_processes_left"]) else "fail"
    Path(".build/endurance-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)
    raise SystemExit(0 if report["result"] == "pass" else 1)


if __name__ == "__main__": main()
