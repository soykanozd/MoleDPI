#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/native
cd vendor/zapret/tpws
/usr/bin/clang -arch arm64 -mmacosx-version-min=13.0 -std=gnu99 -Os -Wno-address-of-packed-member -Iepoll-shim/include -Imacos -o ../../../.build/native/tpws *.c epoll-shim/src/*.c -lz -lpthread -Wl,-dead_strip

cd ../../..
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 Native/PFSession.swift Sources/MoleDPI/ListenerReadiness.swift -o .build/native/moledpi-pf

swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 Sources/MoleDPI/ServiceProtocol.swift Native/Daemon.swift -o .build/native/moledpi-service
