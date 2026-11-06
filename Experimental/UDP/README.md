# UDP / QUIC development lab — not an application feature

**The lab remains a separate test harness. Its tested design is now integrated in Native/UDPSession.swift for the public UDP/443 app backend, restricted to public UDP/443. General UDP bypass remains unsupported.**

This lab follows the local SOCKS + packet-tunnel architecture used by ByeDPI Android. It builds ByeDPI's UDP fake-packet engine and HEV's macOS packet-to-SOCKS implementation from pinned source. There is no remote server, account, paid API or Apple Developer membership requirement for these tests.

## Run on a development Mac

Apple Silicon and Apple Command Line Tools, Git, Python 3 and the macOS Network/Security frameworks are required. The QUIC certificate fixture uses a recent macOS SDK with in-memory PKCS#12 import. It is a development fixture, not a macOS 13 compatibility claim. Executables are explicitly ad-hoc signed and verified after building; they are not Apple-notarized.

```sh
./Experimental/UDP/build.sh
python3 Experimental/UDP/pipeline_test.py
python3 Experimental/UDP/quic_test.py
```

Dependencies are downloaded as source into the disposable `.build/udp-lab` directory. Nothing is installed in Applications or privileged directories. The two default tests above do not ask for root, create a system tunnel, change PF/DNS/routes, or capture other applications' traffic. The runner uses an inherited Unix socket as a synthetic packet interface. Test destinations belong to this Mac; an active local IPv4 interface is needed. The address is not printed or saved in a report.

## Opt-in physical macOS routing test

```sh
python3 Experimental/UDP/physical_test.py
python3 Experimental/UDP/physical_test.py --ipv6
```

This separate test requests administrator authorization and creates a real temporary utun plus a dedicated PF anchor. Its rule matches **only the current user's UDP to this Mac's assigned local address and one test port**. It does not capture arbitrary applications or internet destinations. No default route, DNS/proxy preference, installed app/helper, global PF ruleset or sudoers entry is changed. Rules create no PF states, so cleanup does not flush other applications' states. Only the test's PF enable reference is released.

Generated binaries are first copied out of protected Documents storage, then hash-verified in a root-private staging directory. The supervisor watches caller/worker liveness. A separate root launcher invokes journal-based recovery if the supervisor itself is killed; recovery verifies root ownership, the session UUID and executable paths before stopping owned processes. Recovery artifacts are retained on failure rather than silently discarded. The test is narrow development code, not a reviewed production privileged API.

Normal stop, engine crash, tunnel crash, caller loss, a real certificate-pinned QUIC session and supervisor crash/recovery all passed. Each scenario verified positive PF counters and matching PF file, proxy/DNS snapshots and interface inventory after cleanup. Both the controlled filter and QUIC endpoint run on this Mac. **These are real OS packet-routing tests, not real ISP censorship tests.** The same six scenarios also passed with native IPv6 physical capture, using a link-local gateway scoped to the temporary interface.

## What passed

- Source compilation of ByeDPI, HEV and the native macOS QUIC fixture.
- IPv4 and native IPv6 packet → HEV/lwIP → SOCKS5 UDP → ByeDPI → local assigned-address endpoint, and the reverse path, with payload integrity. IPv6 cases are explicitly skipped if no non-link-local local address is assigned.
- A controlled local filter that only echoes the real datagram after receiving the configured fake. This verifies the fake-packet mechanism under the test's model; it is not evidence of a real ISP block being bypassed.
- Real QUIC handshake and stream echo, using a temporary, in-memory test identity and a client certificate pin. Both IPv4 and IPv6 passed with the normal relay and ByeDPI's default UDP-fake mode.
- Bounded, clean termination after idle and active traffic. A macOS-only patch fixes upstream ByeDPI's listener-shutdown issue, preserving original timer deadlines while checking for cancellation at most every 250 ms.

The lab's fake TTL is **1**, intentionally limited to the test. It is not a production strategy or a value calibrated for any ISP. A fake sent locally can reach the local fixture; the test does not prove it would cross a remote DPI and expire before the destination. Test QUIC is a real QUIC transport with a private ALPN; it does **not** implement or certify HTTP/3 application semantics.

## Not complete — do not advertise as app support

- The app integration processes public UDP/443 only. Other UDP remains direct; the lab is not a general production networking API.
- Physical macOS IPv4 utun/PF routing and the narrow lab crash recovery are tested. The installed app has separate lifecycle/IPC integration and live tests; broader routing beyond public UDP/443 remains outside scope.
- Native IPv6 packet-pipeline UDP/QUIC tests passed. The earlier IPv4-mapped fixture was replaced with a valid native assigned IPv6 endpoint; physical IPv6 PF/utun routing passed the six narrow test scenarios too.
- No real ISP censorship test was available: the user reports existing voice, game and screen-sharing functions already work. Those sessions were not instrumented.
- Installed-app remote HTTP/3, concurrent load and bounded sustained-session tests are documented in ../../RELEASE-TESTS.md. Artificial packet-loss/MTU blackhole and 24-hour stability remain unverified.

Before integrating into the app, add a bounded macOS capture/forwarding path, preserve the current TCP engine and privileged XPC restrictions, exclude local/control traffic, validate IPv4/IPv6 and MTU behavior, restore only owned settings after disconnect/crash, and demonstrate the strategy on an actually blocked UDP/QUIC path. Forwarding success must remain distinct from censorship-bypass success.

## Sources and licenses

See [UPSTREAM.md](UPSTREAM.md), the [additional reference review](REFERENCES.md) and [Licenses](Licenses). The lab's own source is GPL-3.0-only; dependency notices are retained. No prebuilt network-engine binaries are fetched or redistributed by this branch.
