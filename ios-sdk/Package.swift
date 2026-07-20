// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "IDVerseSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v11)
    ],
    products: [
        .library(name: "LiteWebView", targets: ["LiteWebView"]),
        .library(name: "IDVerseSDK", targets: ["IDVerseSDK"])
    ],
    targets: [
        .target(
            name: "LiteWebView",
            dependencies: [],
            path: "Source/LiteWebView",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "IDVerseSDK",
            dependencies: ["LiteWebView"],
            path: "Source/IDVerseSDK",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "LiteWebViewTests",
            dependencies: ["LiteWebView"],
            path: "Tests/LiteWebViewTests"
        ),
        .testTarget(
            name: "IDVerseSDKTests",
            dependencies: ["IDVerseSDK"],
            path: "Tests/IDVerseSDKTests"
        )
    ]
)
