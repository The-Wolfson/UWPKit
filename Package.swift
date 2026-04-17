// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "UWPKit",
    products: [
        .library(name: "WindowsFoundation", type: .dynamic, targets: ["WindowsFoundation"]),

        ///         .library(name: "WindowsStorage", type: .dynamic, targets: ["WindowsStorage"]),

        /// <ADD PACKAGES>
    ],
    targets: [
        .target(name: "WindowsFoundation", dependencies: [
            .product(name: "CWinRT"),
        ]),
        .target(name: "CWinRT"),

        ///         .target(name: "WindowsStorage", dependencies: [.product(name: "CWinRT"), .product(name: "WindowsFoundation")]),

        /// <ADD PACKAGES>
    ]
)
