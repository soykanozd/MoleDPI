# MoleDPI v1.0.1 — Experimental Connection Reliability Update

**Experimental software. Bugs, connection failures and network interruptions may occur. This release does not certify compatibility or security.**

## What changed
- Added **? → Connection Help** with guidance based on observed DNS, TLS, timeout, remote HTTP and local-engine failures. Failed access checks alone do not prove censorship.
- Ignore stale health results after network or sleep/wake events. Preserve consecutive failures across refreshes so recovery cannot be postponed indefinitely by repeated events.
- Pause health checks and new connection attempts during system sleep. Preserve a working engine after wake/path checks; manual Disconnect and Quit keep priority.
- Generalized user-facing descriptions. Fixed HTTPS control destinations and the limited recovery DNS scope are unchanged; they are not promises of support for particular applications.
- Retained the existing panel, mole artwork, connection animation, engine and privileged-helper security checks.

## Install or update
Download **MoleDPI.dmg**, open it and drag MoleDPI onto Applications. When updating, Disconnect and Quit the old copy first, then replace it. Open MoleDPI from Applications, click the menu-bar helmet and Connect. A changed build may require one administrator approval; repeated connections with the same approved build reuse the helper.

**Apple Silicon · macOS 13+ target.** The build is ad-hoc signed and **not Apple-notarized**. Gatekeeper may block it; see README for Apple's manual-open guidance. Do not disable system security protections.

## Verification and limitations
42 automated checks passed. Three local live HTTPS cycles with injected path/wake controller events preserved the same network-engine session, and PF configuration/proxy settings were restored after disconnect. These injected events are **not physical Wi-Fi changes or actual Mac sleep**. See RELEASE-TESTS.md for scope.

TCP ports 80/443 only. No system-wide UDP/QUIC bypass, anonymity or universal access guarantee. Your public IP remains visible. Limited recovery DNS uses Quad9 over HTTPS; ordinary DNS follows system settings. Clean-Mac installation/removal, physical sleep/Wi-Fi transitions, older macOS coverage, long-duration reliability and independent security review remain pending.

Free and open source; no subscription, paid API or developer-operated relay. Complete corresponding source and bundled dependency notices are included.
