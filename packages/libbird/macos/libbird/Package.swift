// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "libbird",
    platforms: [
        .macOS("10.15") 
    ],
    products: [
        .library(name: "libbird", targets: ["libbird"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "libbird",
            dependencies: [],
            resources: [
                // Bundle the Ladybird executable helpers, UI resources, AND the dynamic libraries
                .copy("LadybirdArtifacts/helpers"),
                .copy("LadybirdArtifacts/resources"),
                .copy("LadybirdArtifacts/lib") 
                
                // If your plugin requires a privacy manifest, for example if it collects user
                // data, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ],
            cxxSettings: [
                // Header paths are evaluated relative to this target's root directory (Sources/libbird/)
                .headerSearchPath("LadybirdArtifacts/include/ladybird_src"),
                .headerSearchPath("LadybirdArtifacts/include/ladybird_build"),
                .unsafeFlags(["-std=c++2b"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    // Use a pure relative path from the package root. SPM allows this.
                    "-LSources/libbird/LadybirdArtifacts/lib",
                    "-framework", "Cocoa", 
                    "-framework", "Metal", 
                    "-framework", "QuartzCore", 
                    "-framework", "UniformTypeIdentifiers"
                ])
            ]
        )
    ]
)