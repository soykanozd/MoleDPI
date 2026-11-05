// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MoleDPI", platforms: [.macOS(.v13)], products: [.executable(name: "MoleDPI", targets: ["MoleDPI"])], targets: [.executableTarget(name: "MoleDPI"), .testTarget(name: "MoleDPITests", dependencies: ["MoleDPI"])])
