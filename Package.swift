// swift-tools-version:5.9
// アプリの「ロジック部分」（CanSNS/Core）だけをテストするためのパッケージ。
// アプリ本体は CanSNS.xcodeproj を Xcode で開いて動かしてください。
// テストの実行: ターミナルでこのフォルダに移動して `swift test`
import PackageDescription

let package = Package(
    name: "CanSNSCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "CanSNSCore", targets: ["CanSNSCore"]),
    ],
    targets: [
        .target(name: "CanSNSCore", path: "CanSNS/Core"),
        .testTarget(name: "CanSNSCoreTests", dependencies: ["CanSNSCore"], path: "Tests/CanSNSCoreTests"),
    ]
)
