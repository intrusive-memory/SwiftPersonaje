// swift-tools-version: 6.2

import PackageDescription

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
// The org's `sibling()` local-checkout helper is deliberately absent for now:
// SwiftReparto has to be pinned to a branch until 0.2.0 ships, and a local
// `../SwiftReparto` checkout on `development` would not carry it. Restore the
// sibling pattern when the branch pin goes.

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
    // TODO: pin .upToNextMajor(from: "0.2.0") once released
    .package(
      url: "https://github.com/intrusive-memory/SwiftReparto.git",
      branch: "requirements/personaje"),
    .package(
      url: "https://github.com/intrusive-memory/SwiftCompartido.git",
      .upToNextMajor(from: "7.4.0")),
    .package(
      url: "https://github.com/intrusive-memory/SwiftProyecto.git",
      .upToNextMajor(from: "5.3.2")),
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
