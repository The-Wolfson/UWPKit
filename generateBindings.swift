print("Staarting Generation")

import Foundation

struct Namespace {
    let name: String
    let excludes: [String]
    let includes: [String]
    
    init(name: String, includes: [String] = [], excludes: [String] = []) {
        print("[Namespace] Initializing namespace: \(name)")
        self.name = name
        self.includes = includes
        self.excludes = excludes
    }
}

struct Package {
    let id: String
    let version: String
    
    init(id: String, version: String) {
        print("[Package] Created package \(id) version \(version)")
        self.id = id
        self.version = version
    }
}

let swiftWinRTVersion = "0.6.0"
let nugetPackage = Package(id: "Microsoft.Windows.SDK.Contracts", version: "10.0.18362.2005")
let targets: [Namespace] = [
    Namespace(name: "WindowsStorage", includes: ["Windows.Storage"])
]

let scriptDir = FileManager.default.currentDirectoryPath
print("[Init] Script directory: \(scriptDir)")

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

func downloadFile(from url: String, to path: String) throws {
    print("[downloadFile] Downloading from \(url) to \(path)")
    let result = shell("curl", "-fsSL", url, "-o", path)
    print("[downloadFile] Result: \(result)")
    if result != 0 { throw ScriptError.downloadFailed }
}

func restoreNuGet() throws {
    print("[restoreNuGet] Starting NuGet restore")

    let nuGetPath = (ProcessInfo.processInfo.environment["TEMP"] ?? "/tmp") + "/nuget.exe"
    print("[restoreNuGet] NuGet path: \(nuGetPath)")

    if !FileManager.default.fileExists(atPath: nuGetPath) {
        print("[restoreNuGet] nuget.exe not found, downloading...")
        try downloadFile(from: "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe", to: nuGetPath)
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
        print("[restoreNuGet] Creating packages directory at \(packagesDir)")
        try fm.createDirectory(atPath: packagesDir, withIntermediateDirectories: true)
    }

    let configPath = "\(packagesDir)/packages.config"
    print("[restoreNuGet] Writing config to \(configPath)")
    try content.write(toFile: configPath, atomically: true, encoding: .ascii)

    print("[restoreNuGet] Running nuget restore")
    let result = shell(nuGetPath, "restore", configPath, "-PackagesDirectory", packagesDir)
    print("[restoreNuGet] Restore result: \(result)")
    if result != 0 { throw ScriptError.nugetFailed(result) }
}

// MARK: - RSP

func generateRSP(for namespace: Namespace, winmdPaths: [String]) -> String {
    print("[generateRSP] Generating RSP for namespace \(namespace.name)")
    var lines: [String] = ["-output \(generatedDir)"]
    lines += namespace.includes.map { "-include \($0)" }
    lines += namespace.excludes.map { "-exclude \($0)" }
    lines += winmdPaths.map { "-input \($0)" }
    return lines.joined(separator: "\n")
}

func foundationRSP(winmdPaths: [String]) -> String {
    print("[foundationRSP] Generating foundation RSP")
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
    print("[winmdPaths] Searching in \(dir)")
    guard let enumerator = FileManager.default.enumerator(atPath: dir) else {
        print("[winmdPaths] Enumerator failed")
        return []
    }
    let results = (enumerator.allObjects as! [String])
        .filter { $0.hasSuffix(".winmd") }
        .map { "\(dir)/\($0)" }

    print("[winmdPaths] Found \(results.count) winmd files")
    return results
}

// MARK: - SwiftWinRT

func runSwiftWinRT(rsp: String) throws {
    print("[runSwiftWinRT] Running SwiftWinRT")

    let fm = FileManager.default

    if fm.fileExists(atPath: generatedDir) {
        print("[runSwiftWinRT] Removing existing generated dir")
        try fm.removeItem(atPath: generatedDir)
    }

    let rspFile = "\(scriptDir)/swift-winrt.rsp"
    print("[runSwiftWinRT] Writing RSP file to \(rspFile)")
    try rsp.write(toFile: rspFile, atomically: true, encoding: .ascii)

    let exePath = "\(packagesDir)/TheBrowserCompany.SwiftWinRT.\(swiftWinRTVersion)/bin/swiftwinrt.exe"
    let exe = ProcessInfo.processInfo.environment["SwiftWinRTOverride"] ?? exePath

    print("[runSwiftWinRT] Executable: \(exe)")
    let result = shell(exe, "@\(rspFile)")
    print("[runSwiftWinRT] Result: \(result)")
    if result != 0 { throw ScriptError.swiftWinRTFailed(result) }
}

