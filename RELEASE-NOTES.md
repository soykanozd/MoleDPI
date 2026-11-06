# MoleDPI v1.1.1-beta — TCP Fallback and Reviewed Reports

**Experimental; bugs and interruptions remain possible. Ad-hoc signed, not Apple-notarized.**

- QUIC startup failure or worker exit now triggers verified UDP cleanup while preserving the working TCP engine. Cleanup failure still fails closed. The panel explicitly identifies TCP fallback; diagnostics record actual QUIC status.
- **? → Report a Problem** opens reviewed diagnostics with **Copy Report** and **Open GitHub Issue**. The issue template is blank; no diagnostic content is transmitted or appended to the link.
- The compact panel, mole artwork, normal Connect/Disconnect/Quit and permission model are preserved. Changed builds may require one helper approval; repeated connections reuse that approved build.

Apple Silicon, macOS 13 deployment target; broad older-OS compatibility is unverified. Disconnect and Quit before replacing the app in Applications. This remains experimental public UDP/443 QUIC processing; other UDP ports remain direct, public IP is visible and ISP bypass/HTTP3 compatibility is not guaranteed. No server, subscription or paid API is added.
