# Contributing to MoleDPI

MoleDPI is experimental. Contributions should improve verified behavior without promising universal access, anonymity or unsupported UDP functionality.

## Report a reproducible issue
Use the issue templates. Include app version, macOS version, CPU family, steps, expected behavior and observed behavior. General descriptions such as Wi-Fi or Ethernet are enough; never include network names, addresses, credentials or browsing history. Review diagnostics before sharing. Avoid raw logs, packet captures or unredacted screenshots.

Compatibility reports should separate HTTPS access, reconnect behavior, sleep/wake, install and cleanup. A successful website check is not proof that every application works. Mark untested behavior as untested.

## Build and verify a change
Follow [BUILDING.md](BUILDING.md). Run `./scripts/test.sh` for controller, parser, restoration and recovery checks. Real-network tests are opt-in and change networking on the test Mac; injected events must not be described as physical Wi-Fi or sleep tests.

Keep the current compact UI and English application text. Preserve cancellation, owned-process cleanup, certificate validation, signature verification and user network settings. Explain any changes to privileged components and add focused checks for concurrency or cleanup changes.

## Licensing and publishing
MoleDPI is GPL-3.0-only. Preserve dependency notices, pin reviewed upstream changes and include complete corresponding source with distributed binaries. Contributions must be compatible with the project and dependency licenses. Do not add private data, credentials, telemetry, paid services or opaque prebuilt network engines.

Documentation corrections, reproducible test reports and independent security review are welcome; no paid tool or account is required to contribute source.
