#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p .build/native
cd vendor/zapret/tpws
/usr/bin/clang -arch arm64 -mmacosx-version-min=13.0 -std=gnu99 -Os -Wno-address-of-packed-member -Iepoll-shim/include -Imacos -o ../../../.build/native/tpws *.c epoll-shim/src/*.c -lz -lpthread -Wl,-dead_strip

cd ../../..
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 Native/PFSession.swift Sources/MoleDPI/ListenerReadiness.swift -o .build/native/moledpi-pf

swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 Sources/MoleDPI/ServiceProtocol.swift Native/Daemon.swift -o .build/native/moledpi-service

make -C vendor/byedpi -j4
cp vendor/byedpi/ciadpi .build/native/ciadpi
make -C vendor/hev static -j4
cc -arch arm64 -mmacosx-version-min=13.0 -I vendor/hev/src Experimental/UDP/tunnel-runner.c vendor/hev/bin/libhev-socks5-tunnel.a vendor/hev/third-part/{yaml/bin/libyaml.a,lwip/bin/liblwip.a,hev-task-system/bin/libhev-task-system.a} -lpthread -o .build/native/tunnel-runner
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 Native/UDPSession.swift Sources/MoleDPI/ListenerReadiness.swift -o .build/native/moledpi-udp
