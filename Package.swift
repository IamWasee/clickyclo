// swift-tools-version: 5.9
//
//  Package.swift
//  ClickyClo — a screen-aware AI desktop companion for macOS.
//
//  Build:  swift build -c release
//  Bundle: ./scripts/build_app.sh   (produces a launchable .app with LSUIElement)
//

import PackageDescription

let package = Package(
    name: "ClickyClo",
    platforms: [
        // ScreenCaptureKit (Stage 3) and the modern Swift concurrency model require Ventura or newer.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClickyClo", targets: ["ClickyClo"])
    ],
    targets: [
        .executableTarget(
            name: "ClickyClo",
            path: "Sources/ClickyClo"
        )
    ]
)
