// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "libbird",
  platforms: [
    .macOS(.v11)
  ],
  products: [
    .library(
      name: "libbird",
      targets: ["libbird"]
    )
  ],
  dependencies: [],
  targets: [
    .binaryTarget(
      name: "LadybirdEngine",
      path: "Frameworks/LadybirdEngine.xcframework"
    ),
    .target(
      name: "libbird",
      dependencies: [
        "LadybirdEngine"
      ],
      path: "Sources/libbird",
      resources: [
        .copy("LadybirdBundle")
      ],
      cxxSettings: [
        .headerSearchPath("../../../third_party/ladybird/UI/AppKit"),
        .headerSearchPath("../../../third_party/ladybird"),
        .define("DEFINES_MODULE", to: "YES"),
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("Metal"),
        .linkedFramework("QuartzCore"),
        .linkedFramework("UniformTypeIdentifiers"),
        .unsafeFlags(["-Xlinker", "-w"]),
      ]
    ),
  ],
  cxxLanguageStandard: .cxx20
)
