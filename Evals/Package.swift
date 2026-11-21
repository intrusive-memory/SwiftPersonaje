// swift-tools-version: 6.2

import PackageDescription

// The model-backed evaluation of SwiftPersonaje's character summaries.
//
// A package of its own, so the library keeps its macOS 26 floor and its
// dependency graph: SwiftLlavero (the one path to a model) and Apple's
// Evaluations framework both need macOS 27, SwiftLlavero brings
// firebase-ios-sdk with it, and SwiftBruja (local MLX models) brings MLX.
//
//   * PersonajeEvalKit         — fixtures, scoring, thresholds, and the
//                                baseline extractor and summarizer.
//   * SwiftPersonajeEvalTests  — the evaluation itself (Evaluations
//                                framework), gated on Apple Intelligence and
//                                never run in GitHub Actions; plus scoring
//                                tests. Run with `make test-eval` from the
//                                repo root.
//
// Nothing here is part of `make test` or CI.

let package = Package(
  name: "PersonajeEvals",
  platforms: [
    .macOS("27.0")
  ],
  products: [
    .library(name: "PersonajeEvalKit", targets: ["PersonajeEvalKit"])
  ],
  dependencies: [
    .package(name: "SwiftPersonaje", path: ".."),
    .package(
      url: "https://github.com/intrusive-memory/SwiftLlavero.git",
      .upToNextMajor(from: "0.1.0-beta.2")),
    .package(url: "https://github.com/jpsim/Yams.git", .upToNextMajor(from: "6.2.2")),
    // Local MLX models, in-process, for comparison with Apple's models.
    .package(
      url: "https://github.com/intrusive-memory/SwiftBruja.git", .upToNextMajor(from: "1.12.0")),
  ],
  targets: [
    .target(
      name: "PersonajeEvalKit",
      dependencies: [
        .product(name: "SwiftPersonaje", package: "SwiftPersonaje"),
        .product(name: "SwiftLlavero", package: "SwiftLlavero"),
        .product(name: "Yams", package: "Yams"),
        .product(name: "SwiftBruja", package: "SwiftBruja"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "SwiftPersonajeEvalTests",
      dependencies: [
        "PersonajeEvalKit",
        .product(name: "SwiftPersonaje", package: "SwiftPersonaje"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
