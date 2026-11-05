#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/../.."
lab="$PWD/.build/udp-lab"
mkdir -p "$lab"
fetch() {
  local name="$1" remote="$2" revision="$3"
  [[ ! -L "$lab/$name" ]] || { print 'Refusing dependency symlink'; exit 1; }
  if [[ ! -d "$lab/$name/.git" ]]; then
    git clone --no-checkout "$remote" "$lab/$name"
  fi
  git -C "$lab/$name" checkout --detach "$revision"
  [[ "$(git -C "$lab/$name" rev-parse HEAD)" == "$revision" ]]
}
fetch byedpi https://github.com/hufrea/byedpi.git e2684772fbda45f2ff4fc220922a010370534216
fetch hev https://github.com/heiher/hev-socks5-tunnel.git 21bb3d77e64ad5a413d4d851b9f4cacf2098cd77
git -C "$lab/hev" submodule update --init --recursive --depth 1
python3 Experimental/UDP/patch_shutdown.py "$lab/byedpi"
make -C "$lab/byedpi" -j4
# A fresh archive is required: macOS ar otherwise retains duplicate members.
make -C "$lab/hev" clean
rm -f "$lab/hev/bin/libhev-socks5-tunnel.a" "$lab/hev/third-part/yaml/bin/libyaml.a" "$lab/hev/third-part/lwip/bin/liblwip.a" "$lab/hev/third-part/hev-task-system/bin/libhev-task-system.a"
make -C "$lab/hev" static -j4
cc -I "$lab/hev/src" Experimental/UDP/tunnel-runner.c \
  "$lab/hev/bin/libhev-socks5-tunnel.a" "$lab/hev/third-part/yaml/bin/libyaml.a" \
  "$lab/hev/third-part/lwip/bin/liblwip.a" "$lab/hev/third-part/hev-task-system/bin/libhev-task-system.a" \
  -lpthread -o "$lab/tunnel-runner"
swiftc Experimental/UDP/quic_fixture.swift -o "$lab/quic-fixture"
print 'Built isolated UDP lab from pinned source. No routes or app files changed.'
