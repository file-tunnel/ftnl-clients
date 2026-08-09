// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FtnlClient",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "FtnlClient", targets: ["FtnlClient"])],
    targets: [.target(name: "FtnlClient")]
)
