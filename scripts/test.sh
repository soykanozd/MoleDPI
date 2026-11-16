#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks
sources=(Sources/MoleDPI/{Proxy,Probe,EncryptedDNS,OwnedCommand,Model,Updates,FriendlyError,Routing,TCPStrategy,PFConnection,ListenerReadiness,ServiceProtocol,ServiceClient}.swift)
swiftc -swift-version 5 -parse-as-library Sources/MoleDPI/Proxy.swift Sources/MoleDPI/Probe.swift Sources/MoleDPI/EncryptedDNS.swift Sources/MoleDPI/OwnedCommand.swift Sources/MoleDPI/Model.swift Sources/MoleDPI/Updates.swift Sources/MoleDPI/FriendlyError.swift Sources/MoleDPI/Routing.swift Sources/MoleDPI/TCPStrategy.swift Sources/MoleDPI/PFConnection.swift Sources/MoleDPI/ListenerReadiness.swift Sources/MoleDPI/ServiceProtocol.swift Sources/MoleDPI/ServiceClient.swift Checks/Smoke.swift -o .build/checks/smoke
.build/checks/smoke

for suite in Stability FeatureTests NetworkRecovery; do
  swiftc -swift-version 5 -parse-as-library "${sources[@]}" "Checks/$suite.swift" -o ".build/checks/$suite"
  ".build/checks/$suite"
done

clang -fsanitize=address,undefined Checks/QUICGate.c -o .build/checks/quic-gate
.build/checks/quic-gate

swiftc -swift-version 5 -parse-as-library Native/BoundedCommand.swift Sources/MoleDPI/OwnedCommand.swift Checks/CommandTests.swift -o .build/checks/command-tests
.build/checks/command-tests
