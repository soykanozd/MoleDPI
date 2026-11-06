# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in, unprivileged MTU-boundary payload test of production-built engines.
Synthetic tunnel FD and local endpoints only; no PF, routes or DNS changes.
Not a real internet MTU/fragmentation or packet-loss test.
"""
from pathlib import Path
import select
import shutil
import socket
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Experimental/UDP"))
import pipeline_test as lab


def main():
    root = Path(__file__).resolve().parents[1]
    stage = root / ".build/udp-size-test"
    (stage / "byedpi").mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / ".build/native/ciadpi", stage / "byedpi/ciadpi")
    shutil.copy2(root / ".build/native/tunnel-runner", stage / "tunnel-runner")
    lab.BUILD = stage
    for family in [socket.AF_INET, socket.AF_INET6]:
        if family == socket.AF_INET6 and not lab.LOCAL6:
            # ::1 is the lwIP stack's own loopback, not a forwardable remote
            # destination. Do not substitute it for an assigned IPv6 endpoint.
            print("SKIP synthetic IPv6 sizes: no assigned non-loopback endpoint", flush=True)
            continue
        sizes = [1, 64, 512, 1200, 1232, 1400, 1452] + ([1472] if family == socket.AF_INET else [])
        with socket.socket(family, socket.SOCK_DGRAM) as endpoint, lab.pipeline(False) as (tun, engine, tunnel):
            endpoint.bind((lab.LOCAL6 if family == socket.AF_INET6 else lab.LOCAL, 0))
            for index, size in enumerate(sizes):
                value = bytes(i % 251 for i in range(size))
                frame = lab.packet(value, endpoint.getsockname()[1], family, 35200 + index)
                deadline = time.monotonic() + 5
                next_send = 0
                returned = False
                while time.monotonic() < deadline and not returned:
                    assert engine.poll() is None and tunnel.poll() is None
                    if time.monotonic() >= next_send:
                        tun.send(frame); next_send = time.monotonic() + .2
                    ready, _, _ = select.select([endpoint, tun], [], [], .1)
                    for source in ready:
                        if source is endpoint:
                            received, peer = endpoint.recvfrom(65535)
                            assert received == value, "Outbound datagram changed"
                            endpoint.sendto(received, peer)
                        else:
                            received = lab.payload(tun.recv(65535))
                            if received is not None:
                                assert received == value, "Inbound datagram changed"
                                returned = True
                assert returned, "Payload-size roundtrip failed"
                print("PASS synthetic", "IPv6" if family == socket.AF_INET6 else "IPv4",
                      "payload", size, "bytes intact", flush=True)
    print("SCOPE production engines with synthetic packets; no physical/public IPv6 or blackhole claim")


if __name__ == "__main__": main()
