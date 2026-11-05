# v0.9.2-beta — Experimental privacy update
**Experimental. Bugs, disconnections and network interruptions may occur.**
- Supplemental Discord/Roblox DNS recovery now uses certificate-verified DNS-over-HTTPS through a session-only localhost UDP/TCP bridge.
- Recovery uses Quad9 HTTPS with a fixed bootstrap address. There is no plaintext upstream fallback for recovery. Other system DNS settings remain in effect for ordinary queries.
- Review and copy an allowlisted diagnostics report from About. Nothing is automatically uploaded.
- No paid services, accounts, telemetry, developer-operated servers or subscriptions added.
- Existing TCP bypass, connection recovery and manual Disconnect/ Quit priorities remain.

Apple Silicon, macOS 13+. Ad-hoc signed, not Apple-notarized. Gatekeeper may block the downloaded app. Experimental software provided without warranty. UDP game/voice bypass is not claimed.

Assets: MoleDPI.dmg, MoleDPI-source.zip and SHA256SUMS. See README for installation and limitations.
