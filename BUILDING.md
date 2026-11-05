# Building the experimental app

Developers need Apple Command Line Tools and an Apple Silicon Mac. Runtime users should use the DMG.

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package.sh
```

The output is `dist/MoleDPI.dmg`. Source-built tpws, the fixed-purpose PF worker and XPC service are bundled. No third-party prebuilt network executable is downloaded by the build.

Local builds are ad-hoc signed. Developer ID signing and notarization remain a release requirement for smooth public installation.

`./scripts/test-pf-live.sh` invokes the installed app and changes real networking during verification. Only run it deliberately on a test Mac. Deterministic controller checks live in Checks/Stability.swift.

The public tree has fresh, generic author metadata and excludes historical local diagnostics. Changes are experimental and provided without warranty.
