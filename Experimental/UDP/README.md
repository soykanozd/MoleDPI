# UDP / QUIC development lab — not an application feature

**Experimental, incomplete, source-only development work. This is not a new MoleDPI release.**

This lab follows the local SOCKS + packet-tunnel architecture used by ByeDPI Android. It builds ByeDPI's UDP fake-packet engine and HEV's macOS packet-to-SOCKS implementation from pinned source. There is no remote server, account, paid API or Apple Developer membership requirement for these tests.

## Run on a development Mac

Apple Silicon and Apple Command Line Tools, Git, Python 3 and the macOS Network/Security frameworks are required. The QUIC certificate fixture uses a recent macOS SDK with in-memory PKCS#12 import. It is a development fixture, not a macOS 13 compatibility claim.

```sh
./Experimental/UDP/build.sh
python3 Experimental/UDP/pipeline_test.py
python3 Experimental/UDP/quic_test.py
```

Dependencies are downloaded as source into the disposable `.build/udp-lab` directory. Nothing is installed in Applications or privileged directories. Tests do not ask for root, create a system tunnel, change PF/DNS/routes, or capture other applications' traffic. The runner uses an inherited Unix socket as a synthetic packet interface. Test destinations belong to this Mac; an active local IPv4 interface is needed. The address is not printed or saved in a report.

## What passed

- Source compilation of ByeDPI, HEV and the native macOS QUIC fixture.
- IPv4 packet → HEV/lwIP → SOCKS5 UDP → ByeDPI → local UDP endpoint, and the reverse path, with payload integrity.
- A controlled local filter that only echoes the real datagram after receiving the configured fake. This verifies the fake-packet mechanism under the test's model; it is not evidence of a real ISP block being bypassed.
- Real QUIC handshake and stream echo, using a temporary, in-memory test identity and a client certificate pin. Both the normal relay and ByeDPI's default UDP-fake mode passed.
- Bounded, clean termination after idle and active traffic. A macOS-only patch fixes upstream ByeDPI's listener-shutdown issue, preserving original timer deadlines while checking for cancellation at most every 250 ms.

The lab's fake TTL is **1**, intentionally limited to the test. It is not a production strategy or a value calibrated for any ISP. A fake sent locally can reach the local fixture; the test does not prove it would cross a remote DPI and expire before the destination. Test QUIC is a real QUIC transport with a private ALPN; it does **not** implement or certify HTTP/3 application semantics.

## Not complete — do not advertise as app support

- No system-wide packet interception or app integration has been implemented.
- No physical macOS utun/PF UDP routing, restoration or crash watchdog has been tested here.
- Native IPv6 is unverified. An initial IPv4-mapped synthetic IPv6 fixture did not pass; that does not establish that native IPv6 is broken or supported.
- No real ISP censorship test was available: the user reports existing voice, game and screen-sharing functions already work. Those sessions were not instrumented.
- Remote QUIC/HTTP3, MTU/fragmentation behavior, concurrent load and long-duration stability remain unverified.

Before integrating into the app, add a bounded macOS capture/forwarding path, preserve the current TCP engine and privileged XPC restrictions, exclude local/control traffic, validate IPv4/IPv6 and MTU behavior, restore only owned settings after disconnect/crash, and demonstrate the strategy on an actually blocked UDP/QUIC path. Forwarding success must remain distinct from censorship-bypass success.

## Sources and licenses

See [UPSTREAM.md](UPSTREAM.md) and [Licenses](Licenses). The lab's own source is GPL-3.0-only; dependency notices are retained. No prebuilt network-engine binaries are fetched or redistributed by this branch.
