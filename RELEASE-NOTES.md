# v0.9.3-beta — Experimental network resilience update
**Experimental. Bugs, connection failures and network interruptions may occur.**

- Network-path changes and Mac wake trigger a coalesced immediate health check. A working engine is preserved.
- Save only the last verified strategy number locally and try it first. Failed strategies fall back to the remaining candidates and require verification.
- Friendly English error guidance without exposing raw errors or personal identifiers.
- Optional **About → Check for Updates** reads public GitHub releases only when clicked. No automatic installation or startup request.
- Existing encrypted DNS recovery, reviewed diagnostics, manual Disconnect/ Quit priorities and free operation retained.

Ad-hoc signed, not Apple-notarized. Gatekeeper may block the download. Apple Silicon preview; UDP voice/game bypass is not claimed. No paid services or developer-operated servers added.
