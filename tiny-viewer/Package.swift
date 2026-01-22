// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "tiny-viewer",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .executable(
            name: "tiny-viewer",
            targets: ["TinyViewerMain"]
        ),
        .library(
            name: "TinyViewerIOS",
            targets: ["TinyViewerIOS"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "TinyViewerCore",
            dependencies: [
                .product(name: "Kingfisher", package: "Kingfisher")
            ]
        ),
        
        .target(
            name: "TinyViewerMacOS",
            dependencies: [
                "TinyViewerCore",
                .product(name: "Kingfisher", package: "Kingfisher")
            ]
        ),
        
        .target(
            name: "TinyViewerIOS",
            dependencies: [
                "TinyViewerCore",
                .product(name: "Kingfisher", package: "Kingfisher")
            ]
        ),
        
        .executableTarget(
            name: "TinyViewerMain",
            dependencies: ["TinyViewerMacOS"]
        ),
    ]
)
