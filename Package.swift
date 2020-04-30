// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "DownloadToGo",
    products: [
        .library(
            name: "DownloadToGo",
            targets: ["DownloadToGo"]),
    ],
    dependencies: [
        .package(name: "PlayKitUtils", url: "https://github.com/kaltura/playkit-ios-utils.git", .branch("spm")),
        .package(url: "https://github.com/DaveWoodCom/XCGLogger.git", from: "7.0.1"),
        .package(url: "https://github.com/SlaunchaMan/GCDWebServer.git", .branch("swift-package-manager")),
        .package(name: "Realm", url: "https://github.com/realm/realm-cocoa.git", from: "3.21.0"),
        .package(url: "https://github.com/M3U8Kit/M3U8Parser.git", from: "0.4.1")
    ],
    targets: [
        .target(
            name: "DownloadToGo",
            dependencies: [
                "PlayKitUtils", 
                "XCGLogger", 
                "GCDWebServer", 
                "M3U8Parser",
                .product(name: "RealmSwift", package: "Realm")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "DownloadToGoTests",
            dependencies: ["DownloadToGo"])
    ]
)

