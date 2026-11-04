// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChatFrom",
    // The package links from iOS 15, so an app that supports it can add this. The chat itself needs iOS 16.4: see Hub.isSupported.
    platforms: [.iOS(.v15)],
    products: [
        // Not "ChatFrom": a module with the name of a type in it can't be told apart from that type.
        .library(name: "ChatFromSDK", targets: ["ChatFromSDK"]),
    ],
    targets: [
        .target(
            name: "ChatFromSDK",
            path: "Sources/ChatFromSDK",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "ChatFromSDKTests",
            dependencies: ["ChatFromSDK"],
            path: "Tests/ChatFromSDKTests"
        ),
    ]
)
