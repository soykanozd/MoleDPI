# Building MoleDPI

Developers need Apple Command Line Tools and an Apple Silicon Mac. Runtime users should use the DMG.

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package.sh
```

The output is `dist/MoleDPI.dmg`. Source-built tpws, the fixed-purpose PF worker and XPC service are bundled. No third-party prebuilt network executable is downloaded by the build.

Local builds are ad-hoc signed. Developer ID signing and notarization remain a release requirement for smooth public installation.

`./scripts/test-pf-live.sh` invokes the installed app and changes real networking during verification. Only run it deliberately on a test Mac. Deterministic controller checks live in Checks/Stability.swift.

The public tree has fresh, generic author metadata and excludes historical local diagnostics. Software is provided without warranty. Network compatibility depends on the filtering method.

## Opt-in HTTP/3 acceptance

These tests use fixed public Google test resources. They require internet access and transfer about 1.5 MB of response payload per address family, plus protocol overhead. They do not capture browsing traffic, use accounts or upload diagnostics. The Python client implements only HTTP/3, so TCP fallback cannot hide a failed QUIC test. This is a developer dependency, never an application runtime dependency.

```sh
python3 -m venv .build/http3-env
.build/http3-env/bin/python -m pip install -r Checks/http3-requirements.txt
# Quit the ordinary MoleDPI copy first; install the built app in Applications.
.build/http3-env/bin/python Checks/quic_release.py --duration 300 --output .build/quic-report.json
```

A changed app may request normal helper approval once. The driver stops its own session and verifies network restoration. A missing public IPv6 route is recorded as unavailable, never as a passed IPv6 internet test. The report does not prove real ISP bypass. Review docs/UDP.md and RELEASE-TESTS.md for the actual release evidence.

Additional opt-in checks (close the ordinary app before installed-app checks):

```sh
python3 Checks/udp_payload_sizes.py
.build/http3-env/bin/python Checks/endurance_release.py
```

The payload-size check uses production-built engines and a synthetic tunnel FD, with local assigned-address endpoints. It changes no system routing. It skips IPv6 when no suitable assigned endpoint exists. The endurance check performs 100 real Connect/Disconnect cycles, records aggregate timings and checks final network restoration.
