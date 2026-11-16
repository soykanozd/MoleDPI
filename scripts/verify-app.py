#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Read-only release checks: signature, helper manifest, architecture and sources."""
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def require(value, label):
    if not value:
        raise SystemExit("FAIL: " + label)


def verify(app):
    def command(args):
        result = subprocess.run(args, capture_output=True, text=True, timeout=15)
        require(result.returncode == 0, "release tool check")
        return result.stdout + result.stderr
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = info.get("CFBundleShortVersionString", "")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), "application version")
    require(info.get("MoleReleaseTag") in ["v"+version,"v"+version+"-beta"], "release tag matches version")
    require(info.get("CFBundleIdentifier") == "local.moledpi.app", "application identifier")
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    resources = app / "Contents/Resources"
    names = ["moledpi-service", "moledpi-pf", "tpws", "ciadpi", "tunnel-runner", "moledpi-udp"]
    for name in names:
        binary = resources / name
        require(binary.is_file() and not binary.is_symlink() and binary.stat().st_mode & 0o111, "bundled executable: "+name)
        require(hashlib.sha256(binary.read_bytes()).hexdigest() == info.get("MoleSHA-"+name), "helper digest: "+name)
        require(command(["/usr/bin/lipo", "-archs", str(binary)]).strip() == "arm64", "Apple Silicon architecture: "+name)
    signing = command(["/usr/bin/codesign", "-dvvv", str(resources / "moledpi-service")])
    digest = re.search(r"^CDHash=([0-9a-f]{40})$", signing, re.M)
    require(digest and digest[1] == info.get("MoleServiceCDHash"), "pinned helper identity")
    require(command(["/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/MoleDPI")]).strip() == "arm64", "application architecture")
    for name in ["LICENSE", "NOTICE", "THIRD-PARTY.md", "scripts/build.sh", "scripts/build-engine.sh",
                 "Native/BoundedCommand.swift", "Sources/MoleDPI/TCPStrategy.swift", "Native/PFSession.swift", "Native/UDPSession.swift",
                 "vendor/byedpi/main.c", "vendor/hev/src/hev-main.c", "vendor/zapret/tpws/tpws.c"]:
        require((resources / "Source" / name).is_file(), "corresponding source: "+name)
    print("PASS release signature, helper digests/identity, arm64 architecture and corresponding sources")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1] if len(sys.argv) > 1 else "dist/MoleDPI.app"))
    except (OSError, ValueError, subprocess.SubprocessError, plistlib.InvalidFileException):
        raise SystemExit("FAIL: release verification could not complete")
