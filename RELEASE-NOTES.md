# MoleDPI v1.2.0 — HTTP/3 Verification and Clear Support Scope

A regular release with local TCP 80/443 and public UDP/443 QUIC processing. The general experimental banner is replaced by a network-compatibility notice. The existing DPI engines, packet strategy, permission model, restoration checks and mole design are preserved.

- New opt-in tests use real certificate-verified HTTP/3 with no TCP fallback, complete digest-checked transfers, concurrent streams/connections, idle/resume and a sustained session. An installed-app endurance mode adds per-cycle measurements without private data. Python is only a development-test dependency and is not shipped or needed to run MoleDPI.
- Existing safe TCP fallback, reviewed issue reports, Connect/Disconnect/Quit and local helper approval remain. Changed builds can require one approval; repeated connections reuse the approved build.
- Documentation and compatibility forms now describe the actual UDP/443 scope and bundled source dependencies consistently. Final installed build: 107 HTTP/3 requests and eight Quit scenarios passed. A separate five-minute acceptance run completed 483 HTTP/3 requests. The endurance run was deliberately stopped after 62 completed cycles; the 100-cycle target was not completed. See RELEASE-TESTS.md and the attached verification report for measured results.

**Limits remain explicit:** other UDP ports are direct; public IP remains visible. This network had no public IPv6 route or known blocked QUIC target, so neither public IPv6 nor real ISP-block bypass is claimed. Fixed fake TTL 8 is not ISP-calibrated. No 24-hour soak, broad older-OS certification or independent security audit is claimed.

Apple Silicon; macOS 13 deployment target. Ad-hoc signed and **not Apple-notarized**. Follow the README's macOS installation guidance; do not disable Gatekeeper. Disconnect and Quit before replacing the app in Applications. No server, subscription or paid API is added.
