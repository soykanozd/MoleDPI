#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/checks previews
swiftc -swift-version 5 -parse-as-library Sources/MoleDPI/UI.swift Sources/MoleDPI/Proxy.swift Sources/MoleDPI/Probe.swift Sources/MoleDPI/EncryptedDNS.swift Sources/MoleDPI/OwnedCommand.swift Sources/MoleDPI/Model.swift Sources/MoleDPI/Routing.swift Sources/MoleDPI/PFConnection.swift Sources/MoleDPI/ListenerReadiness.swift Sources/MoleDPI/ServiceProtocol.swift Sources/MoleDPI/ServiceClient.swift Checks/Render.swift -o .build/checks/render
.build/checks/render "$PWD/previews"
