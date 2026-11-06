# v1.1.0-beta verification scope

Automated smoke/controller/recovery tests plus ASan/UBSan QUIC header gate tests pass. Previous lab tests verified native IPv4/IPv6 UDP/QUIC, twelve narrow physical PF/utun routing/crash cases and preserved network configuration.

The integrated app verification covers actual Connect/Disconnect cycles, HTTPS controls, public QUIC handshake using system certificate verification, positive owned UDP PF counters and network restoration. Live results are recorded in the release only after the final build passes. No real ISP-blocked UDP path was available.

No universal UDP/game/voice support, HTTP/3 semantics, older macOS acceptance, clean-Mac acceptance, notarization or independent audit is claimed.

## Final integrated build results
- 10 Connect/Disconnect cycles passed with verified HTTPS, active UDP helper, network restoration and public QUIC handshake using system certificate verification. A positive owned UDP PF counter confirmed interception during that handshake.
- Eight Quit cases passed: connected, idle, immediate, connecting, starting worker, disconnecting, preflight engine failure, connected again. The app exited normally, networking was restored, HTTPS stayed reachable and no owned processes remained.
- SIGKILL of the actual client passed watchdog recovery, including removal of TCP/UDP/tunnel workers.
- Automated controller checks and ASan/UBSan QUIC gate vectors/fuzzing passed. Strict signatures and distribution privacy scans passed. These are short local tests, not long-term/independent certification.
