# Reviewed dependency pins

| Component | Source revision | License |
| --- | --- | --- |
| ByeDPI | [e2684772fbda45f2ff4fc220922a010370534216](https://github.com/hufrea/byedpi/tree/e2684772fbda45f2ff4fc220922a010370534216) | MIT |
| HEV SOCKS5 tunnel | [21bb3d77e64ad5a413d4d851b9f4cacf2098cd77](https://github.com/heiher/hev-socks5-tunnel/tree/21bb3d77e64ad5a413d4d851b9f4cacf2098cd77) | MIT |
| HEV SOCKS5 core | d12ec5962cbb777e087015db6aa73374014dd82e | MIT |
| HEV task system | ded55c412b3951bc7decb5cb3b9135701e762998 | MIT |
| HEV lwIP fork | 8115cd6150ab32500db3d4d8bd8ad7ec6648534c | BSD; see full notice |
| libyaml fork | 0c82efd10dc67b9e7f159d2c7f5d1dc3c1b5bc11 | MIT |

HEV submodule pins come from its pinned tree. Full notices are kept in `Licenses/`; fetched dependency source also retains original notices. `patch_shutdown.py` applies a narrowly scoped, macOS-only cancellation patch to the disposable ByeDPI source. It does not alter packet content or filtering strategies.

Architecture reference: [ByeDPI Android](https://github.com/dovecoteescapee/ByeDPIAndroid). No Android code or binaries are copied. [Zapret macOS documentation](https://github.com/bol-van/zapret/blob/master/docs/bsd.en.md#macos) explains why its dvtws packet-diversion backend cannot simply be enabled in the existing macOS tpws app.

If lab binaries are distributed later, preserve these notices and supply the complete matching source of the lab, local patches and all linked dependencies with exact submodule revisions. The current public application continues to bundle its original tpws engine; these lab binaries are not in its DMG.
