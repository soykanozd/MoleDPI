# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in real HTTP/3 tests. No TCP fallback, cookies, account or traffic capture.

Development dependency only: python -m pip install aioquic==1.3.0
The installed application does not use Python or download this dependency.
Only fixed public test resources are contacted. IPs/response bodies are not logged.
"""
import argparse
import asyncio
import hashlib
import json
import socket
import ssl
import statistics
import time
from pathlib import Path

import certifi
from aioquic.asyncio import QuicConnectionProtocol, connect
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import DataReceived, HeadersReceived
from aioquic.quic.configuration import QuicConfiguration
from aioquic.quic.events import ConnectionTerminated, ProtocolNegotiated

PHASE = "startup"

class HTTP3(QuicConnectionProtocol):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.http = H3Connection(self._quic)
        self.pending = {}
        self.alpn = None

    def quic_event_received(self, event):
        if isinstance(event, ProtocolNegotiated):
            self.alpn = event.alpn_protocol
        if isinstance(event, ConnectionTerminated):
            for future, _, _ in self.pending.values():
                if not future.done():
                    future.set_exception(ConnectionError("QUIC connection terminated"))
        for item in self.http.handle_event(event):
            if isinstance(item, (HeadersReceived, DataReceived)) and item.stream_id in self.pending:
                future, headers, body = self.pending[item.stream_id]
                if future.done():
                    continue
                if isinstance(item, HeadersReceived):
                    headers.extend(item.headers)
                else:
                    body.extend(item.data)
                    if len(body) > 2 * 1024 * 1024:
                        future.set_exception(ValueError("Response exceeded test limit"))
                        continue
                if item.stream_ended:
                    future.set_result((headers, bytes(body)))

    async def get(self, host, resource, expected_status, expected_bytes=None, expected_hash=None):
        assert self.alpn == "h3", "HTTP/3 ALPN was not negotiated"
        stream = self._quic.get_next_available_stream_id()
        future = asyncio.get_running_loop().create_future()
        self.pending[stream] = (future, [], bytearray())
        start = time.monotonic()
        try:
            self.http.send_headers(stream, [(b":method", b"GET"), (b":scheme", b"https"),
                (b":authority", host.encode("ascii")), (b":path", resource.encode("ascii")),
                (b"user-agent", b"MoleDPI-HTTP3-verification"), (b"accept-encoding", b"identity")], end_stream=True)
            self.transmit()
            headers, body = await asyncio.wait_for(future, 15)
            values = dict(headers)
            assert values.get(b":status") == str(expected_status).encode(), "Unexpected HTTP status"
            if b"content-length" in values:
                assert len(body) == int(values[b"content-length"]), "Incomplete response"
            if expected_bytes is not None:
                assert len(body) == expected_bytes, "Unexpected response size"
            if expected_hash is not None:
                assert hashlib.sha256(body).hexdigest() == expected_hash, "Response integrity mismatch"
            return {"ms": round((time.monotonic() - start) * 1000, 2), "bytes": len(body),
                    "sha256": hashlib.sha256(body).hexdigest()}
        finally:
            self.pending.pop(stream, None)


async def session(host, family, operation):
    loop = asyncio.get_running_loop()
    addresses = await loop.getaddrinfo(host, 443, family=family, type=socket.SOCK_DGRAM)
    assert addresses, "No address for requested family"
    config = QuicConfiguration(is_client=True, alpn_protocols=["h3"], server_name=host,
                               idle_timeout=30, max_data=16 * 1024 * 1024,
                               max_stream_data=2 * 1024 * 1024)
    config.verify_mode = ssl.CERT_REQUIRED
    config.load_verify_locations(cafile=certifi.where())
    async with connect(addresses[0][4][0], 443, configuration=config, create_protocol=HTTP3) as client:
        return await operation(client)


async def run(family, duration):
    global PHASE
    # HTTP/3 only: the client has no HTTP-over-TCP implementation.
    results = []
    async def small(client):
        return await client.get("www.google.com", "/generate_204", 204, 0)
    PHASE = "initial_http3_request"
    results.append(await asyncio.wait_for(session("www.google.com", family, small), 25))
    async def downloads(client):
        # Public WebP test image, compared byte-for-byte by digest with the
        # separately verified HTTPS reference. No image is saved or displayed.
        return await asyncio.gather(*(client.get("www.gstatic.com", "/webp/gallery/1.png", 200,
            375229, "a391517dc3962aea18169a1da0dc2c2114dec2e04858eaef33892d0a70452e0d") for _ in range(4)))
    PHASE = "parallel_downloads"
    results.extend(await asyncio.wait_for(session("www.gstatic.com", family, downloads), 35))
    async def multiplex(client):
        measurements = []
        for _ in range(5):
            measurements.extend(await asyncio.gather(*(client.get("www.google.com", "/generate_204", 204, 0)
                                                       for _ in range(5))))
        return measurements
    PHASE = "concurrent_streams"
    batches = await asyncio.wait_for(asyncio.gather(*(session("www.google.com", family, multiplex)
                                                     for _ in range(4))), 90)
    for batch in batches:
        results.extend(batch)
    async def idle_resume(client):
        first = await client.get("www.google.com", "/generate_204", 204, 0)
        await asyncio.sleep(5)
        second = await client.get("www.google.com", "/generate_204", 204, 0)
        return [first, second]
    PHASE = "idle_resume"
    results.extend(await asyncio.wait_for(session("www.google.com", family, idle_resume), 30))
    async def sustained(client):
        measurements = []
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            measurements.append(await client.get("www.google.com", "/generate_204", 204, 0))
            await asyncio.sleep(.75)
        return measurements
    PHASE = "sustained_session"
    results.extend(await asyncio.wait_for(session("www.google.com", family, sustained), duration + 25))
    times = [item["ms"] for item in results]
    return {"result": "pass", "family": "IPv6" if family == socket.AF_INET6 else "IPv4",
            "protocol": "h3", "certificate_verification": True, "tcp_fallback": False,
            "requests": len(results), "response_bytes": sum(item["bytes"] for item in results),
            "median_ms": round(statistics.median(times), 2), "slowest_ms": max(times),
            "sustained_seconds": duration, "concurrent_connections": 4, "streams_per_connection": 5,
            "idle_resume_seconds": 5,
            "mtu_blackhole_or_loss_injection": "not tested", "isp_bypass": "not tested"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipv6", action="store_true")
    parser.add_argument("--duration", type=int, choices=range(0, 301), default=60)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = asyncio.run(run(socket.AF_INET6 if args.ipv6 else socket.AF_INET, args.duration))
    except Exception as error:
        # Never serialize remote errors, addresses, response bodies or local paths.
        report = {"result": "fail", "failure_type": type(error).__name__,
                  "stage": PHASE,
                  "family": "IPv6" if args.ipv6 else "IPv4", "tcp_fallback": False}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)
    raise SystemExit(0 if report["result"] == "pass" else 1)


if __name__ == "__main__":
    main()
