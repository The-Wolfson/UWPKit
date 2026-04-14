import Foundation

struct Namespace {
    let name: String
    let excludes: [String]
    let includes: [String]
    
    init(name: String, includes: [String] = [], excludes: [String] = []) {
        self.name = name
        self.includes = includes
        self.excludes = excludes
    }
}

struct Package {
    let id: String
    let version: String
}

let swiftWinRTVersion = "0.6.0"
let nugetPackage = Package(id: "Microsoft.Windows.SDK.Contracts", version: "10.0.18362.2005")
let targets: [Namespace] = [
    Namespace(name: "WindowsStorage", includes: ["Windows.Storage"])
]

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let packagesDir = "\(scriptDir)/.packages"
let generatedDir = "\(scriptDir)/.generated"
let sourcesDir = "\(scriptDir)/Sources"
let placeholder = "<ADD PACKAGES>"

var packageSwift = """
    // swift-tools-version: 6.3

    import PackageDescription

    let package = Package(
        name: "UWPKit",
        products: [
            .library(name: "WindowsFoundation", type: .dynamic, targets: ["WindowsFoundation"]),

            /// \(placeholder)
        ],
        targets: [
            .target(name: "WindowsFoundation", dependencies: [
                .product(name: "CWinRT"),
            ]),
            .target(name: "CWinRT"),
            
            /// \(placeholder)
        ]
    )
    """

// MARK: - NuGet

func restoreNuGet() throws {
    let nuGetPath = (ProcessInfo.processInfo.environment["TEMP"] ?? "/tmp") + "/nuget.exe"
    if !FileManager.default.fileExists(atPath: nuGetPath) {
        let url = URL(string: "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe")!
        let data = try Data(contentsOf: url)
        try data.write(to: URL(fileURLWithPath: nuGetPath))
    }

    let content = """
    <?xml version="1.0" encoding="utf-8"?>
    <packages>
        <package id="TheBrowserCompany.SwiftWinRT" version="\(swiftWinRTVersion)" />
        <package id="\(nugetPackage.id)" version="\(nugetPackage.version)" />
    </packages>
    """

    let fm = FileManager.default
    if !fm.fileExists(atPath: packagesDir) {
        try fm.createDirectory(atPath: packagesDir, withIntermediateDirectories: true)
    }

    let configPath = "\(packagesDir)/packages.config"
    try content.write(toFile: configPath, atomically: true, encoding: .ascii)

    let result = shell(nuGetPath, "restore", configPath, "-PackagesDirectory", packagesDir)
    if result != 0 { throw ScriptError.nugetFailed(result) }
}

// MARK: - RSP

func generateRSP(for namespace: Namespace, winmdPaths: [String]) -> String {
    var lines: [String] = ["-output \(generatedDir)"]
    lines += namespace.includes.map { "-include \($0)" }
    lines += namespace.excludes.map { "-exclude \($0)" }
    lines += winmdPaths.map { "-input \($0)" }
    return lines.joined(separator: "\n")
}

func foundationRSP(winmdPaths: [String]) -> String {
    var lines: [String] = [
        "-output \(generatedDir)",
        "-include Windows.Foundation"
    ]
    lines += winmdPaths.map { "-input \($0)" }
    return lines.joined(separator: "\n")
}

// MARK: - WinMD Discovery

func winmdPaths() -> [String] {
    let dir = "\(packagesDir)/\(nugetPackage.id).\(nugetPackage.version)"
    guard let enumerator = FileManager.default.enumerator(atPath: dir) else { return [] }
    return (enumerator.allObjects as! [String])
        .filter { $0.hasSuffix(".winmd") }
        .map { "\(dir)/\($0)" }
}

// MARK: - SwiftWinRT

func runSwiftWinRT(rsp: String) throws {
    let fm = FileManager.default

    if fm.fileExists(atPath: generatedDir) {
        try fm.removeItem(atPath: generatedDir)
    }

    let rspFile = "\(scriptDir)/swift-winrt.rsp"
    try rsp.write(toFile: rspFile, atomically: true, encoding: .ascii)

    let exePath = "\(packagesDir)/TheBrowserCompany.SwiftWinRT.\(swiftWinRTVersion)/bin/swiftwinrt.exe"
    let exe = ProcessInfo.processInfo.environment["SwiftWinRTOverride"] ?? exePath

    let result = shell(exe, "@\(rspFile)")
    if result != 0 { throw ScriptError.swiftWinRTFailed(result) }
}

