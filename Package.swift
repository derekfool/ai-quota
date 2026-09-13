// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AIQuota", platforms: [.macOS(.v13)], products: [.executable(name: "AIQuota", targets: ["AIQuota"])], targets: [.target(name: "QuotaCore", resources: [.copy("Sounds")]), .executableTarget(name: "AIQuota", dependencies: ["QuotaCore"]), .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"])])
