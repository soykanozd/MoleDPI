# v1.1.1-beta verification

- Automated controller/parser/restoration checks and QUIC-gate ASan/UBSan checks passed. New regression cases verify connected TCP fallback, truthful fallback diagnostics, no stale QUIC claim after disconnect, and cancellation while the QUIC-status query is suspended.
- Actual installed app: two Connect/Disconnect cycles with the local QUIC TCP port deliberately occupied passed. HTTPS stayed verified, the app remained Connected using TCP, and network settings were restored. The unrelated port owner was preserved.
- Ten normal Connect/Disconnect cycles passed, including a public certificate-verified QUIC handshake and owned UDP PF counter verification. Eight Quit cases passed with no workers left.
- The fixed 330 × 430 pt diagnostics page was rendered and reviewed. Reports are copied explicitly; the GitHub link contains only the template name, with no diagnostic body. No issue was submitted automatically.
- Source and package privacy scans, signatures and DMG integrity were checked during publication. These remain short local tests, not independent security review, universal ISP bypass or older-OS certification.