// MARK: - Sources

func copyWindowsFoundation() throws {
    print("[copyWindowsFoundation] Copying WindowsFoundation and CWinRT")

    for name in ["WindowsFoundation", "CWinRT"] {
        let generatedSubDir = name == "CWinRT" ? name : "\(name)/Generated"
        let dest = "\(sourcesDir)/\(generatedSubDir)"
        let src = "\(generatedDir)/Sources/\(name)"

        print("[copyWindowsFoundation] Copying \(name) from \(src) to \(dest)")

        if FileManager.default.fileExists(atPath: dest) {
            print("[copyWindowsFoundation] Removing existing \(dest)")
            try FileManager.default.removeItem(atPath: dest)
        }
        try FileManager.default.copyItem(atPath: src, toPath: dest)
    }
}

func copyGeneratedNamespace(_ namespace: Namespace) throws {
    print("[copyGeneratedNamespace] Copying namespace \(namespace.name)")

    let fm = FileManager.default
    let dest = "\(sourcesDir)/\(namespace.name)/Generated"
    let src = "\(generatedDir)/Sources/UWP"

    if fm.fileExists(atPath: dest) {
        print("[copyGeneratedNamespace] Removing existing \(dest)")
        try fm.removeItem(atPath: dest)
    }

    print("[copyGeneratedNamespace] Creating directory \(sourcesDir)/\(namespace.name)")
    try fm.createDirectory(atPath: "\(sourcesDir)/\(namespace.name)", withIntermediateDirectories: true)

    print("[copyGeneratedNamespace] Copying from \(src) to \(dest)")
    try fm.copyItem(atPath: src, toPath: dest)
}

// MARK: - Package.swift mutation

func modifyPackage(for namespace: Namespace) {
    print("[modifyPackage] Modifying Package.swift for \(namespace.name)")

    let library = "        .library(name: \"\(namespace.name)\", type: .dynamic, targets: [\"\(namespace.name)\"]),"
    let target = "        .target(name: \"\(namespace.name)\", dependencies: [.product(name: \"CWinRT\"), .product(name: \"WindowsFoundation\")]),"

    if let firstRange = packageSwift.range(of: placeholder) {
        print("[modifyPackage] Inserting library")
        packageSwift.replaceSubrange(firstRange, with: "\(library)\n\n\(placeholder)")
    }

    if let lastRange = packageSwift.range(of: placeholder, options: .backwards) {
        print("[modifyPackage] Inserting target")
        packageSwift.replaceSubrange(lastRange, with: "\(target)\n\n\(placeholder)")
    }
}

// MARK: - Shell

@discardableResult
func shell(_ args: String...) -> Int32 {
    print("[shell] Executing: \(args.joined(separator: " "))")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0])
    process.arguments = Array(args.dropFirst())

    try? process.run()
    process.waitUntilExit()

    print("[shell] Exit code: \(process.terminationStatus)")
    return process.terminationStatus
}

// MARK: - Errors

enum ScriptError: Error {
    case nugetFailed(Int32)
    case swiftWinRTFailed(Int32)
    case downloadFailed
}

// MARK: - Main

func main() throws {
    print("[main] Starting script")

    let fm = FileManager.default
    let winmds = winmdPaths()

    if fm.fileExists(atPath: sourcesDir) {
        print("[main] Removing existing Sources directory")
        try fm.removeItem(atPath: sourcesDir)
    }

    print("[main] Creating Sources directory")
    try fm.createDirectory(atPath: sourcesDir, withIntermediateDirectories: true)

    try restoreNuGet()

    print("[main] Generating Windows.Foundation")
    let rsp = foundationRSP(winmdPaths: winmds)
    try runSwiftWinRT(rsp: rsp)
    try copyWindowsFoundation()

    for namespace in targets {
        print("[main] Processing namespace \(namespace.name)")
        let rsp = generateRSP(for: namespace, winmdPaths: winmds)
        try runSwiftWinRT(rsp: rsp)
        try copyGeneratedNamespace(namespace)
        modifyPackage(for: namespace)
    }

    let packageSwiftPath = "\(scriptDir)/Package.swift"
    print("[main] Writing Package.swift to \(packageSwiftPath)")
    try packageSwift.write(toFile: packageSwiftPath, atomically: true, encoding: .utf8)

    print("[main] Done! Package.swift written with \(targets.count) target(s).")
}

do {
    try main()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
