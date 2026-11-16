# v1.2.1 verification — 2026-11-16

Results from the installed Apple Silicon application, with the same executable shipped in the DMG. Full aggregate measurements are in [verification-v1.2.1.json](docs/verification-v1.2.1.json). No personal paths, credentials, traffic contents, account identifiers or raw application logs are published.

## Reproduced issues and fixes

The legacy OOB strategy intermittently failed a public content-CDN TLS handshake while the principal page still worked. In a matched 12-request comparison, legacy OOB returned 3/12 secure responses (mean 3018.94 ms including timeouts); the corrected suffix policy returned 12/12 (mean 65.29 ms). The root returns HTTP 403: this verifies transport, not authorization, content delivery or a game session. The same source-built engine and certificate checks were used for both variants. The opt-in reproduction script is `Checks/cdn_compatibility.py`.

A baseline Connect/Disconnect run completed only 3 cycles and 4 verified connections before a cleanup/worker-exit race. Cleanup subsequently recovered. The corrected final build completed all 10 cycles. A separate candidate failed a transparent-route check despite passing the local SOCKS probe; the final code cleans up before trying another fixed strategy. No failed strategy is saved as verified.

## Final checks

| Check | Observed result |
|---|---|
| Connect/Disconnect | 10/10 completed, no failed connections or cleanup errors |
| Connect duration | Mean 4275.71 ms; median 3156.10 ms; slowest 7528.80 ms |
| Public HTTP/3 | 184 requests; 60-second sustained phase; certificate verification enabled; no TCP fallback |
| HTTP/3 request latency | Median 30.52 ms; slowest 297.73 ms |
| Parallel transfers | Four hash-checked transfers; four connections with five streams each; idle/resume passed |
| HTTP/3 sampled process usage | Peak 23.4% CPU and 74432 KiB RSS; one-second samples |
| Quit | Eight scenarios passed, including idle, connecting, connected, disconnecting, and engine failure |
| Client SIGKILL | Watchdog restored the network; owned TCP/UDP/tunnel processes exited |
| Injected path/wake events | Three cycles with real HTTPS, preserving the same engine session |
| UDP payload integrity | Synthetic IPv4: 1, 64, 512, 1200, 1232, 1400, 1452, 1472 bytes |
| Standalone regressions | 71 passed assertions, including partial-health visibility, cancellation, stale results, update links and bounded native commands |
| QUIC gate | ASan/UBSan checks passed |
| Distribution | Source/app/DMG privacy scan, signatures, helper hashes, architecture and DMG integrity passed |

HTTP/3 teardown verified restoration of PF, proxy and DNS configuration and absence of owned processes. Quit checks also verified normal HTTPS afterwards. Transport/API checks now supplement page checks; one successful destination no longer hides partial failures. Partial failures preserve established connections and display Limited Access.

The incomplete baseline mean was 4275.89 ms over four connections, median 4231.31 ms, slowest 6737.00 ms. This is **not** a complete 10-versus-10 comparison, and the final run checks more destinations. No improvement in overall mean Connect time or controlled CPU/memory reduction is claimed. Retries and direct diagnostic timeouts still account for the slowest connections; the CDN latency improvement is a separate measurement.

`swift test` was unavailable because the installed Command Line Tools do not provide XCTest. Standalone parser, proxy, controller and process tests passed; this is not reported as a passed XCTest run.

## Limits

Some optional remote service endpoints still timed out during exploration. Passing these checks does not establish access to every website, game or voice service. No game-session claim is made. No known ISP-blocked QUIC destination or public IPv6 route was available. Synthetic IPv6 was also skipped on this run because no suitable local endpoint was assigned.

No controlled root-worker crash, physical sleep/Wi-Fi roaming, packet-loss/MTU-blackhole injection, 24-hour soak, clean-Mac uninstall, older-OS certification, independent security audit or Apple notarization is claimed. Normal GitHub release status is not proof that these untested cases passed.

The app contains its complete corresponding runtime source and a preparation report. These final measurements and the standalone CDN comparison script were added to the repository/release after freezing the tested executable; no executable was rebuilt solely to embed post-test results. Earlier evidence remains in `docs/verification-v1.2.0.json`.