// MARK: - Sources

func copyWindowsFoundation() throws {
    for name in ["WindowsFoundation", "CWinRT"] {
        let generatedSubDir = name == "CWinRT" ? name : "\(name)/Generated"
        let dest = "\(sourcesDir)/\(generatedSubDir)"
        let src = "\(generatedDir)/Sources/\(name)"
        if FileManager.default.fileExists(atPath: dest) { try FileManager.default.removeItem(atPath: dest) }
        try FileManager.default.copyItem(atPath: src, toPath: dest)
    }
}

func copyGeneratedNamespace(_ namespace: Namespace) throws {
    let fm = FileManager.default
    let dest = "\(sourcesDir)/\(namespace.name)/Generated"
    let src = "\(generatedDir)/Sources/UWP"
    if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
    try fm.createDirectory(atPath: "\(sourcesDir)/\(namespace.name)", withIntermediateDirectories: true)
    try fm.copyItem(atPath: src, toPath: dest)
}

// MARK: - Package.swift mutation

func modifyPackage(for namespace: Namespace) {
    let library = "        .library(name: \"\(namespace.name)\", type: .dynamic, targets: [\"\(namespace.name)\"]),"
    let target = "        .target(name: \"\(namespace.name)\", dependencies: [.product(name: \"CWinRT\"), .product(name: \"WindowsFoundation\")]),"

    // Insert library before first placeholder
    if let firstRange = packageSwift.range(of: placeholder) {
        packageSwift.replaceSubrange(firstRange, with: "\(library)\n\n\(placeholder)")
    }

    // Insert target before last placeholder
    if let lastRange = packageSwift.range(of: placeholder, options: .backwards) {
        packageSwift.replaceSubrange(lastRange, with: "\(target)\n\n\(placeholder)")
    }
}

// MARK: - Shell

@discardableResult
func shell(_ args: String...) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0])
    process.arguments = Array(args.dropFirst())
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

// MARK: - Errors

enum ScriptError: Error {
    case nugetFailed(Int32)
    case swiftWinRTFailed(Int32)
}

// MARK: - Main

func main() throws {
    let fm = FileManager.default
    let winmds = winmdPaths()

    // Wipe Sources
    if fm.fileExists(atPath: sourcesDir) {
        try fm.removeItem(atPath: sourcesDir)
    }
    try fm.createDirectory(atPath: sourcesDir, withIntermediateDirectories: true)

    try restoreNuGet()

    // Windows.Foundation + CWinRT
    let rsp = foundationRSP(winmdPaths: winmds)
    try runSwiftWinRT(rsp: rsp)
    try copyWindowsFoundation()

    // Each additional target
    for namespace in targets {
        let rsp = generateRSP(for: namespace, winmdPaths: winmds)
        try runSwiftWinRT(rsp: rsp)
        try copyGeneratedNamespace(namespace)
        modifyPackage(for: namespace)
    }

    // Write Package.swift
    let packageSwiftPath = "\(scriptDir)/Package.swift"
    try packageSwift.write(toFile: packageSwiftPath, atomically: true, encoding: .utf8)

    print("Done! Package.swift written with \(targets.count) target(s).")
}

do {
    try main()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}


///#Original
///Set packages directory to .packages/ relative to script
///Restore NuGet
/// - Download nuget.exe if not already installed
/// - builds packages.config xml, always include SwiftWinRT
/// - Adds packages and dependencies to the string
/// - Writes XML to disk
/// - run `nuget restore`
///
///Invoke SwiftWinRT
/// - Wipes Sources/
/// - Builds .rsp string
/// - Add Output and include/exclude based on namespaces
/// - finds .winmd files for each package (packages, dependencies) adds as -input
/// - writes to disk
/// - runs swiftwinrt with .rsp file
