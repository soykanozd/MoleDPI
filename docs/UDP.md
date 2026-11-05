# UDP behavior and capability status

## What works and what is implemented
MoleDPI processes public TCP ports 80/443 through tpws and its PF anchor. Application UDP/QUIC flows are left to the ordinary system network path. The small UDP/TCP DNS recovery listener is a DNS-only component, not a general UDP relay.

Voice calls, screen sharing and game sessions may work with MoleDPI active. A user reported these functions working in their own setup. This is a user observation, not an independently instrumented protocol test or a guarantee across networks. Opening TCP signaling or HTTPS resources can be enough for an application whose media/game traffic is already reachable. Some applications can also use fallback transports. We have not established which path carried those reported sessions.

**No system-wide UDP/QUIC censorship-bypass feature has been implemented.** A successful call or game session does not, by itself, prove that an otherwise blocked UDP path was modified.

## Verified locally
Run `python3 Checks/udp_capability.py` after building the source engine. It starts only an owned, unprivileged loopback tpws instance, checks that SOCKS UDP ASSOCIATE is rejected with reply 0x07, and checks intact direct loopback UDP datagrams while that instance runs. It changes no PF rules or routes and contacts no public endpoint. It does not exercise the installed transparent PF session or establish external UDP reachability/censorship bypass.

The installed PF rules in `Native/PFSession.swift` select TCP only. The pinned tpws SOCKS handler in `vendor/zapret/tpws/tpws_conn.c` accepts CONNECT and explicitly rejects UDP ASSOCIATE.

## Options reviewed, not integrated
- [Zapret macOS notes](https://github.com/bol-van/zapret/blob/master/docs/bsd.en.md#macos): upstream documents that dvtws packet diversion is not functional on macOS, while tpws works with PF. Its Linux/FreeBSD UDP features cannot simply be enabled in this macOS tpws build.
- [ByeDPI](https://github.com/hufrea/byedpi): documents SOCKS UDP handling and UDP fake-packet options. A SOCKS capability alone does not capture UDP from arbitrary macOS applications. Compatibility, interception and whether a strategy actually helps against an observed block need separate verification.
- [ByeDPI Android](https://github.com/dovecoteescapee/ByeDPIAndroid): redirects application traffic using Android's local VPN service and a separate SOCKS tunnel component. This is not a macOS integration. A local tunnel does not inherently require a paid remote server, but also does not inherently defeat filtering.

A future local UDP implementation needs a reviewed macOS capture/forwarding path, IPv4/IPv6 and MTU handling, flow/NAT lifetime management, bounded resources, safe route restoration, crash recovery and tests against a genuinely failing UDP path. Forwarding must be distinguished from verified censorship bypass. No such component has been installed or silently enabled by this documentation change.
