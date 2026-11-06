# MoleDPI v1.1.0-beta — Experimental QUIC Integration

**Experimental. Bugs, disconnections and interruptions may occur. Not Apple-notarized.**

Connect now includes source-built local UDP/443 routing on IPv4/IPv6, alongside the existing TCP engine. ByeDPI adds fake packets only for plausible QUIC v1/v2 Initial datagrams; other UDP/443 is relayed unchanged and all other UDP ports remain direct. The proxy runs as nobody; the restricted root helper owns the temporary PF anchor and utun. No remote server, subscription or paid API is used.

Disconnect and Quit remove routing before stopping the owned engines. Independent recovery is included for unexpected worker exit. The panel and mole artwork are unchanged.

Apple Silicon, macOS 13 deployment target; verified locally on a recent macOS only. Quit the old app, open MoleDPI.dmg and drag MoleDPI into Applications. Approve the updated helper if macOS asks. Do not disable Gatekeeper. For advanced TCP-only fallback, Quit and launch `open -a MoleDPI --args --tcp-only`.

Scope: public UDP/443 only. This is not general UDP censorship bypass or anonymity. TTL 8 is not calibrated to every ISP. A real QUIC handshake with system TLS verification is a transport test, not proof of bypassing a blocked ISP path. Full HTTP/3 application compatibility, long-term stability, clean-Mac installation and independent security review remain unverified. See RELEASE-TESTS.md for actual validation.
