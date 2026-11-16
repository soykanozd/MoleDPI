# MoleDPI v1.2.1 — Reliability and Release Hardening

This release preserves the existing interface, mole animations, TCP/UDP engines and one-approval-per-build helper model. No paid service, telemetry or new background agent is added.

- Fixed a reproduced content-CDN incompatibility: the OOB TCP strategy now uses ordinary splitting for the affected CDN suffix. The preflight and privileged worker share the same strategy definition; API and CDN TLS checks supplement the existing page checks.
- A strategy that passes the local SOCKS probe but fails the real transparent PF check is now safely cleaned up and replaced with the next fixed strategy. Failed cleanup blocks fallback. No failed transparent strategy is saved as verified.
- Partial health failures now show **Limited Access** instead of a false all-clear. Existing connections are preserved rather than restarted for one remote outage. A verified TLS error response from the API/CDN root counts only as transport reachability, not a successful login or game session.
- UDP idle mappings last 60 seconds instead of 2 seconds, avoiding premature idle-session expiry. This does not promise unrestricted UDP bypass.
- Disconnect now waits for the existing automatic repair to finish before requesting another repair, fixing a reproduced cleanup/worker-exit race.
- Privileged command execution now bounds time, input and output, drains pipes without blocking and verifies owned-process termination. Routing is removed before its engine is stopped; failed rule removal preserves the engine for recovery.
- Independent UDP repair joins a live guardian before replaying its journal. The service bounds repair commands and permits an explicit retry after a failed automatic repair instead of leaving a dead-worker admission lock. XPC waiters have deadlines and tolerate delayed duplicate replies.
- Late QUIC status results cannot overwrite newer offline/sleep events or publish Connected after an offline startup. Cancellation escalates only for an unresponsive process launched by the app.
- Regular builds offer published regular updates; beta builds retain their beta channel. Release links must be canonical, belong to this repository and match their advertised version.
- The uninstaller refuses removal while an owned network worker or pending recovery record needs its helper. Build/package verification checks signatures, helper hashes/identity, architecture, version and included source before producing a DMG.

See RELEASE-TESTS.md and the accompanying verification JSON for actual checks and remaining limits. Local TCP 80/443 and public UDP/443 are the supported scope; other UDP remains direct. Real ISP-blocked QUIC bypass, public IPv6 internet on the available test network, 24-hour soak, older-OS compatibility and independent security review are not certified.

Apple Silicon, macOS 13 deployment target. Ad-hoc signed, **not Apple-notarized**. Follow the README's installation guidance; do not disable Gatekeeper. Disconnect and Quit before updating. A changed build may need one macOS helper approval; repeated connections reuse that approved build.
