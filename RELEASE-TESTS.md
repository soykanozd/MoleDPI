# v1.0.1 experimental release verification

Short local tests only. No overnight or long-duration network test was performed.

- 42 automated check results passed across smoke, stability, feature and network-recovery suites (`./scripts/test.sh`).
- New checks cover curl error categories, stale health results after network loss, actionable offline help, preserving a healthy worker, pausing checks during sleep, repeated wake events, failure streaks across refreshes, sanitized diagnostics, Connect during sleep, manual Disconnect and Quit priority.
- Production ARM64 build and strict deep ad-hoc signature verification passed. Packaging verifies the DMG and signs the bundled removal application.
- Three local live HTTPS/PF cycles with injected controller network/wake events preserved the original engine session. PF configuration and proxy settings matched after Disconnect. These checks use the real engine and HTTPS but **do not physically change Wi-Fi or put the Mac to sleep**.
- The fixed 330 × 430 pt help panel was rendered and visually reviewed; long help text is scrollable.
- Prior v1.0.0 short live panel/quit checks and historical DNS/crash-cleanup tests are not substitutes for acceptance testing this release on other networks.
- Developer ID/notarization, quarantined clean-Mac installation, graphical removal in a fresh account, Intel, older macOS devices, physical sleep/Wi-Fi transitions, long-duration stability and independent security review remain unverified.
