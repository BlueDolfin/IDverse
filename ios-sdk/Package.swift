// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "IDVerseSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "IDVerseSDK",
            targets: ["IDVerseSDK"]
        )
    ],
    dependencies: [
        // Add dependencies here if needed
        // .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0")
    ],
    targets: [
        .target(
            name: "IDVerseSDK",
            dependencies: [],
            path: "Source",
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "IDVerseSDKTests",
            dependencies: ["IDVerseSDK"],
            path: "Tests"
        )
    ]
)
