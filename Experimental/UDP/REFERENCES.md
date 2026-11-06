# Additional reference review

## GoodbyeDPI-Turkey

Reviewed revision: [cb83565af1edfc6d80f53d98ca32a41fa6bc0862](https://github.com/cagritaskn/GoodbyeDPI-Turkey/tree/cb83565af1edfc6d80f53d98ca32a41fa6bc0862).

This repository contains a macOS port as well as Windows code. The [macOS port](https://github.com/cagritaskn/GoodbyeDPI-Turkey/blob/cb83565af1edfc6d80f53d98ca32a41fa6bc0862/macos/README.md) wraps source-built ByeDPI and configures system SOCKS/DNS settings. It is not a ready-made macOS transparent UDP capture implementation. Its documented TCP techniques are separate from the UDP fake-packet method tested in this lab.

Relevant lessons:
- The build helper explicitly ad-hoc signs copied executables. This lab now explicitly signs and verifies its binaries before privileged staging; this does not provide Apple notarization or developer identity.
- Its state-preservation and teardown structure is worth reviewing. This lab uses a separate, narrowly scoped PF anchor, ephemeral utun interface, root-owned JSON recovery journal and independent supervisor-crash recovery rather than sourcing a shell state file.
- A system SOCKS preference can be ignored by applications. Real packet-capture tests remain necessary; global proxy/DNS changes are not used by the UDP lab.

The repository declares Apache-2.0. No implementation code, binaries, shell scripts or configuration recipes were copied from it. It is an architectural/build reference; the actual lab engines retain their separate pinned revisions and notices listed in UPSTREAM.md. MoleDPI's working TCP engine is unchanged.

## SplitWire-Turkey

[SplitWire-Turkey](https://github.com/cagritaskn/SplitWire-Turkey) is a Windows automation project combining several backends. Its README describes local ByeDPI/zapret methods separately from WireSock/WARP tunnelling. Its QUIC blockcheck script tries fake-packet and fragmentation variants; those packet-driver strategies are not directly portable to macOS. Its top-level license is MIT; bundled engines have their own notices. No code or binaries were copied. The applicable design lesson is measured strategy selection and separate verification of each transport, rather than claiming all backends are equivalent. No WARP account, remote tunnel or Windows driver is added to MoleDPI.
