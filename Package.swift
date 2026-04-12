// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "UWPKit",
    products: [
        .library(name: "WindowsFoundation", type: .dynamic, targets: ["WindowsFoundation"]), //Windows.Foundation
        .library(name: "WindowsData", type: .dynamic, targets: ["WindowsData"]), //Windows.Data
        .library(name: "WindowsDevices", type: .dynamic, targets: ["WindowsDevices"]), //Windows.Devices
        .library(name: "WindowsMedia", type: .dynamic, targets: ["WindowsMedia"]), //Windows.Media
        .library(name: "WindowsStorage", type: .dynamic, targets: ["WindowsStorage"]), //Windows.Storage
    ],
    targets: [
        .target(name: "WindowsFoundation"),
        .target(name: "WindowsData"),
        .target(name: "WindowsDevices"),
        .target(name: "WindowsMedia"),
        .target(name: "WindowsStorage"),
    ]
)
