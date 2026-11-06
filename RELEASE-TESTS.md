# v1.2.0 verification

## Measured before the final package

A pre-release acceptance build using the unchanged production UDP backend completed 483 actual certificate-verified HTTP/3 requests without TCP fallback. The sustained phase lasted 300 seconds. Four simultaneous test-image transfers totalled 1500916 response bytes and matched the independently obtained HTTPS reference SHA-256. Four concurrent connections with five multiplexed requests each and a five-second idle/resume check passed. Request median was 34.04 ms; slowest was 284.92 ms. These are response timings, not bypass speedup measurements.

The app's UDP PF counter increased by 10208. PF/proxy/DNS snapshots matched afterward, the app exited cleanly and no owned processes remained. A separate 60-second run also passed. A missing public IPv6 route was recorded as unavailable, not passed.

Production-built engines passed synthetic IPv4 UDP payload roundtrips at 1, 64, 512, 1200, 1232, 1400, 1452 and 1472 bytes. Synthetic IPv6 payloads at 1, 64, 512, 1200, 1232, 1400 and 1452 bytes also passed with an assigned local endpoint. These are local packet-pipeline checks, not physical internet MTU/fragmentation or loss tests.

Controller/parser/restoration regression checks and the production QUIC Initial gate's ASan/UBSan malformed-input checks passed. Prior installed v1.1.1-beta tests passed ten normal cycles, two forced QUIC-start failures preserving TCP and eight Quit scenarios.

## Final release checks

The final installed v1.2.0 passed 107 certificate-verified HTTP/3 requests, four complete digest-checked transfers, concurrent streams and five-second idle/resume, with no TCP fallback. Its owned UDP PF counter increased; PF/proxy/DNS restoration and no leftover owned processes were verified. Eight real Quit scenarios passed, including Connecting, Connected, Disconnecting, immediate Quit and engine failure.

The endurance run completed 62 Connect/Disconnect cycles and verified 63 connections before deliberate interruption. It did **not** complete the 100-cycle target, and its process termination is not counted as a normal clean test exit. No network failure was logged before interruption. Network restoration and no leftover owned processes were checked afterward. Connection median: 1289.56 ms; mean: 1425.11 ms; slowest: 6389.1 ms.

The long acceptance run's UDP component hashes are compared with the final build in the [machine-readable report](docs/verification-v1.2.0.json). Installed/frozen app signatures and DMG integrity were verified; privacy scans are performed on source and package before upload. The app bundle's source snapshot contains the earlier pre-package verification text; this source report and release JSON add the final results. No runtime source changes were made after freezing the tested app. Run instructions and limits are in BUILDING.md and docs/UDP.md. Nothing is uploaded automatically.

## Not verified

No actual ISP-blocked QUIC path was available. Public IPv6 internet access, automatic TTL calibration, artificial loss/MTU blackholes, 24-hour soak, physical Wi-Fi roaming/sleep and broad older-macOS/clean-Mac compatibility are not certified. Independent security review and Apple notarization remain pending. A regular release designation is not evidence that these untested cases passed.
