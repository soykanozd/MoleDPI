# UDP / QUIC scope — v1.2.0

## What the app does

Connect starts the TCP engine plus a local QUIC backend. The signed-in user's public UDP/443 is routed over IPv4/IPv6 through HEV and source-built ByeDPI. Fake injection is limited to plausible QUIC v1/v2 Initial packets. Other UDP/443 payloads are relayed unchanged. Other UDP ports, other users and private/LAN destinations stay on the normal network. The proxy drops to nobody; the root guardian owns PF/utun and cleanup. This is not a remote relay, VPN or anonymity service.

The fake TTL is fixed at 8. It is neither automatically calibrated nor proven suitable for every ISP. A normal release label is not a guarantee that this strategy bypasses a particular filter. No actual blocked QUIC path was available on the test network.

## Verification

`Checks/http3_acceptance.py` uses aioquic only as an opt-in developer test client. It negotiates h3 with certificate verification and implements no TCP fallback. Tests include a complete public test image with a fixed reference SHA-256, four simultaneous transfers, four concurrent connections with five multiplexed requests each, a five-second idle/resume check and a bounded sustained session. Reports contain aggregate timings/counts, never response bodies or client addresses.

`Checks/quic_release.py` launches the installed authenticated app with a fixed-policy test session, observes an increase in its own UDP PF counter, checks for a clean exit, compares PF/proxy/DNS snapshots and verifies that owned processes exited. A missing public IPv6 route is recorded as unavailable. This differs from the previously completed narrow physical IPv6 lab tests; lab success is not a public IPv6 internet test.

See [the release verification report](../RELEASE-TESTS.md) for actual counts, timings and limitations. Tests are opt-in and use no paid service or account. Instructions are in [BUILDING.md](../BUILDING.md). Python and its dependencies are not shipped or required by the app.

## Remaining limits

- No real ISP-blocked QUIC comparison or automatic TTL calibration.
- Public IPv6 internet testing requires a network with working IPv6.
- No artificial packet-loss, MTU-blackhole or 24-hour soak certification.
- Physical Wi-Fi roaming, system sleep, clean-Mac installation and older macOS versions need broader testing.
- No general UDP/voice/game bypass promise. Forwarding and ordinary access do not prove censorship bypass.
- Independent security review and Apple notarization remain pending.

Connected means the configured HTTPS checks and local engine/session verification passed. It does not mean every UDP/QUIC destination was tested. If the QUIC backend cannot start or exits, safe verified cleanup preserves working TCP and the panel identifies TCP fallback. Failed cleanup stops the session.

Quit before an advanced TCP-only launch: `open -a MoleDPI --args --tcp-only`. No arbitrary destinations, helper executables or PF rules can be supplied by these flags. Root helper hashes, peer authentication and restoration checks are unchanged.
