# Swift UWP

Swift Language Bindings for UWP APIs

## APIs
These projections contains a subset of APIs as part of the UWP platform. The list of full namespaces is available here for reference: https://learn.microsoft.com/en-us/uwp/api/

### SDK Version
Currently, these APIs are targeted towards the 10.0.18362.0 SDK of Windows, as this is the minimum version that the Windows App SDK supports.

## Project Configuration
The bindings are generated from WinMD files, found in NuGet packages on Nuget.org. There are two key files which drive this:
1. projections.json - this specifies the project/packages and which apis to include in the projection
2. generate-bindings.ps1 - this file reads `projections.json` and generates the appropriate bindings.

Forked from https://github.com/thebrowsercompany/swift-uwp/blob/main/projections.json