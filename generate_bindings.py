import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

SWIFT_WINRT_VERSION = "0.6.0"
NUGET_PACKAGE = {"Id": "Microsoft.Windows.SDK.Contracts", "Version": "10.0.18362.2005"}
TARGETS = [
    {"name": "WindowsStorage", "includes": ["Windows.Storage"], "excludes": []},
]

SCRIPT_DIR = Path(__file__).parent
PACKAGES_DIR = SCRIPT_DIR / ".packages"
GENERATED_DIR = SCRIPT_DIR / ".generated"
SOURCES_DIR = SCRIPT_DIR / "Sources"

PLACEHOLDER = "<ADD PACKAGES>"

PACKAGE_SWIFT_TEMPLATE = f"""\
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "UWPKit",
    products: [
        .library(name: "WindowsFoundation", type: .dynamic, targets: ["WindowsFoundation"]),

        /// {PLACEHOLDER}
    ],
    targets: [
        .target(name: "WindowsFoundation", dependencies: [
            "CWinRT",
        ]),
        .target(name: "CWinRT"),

        /// {PLACEHOLDER}
    ]
)
"""


def restore_nuget():
    nuget_path = Path(os.environ.get("TEMP", "/tmp")) / "nuget.exe"
    if not nuget_path.exists():
        print("[nuget] Downloading nuget.exe")
        urllib.request.urlretrieve(
            "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe",
            nuget_path,
        )

    content = (
        '<?xml version="1.0" encoding="utf-8"?>\n<packages>\n'
        f'    <package id="TheBrowserCompany.SwiftWinRT" version="{SWIFT_WINRT_VERSION}" />\n'
        f'    <package id="{NUGET_PACKAGE["Id"]}" version="{NUGET_PACKAGE["Version"]}" />\n'
        "</packages>"
    )

    PACKAGES_DIR.mkdir(exist_ok=True)
    config_path = PACKAGES_DIR / "packages.config"
    config_path.write_text(content)

    result = subprocess.run(
        [str(nuget_path), "restore", str(config_path), "-PackagesDirectory", str(PACKAGES_DIR)],
        capture_output=True,
    )
    if result.returncode != 0:
        print("[nuget] Restore failed")
        sys.exit(1)


def winmd_paths():
    pkg_dir = PACKAGES_DIR / f"{NUGET_PACKAGE['Id']}.{NUGET_PACKAGE['Version']}"
    return list(pkg_dir.rglob("*.winmd"))


def foundation_rsp(winmds):
    lines = [f"-output {GENERATED_DIR}", "-include Windows.Foundation"]
    lines += [f"-input {p}" for p in winmds]
    return "\n".join(lines)


def namespace_rsp(namespace, winmds):
    lines = [f"-output {GENERATED_DIR}"]
    lines += [f"-include {i}" for i in namespace["includes"]]
    lines += [f"-exclude {e}" for e in namespace["excludes"]]
    lines += [f"-input {p}" for p in winmds]
    return "\n".join(lines)


def run_swift_winrt(rsp: str):
    if GENERATED_DIR.exists():
        shutil.rmtree(GENERATED_DIR)

    rsp_file = SCRIPT_DIR / "swift-winrt.rsp"
    rsp_file.write_text(rsp)

    exe = os.environ.get(
        "SwiftWinRTOverride",
        str(PACKAGES_DIR / f"TheBrowserCompany.SwiftWinRT.{SWIFT_WINRT_VERSION}" / "bin" / "swiftwinrt.exe"),
    )
    result = subprocess.run([exe, f"@{rsp_file}"])
    if result.returncode != 0:
        print(f"[swiftwinrt] Failed with code {result.returncode}")
        sys.exit(1)


def copy_windows_foundation():
    for name in ["WindowsFoundation", "CWinRT"]:
        subdir = name if name == "CWinRT" else f"{name}/Generated"
        src = GENERATED_DIR / "Sources" / name
        dest = SOURCES_DIR / subdir
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(src, dest)


def copy_generated_namespace(namespace):
    name = namespace["name"]
    src = GENERATED_DIR / "Sources" / "UWP"
    dest = SOURCES_DIR / name / "Generated"
    if dest.exists():
        shutil.rmtree(dest)
    (SOURCES_DIR / name).mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dest)


def modify_package(package_swift: str, namespace) -> str:
    name = namespace["name"]
    library = f'        .library(name: "{name}", type: .dynamic, targets: ["{name}"]),'
    target = f'        .target(name: "{name}", dependencies: ["CWinRT", "WindowsFoundation"]),'

    commented = f"/// {PLACEHOLDER}"

    package_swift = package_swift.replace(
        commented, f"{library}\n\n        {commented}", 1
    )
    last = package_swift.rfind(commented)
    package_swift = (
        package_swift[:last]
        + f"{target}\n\n        {commented}"
        + package_swift[last + len(commented):]
    )
    return package_swift


def main():
    print("[main] Starting")

    if SOURCES_DIR.exists():
        print("[main] Removing existing Sources directory")
        shutil.rmtree(SOURCES_DIR)
    SOURCES_DIR.mkdir(parents=True)

    restore_nuget()
    winmds = winmd_paths()

    print("[main] Generating Windows.Foundation")
    run_swift_winrt(foundation_rsp(winmds))
    copy_windows_foundation()

    package_swift = PACKAGE_SWIFT_TEMPLATE
    for namespace in TARGETS:
        print(f"[main] Processing namespace {namespace['name']}")
        run_swift_winrt(namespace_rsp(namespace, winmds))
        copy_generated_namespace(namespace)
        package_swift = modify_package(package_swift, namespace)

    package_swift_path = SCRIPT_DIR / "Package.swift"
    print(f"[main] Writing Package.swift to {package_swift_path}")
    package_swift_path.write_text(package_swift)

    print(f"[main] Done! Package.swift written with {len(TARGETS)} target(s).")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
