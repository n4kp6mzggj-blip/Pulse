// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pulse", targets: ["Pulse"])],
    targets: [.executableTarget(name: "Pulse")]
)
