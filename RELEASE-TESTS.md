# v1.0.0 experimental release verification
Short tests only. No overnight or long-duration network test was performed.

- Existing parser, TLS payload integrity, restoration, permission rejection, cleanup failure, duplicate Quit and listener ownership tests passed.
- Nine injected-timing controller tests passed: isolated health failure, endpoint failure, UI independence, offline waiting, engine-loss recovery, manual Disconnect, Quit during recovery, offline startup and network return.
- Ten feature checks passed: cached strategy order/fallback, release-version ordering and invalid input, update URL restriction, permission guidance, private-data filtering, coalesced immediate health checks and manual Disconnect priority.
- Source-built ARM64 app and helpers, the graphical removal tool, local signatures and DMG structure are verified during packaging.
- The installed v1.0.0 passed a real Connected panel close/reopen health check followed by Quit, and a Connecting-to-Quit check. Both main test processes exited normally. These are short local checks, not physical sleep/Wi-Fi or clean-machine acceptance.
- Previous experimental versions passed local real HTTPS/PF sessions, scoped encrypted-DNS UDP/TCP checks and application-crash cleanup. Those historical tests do not certify all networks or this version for long-duration use.
- Developer ID, notarization, quarantined clean-Mac installation, graphical removal in a fresh account, Intel, older macOS devices and real sleep/Wi-Fi transitions remain unverified.
