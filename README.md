# MoleDPI

**EXPERIMENTAL — bugs, connection failures and network interruptions may occur.**

A free, open-source macOS menu-bar application for trying local DPI circumvention with source-built zapret **tpws**. No remote VPN server or account is required.

## Download and install

**Apple Silicon · macOS 13 or later**

1. Download **[MoleDPI.dmg](../../releases/download/v0.9.3-beta/MoleDPI.dmg)** from Releases. For this experimental pre-release, use **[all releases](../../releases)**.
2. Open the disk image and drag **MoleDPI** onto **Applications**.
3. Open MoleDPI from Applications.
4. Click the helmet in the menu bar, then **Connect**.
5. Approve the local network helper if macOS asks.

No Terminal, Homebrew, Xcode or additional network tools are needed to run the packaged app.

**Important:** This experimental build is ad-hoc signed and **not notarized by Apple**. Gatekeeper may block an internet-downloaded copy. See [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Only approve a copy you trust. Do not disable Gatekeeper. If macOS offers no permitted way to open this build, wait for a notarized release.

## Use

- Left-click the menu-bar helmet to show or hide the panel.
- Clicking elsewhere or pressing Escape hides the panel while the connection continues.
- **Disconnect** restores this session's network configuration and stops automatic recovery.
- Right-click the helmet and select **Quit MoleDPI** to clean up and exit.
- **?** opens About MoleDPI.

First installation and a changed application build may require administrator approval. Repeated Connect/Disconnect with the same approved build uses the installed helper.

## How it works

MoleDPI tests local TCP/TLS splitting strategies, then uses a restricted helper and macOS PF to process the current user's public TCP traffic on ports 80 and 443. Connected requires HTTPS checks, an active PF session and a positive packet count. This verifies specific control destinations rather than every website.

The controller tolerates isolated health-check failures and attempts controlled recovery after a worker failure. Reconnection uses bounded backoff, pauses new worker attempts while offline, and stops when you choose Disconnect or Quit. Reopening the app never automatically connects.

If the ordinary DNS path fails for Discord or Roblox, MoleDPI can use Quad9 DNS-over-HTTPS through a session-only loopback bridge and a temporary, domain-scoped macOS resolver. This affects those domains across the Mac during the session.

## Known limitations

- **Experimental software. Bugs and outages are possible.**
- Apple Silicon binaries only. Minimum target macOS 13; runtime verification has been limited to a recent macOS release. Older macOS versions, Intel Macs and a clean-Mac install are not certified.
- TCP 80/443 only. **No system-wide UDP or QUIC bypass. Discord voice, screen sharing and Roblox game sessions are not guaranteed.**
- Your public IP remains visible. This is not an anonymity service.
- Supplemental recovery queries use a local UDP/TCP bridge and certificate-verified DNS-over-HTTPS to Quad9. Quad9 can see those queries. Ordinary system DNS queries outside recovery remain governed by your system settings. HTTPS certificate validation stays enabled.
- Checks contact example.com, discord.com and www.roblox.com. No browsing history, traffic-content logging or analytics SDK is included.
- VPNs, firewalls, sleep/wake and network changes may affect reliability. Long-duration stability has not been certified.
- Network processing uses root-owned software. Independent security review is still needed.
- Some technical error messages remain untranslated.

## Remove

Disconnect and quit MoleDPI. Open **Uninstall MoleDPI** from the disk image, approve the macOS prompt, then move MoleDPI from Applications to the Trash. Deleting the main app alone leaves the helper registration installed. The experimental graphical uninstaller has been built and signature-checked; a clean-machine removal test remains pending.

## Source and acknowledgements

The engine is [zapret tpws](https://github.com/bol-van/zapret), pinned at `73ee2aa04e6e94922e7dc07554a1c3a456dc3201`. [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) inspired the straightforward project documentation; its Windows driver is not bundled. [ByeDPI](https://github.com/hufrea/byedpi) was reviewed but is not bundled.

MoleDPI is **GPL-3.0-only**. See [LICENSE](LICENSE), [NOTICE](NOTICE) and [THIRD-PARTY.md](THIRD-PARTY.md). Complete corresponding source and build scripts are distributed alongside the binary and within its application bundle. Upstream copyright notices are retained.

See [BUILDING.md](BUILDING.md) for developer instructions.

## Network changes and updates
When the network changes or the Mac wakes, MoleDPI coalesces an immediate health check and preserves a working engine. A successful strategy number is saved locally and tried first next time; all candidates still undergo real verification. No network name or address is saved with this preference.

In **? → Check for Updates**, you can manually request GitHub release metadata. Checking is optional and contacts GitHub, which can see your request IP. No account, token or diagnostics is sent. **View Release** opens the project release page. Downloads and installation remain under your control.

## Diagnostics
Open **? → Review Diagnostics**, inspect the text, then choose **Copy Report** if you want to share it in an issue. Reports contain only allowlisted connection state and counters. Raw errors, account identifiers, IP addresses, paths and browsing history are excluded. Nothing is uploaded automatically.

The app uses public DNS infrastructure and your existing internet connection. It has no paid account, developer-operated relay, subscription or metered application API.

## Report a bug

Use [Issues](../../issues). Include the app version, macOS version, action and error. Do not include passwords, tokens, browsing history, personal network details or unredacted screenshots.
