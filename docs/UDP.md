# UDP/QUIC integration status — v1.1.0-beta

Connect starts the TCP engine plus an experimental local QUIC backend. The signed-in user's public UDP/443 is routed over IPv4/IPv6 through HEV and source-built ByeDPI. Fake injection is limited to plausible QUIC v1/v2 Initial packets. Other UDP/443 payloads are relayed unchanged; other UDP ports and private/LAN destinations remain on the normal network. The proxy drops to nobody; the root guardian owns PF/utun and cleanup.

The installed app passed ten Connect/Disconnect cycles with verified HTTPS and restored networking, a real public QUIC handshake with system TLS verification and positive owned UDP PF counters, eight Quit cases and app-SIGKILL cleanup with no owned engines left. Earlier lab tests cover twelve narrow physical IPv4/IPv6 routing/crash cases. No real ISP-blocked path was available. These are not guarantees of HTTP/3 semantics, arbitrary UDP bypass or universal voice/game support. TTL 8 is a fixed experimental choice, not ISP calibration. IP addresses remain visible.

The panel is unchanged. Connected still means the configured HTTPS checks and local engine/session verification passed, not every website or UDP service. Diagnostics distinguish whether UDP/443 was requested. Quit before using the advanced TCP-only launch: `open -a MoleDPI --args --tcp-only`.

Source and test details: Native/UDPSession.swift, Native/PFSession.swift, vendor/byedpi/moledpi_quic.h and Experimental/UDP/README.md. Engines are source-built, dependency notices and complete corresponding source are distributed. No paid API, remote VPN server or developer account is required to use this backend. Independent security review and broader deployment testing remain pending.
