// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
//
// When this manifest is evaluated as a transitive dependency inside Xcode's
// `SourcePackages/checkouts/` or SwiftPM's `.build/checkouts/`, every other
// dependency lives as a sibling in the same directory. Treating those as
// in-development local paths produces conflicting package identities, so we
// must skip the sibling shortcut in that context.
let manifestDir = (#filePath as NSString).deletingLastPathComponent
let isSPMCheckout =
  manifestDir.contains("/SourcePackages/checkouts/")
  || manifestDir.contains("/.build/checkouts/")
let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
let useLocalSiblings = !isCI && !isSPMCheckout

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}

/// Same sibling-priority pattern as ``sibling(_:remote:from:)`` but pins to a
/// remote branch when no local sibling exists. Use only when a temporary
/// pre-release dependency on a feature branch is required; switch back to the
/// version-pinned ``sibling(_:remote:from:)`` once the upstream tags a release.
func sibling(_ name: String, remote: String, branch: String) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, branch: branch)
}

// Three targets, one rule each (REQUIREMENTS §1):
//   * SwiftPersonaje   — the library the `personaje` CLI and the Personaje app
//                        both link. No ArgumentParser here.
//   * PersonajeCLICore — command logic, unit-testable in-process. Not a product.
//   * personaje        — the executable: a thin `@main` over PersonajeCLICore.
//
// SP-1: every CAST.md byte goes through SwiftReparto; screenplays are read
// through SwiftCompartido; PROJECT.md is read through SwiftProyecto (Q3: its
// library target links no LLM layer).
//
// SwiftReparto 0.2.0 carries `canonicalName`, which the discovery writer
// needs (RP-P9).

let package = Package(
  name: "SwiftPersonaje",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(
      name: "SwiftPersonaje",
      targets: ["SwiftPersonaje"]
    ),
    .executable(
      name: "personaje",
      targets: ["personaje"]
    ),
  ],
  dependencies: [
    sibling(
      "SwiftReparto",
      remote: "https://github.com/intrusive-memory/SwiftReparto.git",
      from: "0.2.0"),
    sibling(
      "SwiftCompartido",
      remote: "https://github.com/intrusive-memory/SwiftCompartido.git",
      from: "7.4.0"),
    sibling(
      "SwiftProyecto",
      remote: "https://github.com/intrusive-memory/SwiftProyecto.git",
      from: "5.3.2"),
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.7.1")),
  ],
  targets: [
    .target(
      name: "SwiftPersonaje",
      dependencies: [
        .product(name: "SwiftReparto", package: "SwiftReparto"),
        .product(name: "SwiftCompartido", package: "SwiftCompartido"),
        .product(name: "SwiftProyecto", package: "SwiftProyecto"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .target(
      name: "PersonajeCLICore",
      dependencies: [
        "SwiftPersonaje",
        .product(name: "SwiftReparto", package: "SwiftReparto"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .executableTarget(
      name: "personaje",
      dependencies: [
        "PersonajeCLICore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "SwiftPersonajeTests",
      dependencies: [
        "SwiftPersonaje",
        "PersonajeCLICore",
        .product(name: "SwiftReparto", package: "SwiftReparto"),
        .product(name: "SwiftCompartido", package: "SwiftCompartido"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
