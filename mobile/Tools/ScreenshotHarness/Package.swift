// swift-tools-version: 6.0
//
// ScreenshotHarness — throwaway macOS CLI for visual verification of the
// HyperGit mobile app's SwiftUI screens WITHOUT Xcode.app or an iOS
// Simulator. Renders the app's real production views (symlinked in from
// ../../App/Views and ../../App/Theme — never copied, so they can't drift)
// via ImageRenderer, fed with the app's existing Preview*/*.samples mock
// data. Only needs the Swift toolchain that ships with Command Line Tools.
//
// Usage: swift run --package-path mobile/Tools/ScreenshotHarness ScreenshotHarness [outputDir]
//
// Not part of the shipped app — not referenced by mobile/Package.swift or
// HyperGit.xcodeproj. Safe to delete once no longer needed.
import PackageDescription

let package = Package(
    name: "ScreenshotHarness",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "HyperGitCore", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotHarness",
            dependencies: ["HyperGitCore"],
            path: "Sources/ScreenshotHarness",
            // SettingsView needs EnvironmentValues (tokenStore/githubOAuthService/
            // linearOAuthService) that are declared inline in App/HyperGitApp.swift
            // alongside @main — out of scope for a symlink-only harness. Skip it.
            exclude: ["Views/SettingsView.swift"]
        )
    ]
)
