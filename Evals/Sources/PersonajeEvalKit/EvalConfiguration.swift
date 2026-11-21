import Foundation
import FoundationModels
import SwiftLlavero
import SwiftPersonaje

/// What one evaluation run reads, uses and writes, from the environment.
///
/// | Variable | Meaning | Default |
/// |---|---|---|
/// | `PERSONAJE_EVAL_PROJECT` | Project folder; episodes are `episodes/*.fountain` | the CC0 example in `Evals/Fixtures/example` |
/// | `PERSONAJE_EVAL_FIXTURES` | Folder of `<CHARACTER>/` fixture folders | `<project>/evals/character-summaries` |
/// | `PERSONAJE_EVAL_EPISODES` | Which files in `episodes/` to read: a glob | `*.fountain` |
/// | `PERSONAJE_EVAL_MODEL` | `on-device`, `pcc`, or `account:model` | `on-device` |
/// | `PERSONAJE_EVAL_REPORT_DIR` | Where reports are written | `Evals/.build/eval` |
///
/// `make test-eval` passes these to the test runner (xcodebuild forwards
/// `TEST_RUNNER_`-prefixed variables with the prefix removed).
public struct EvalConfiguration: Sendable {
  public let project: URL
  public let fixtures: URL
  /// A glob over episode file names, e.g. `0*.fountain`, to leave out a
  /// compiled full script beside the episodes.
  public let episodePattern: String
  public let model: ModelReference
  public let reports: URL

  /// The Evals package folder, found from this file.
  public static let evalsRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // PersonajeEvalKit
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // Evals

  public static let exampleProject = evalsRoot.appendingPathComponent(
    "Fixtures/example", isDirectory: true)

  public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> EvalConfiguration {
    func path(_ key: String) -> URL? {
      environment[key].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    }
    let project = path("PERSONAJE_EVAL_PROJECT") ?? exampleProject
    return EvalConfiguration(
      project: project,
      fixtures: path("PERSONAJE_EVAL_FIXTURES")
        ?? project.appendingPathComponent("evals/character-summaries", isDirectory: true),
      episodePattern: environment["PERSONAJE_EVAL_EPISODES"].flatMap { $0.isEmpty ? nil : $0 }
        ?? "*.fountain",
      model: try ModelReference(parsing: environment["PERSONAJE_EVAL_MODEL"] ?? "on-device"),
      reports: path("PERSONAJE_EVAL_REPORT_DIR")
        ?? evalsRoot.appendingPathComponent(".build/eval", isDirectory: true))
  }

  /// The files in `episodes/` matching ``episodePattern``, in name order.
  public func episodes() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: project.appendingPathComponent("episodes", isDirectory: true),
      includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )
    .filter { fnmatch(episodePattern, $0.lastPathComponent, 0) == 0 }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}

/// When the model-backed evaluation runs.
public enum EvalGate {
  /// Apple Intelligence is on, and this isn't GitHub Actions.
  public static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != "true"
      && SystemLanguageModel.default.isAvailable
  }

  public static let reason =
    "Needs Apple Intelligence on this Mac, and never runs in GitHub Actions."
}

/// Builds the baseline pipeline for `configuration`.
public enum BaselinePipeline {

  /// Tokens kept free for a response, and the cap on every response: an
  /// uncapped response ran one token past an 8,192 context on a long scene.
  public static let reservedForOutput = 1_536

  public static func make(
    corpus: EvidenceCorpus, member: String, configuration: EvalConfiguration
  ) async throws -> CharacterSummaryPipeline {
    let model = try await Llavero.standard.model(configuration.model)
    let counter = OnDeviceTokenCounter()
    let chunkBudget = ChunkBudget(
      contextSize: counter.contextSize, reservedForOutput: reservedForOutput,
      overhead: try await BaselineFactExtractor.overhead(member: member, counter: counter))
    let factBudget =
      counter.contextSize - reservedForOutput
      - (try await BaselineSummarizer.overhead(counter: counter))
    return CharacterSummaryPipeline(
      corpus: corpus, chunker: SceneChunker(budget: chunkBudget, counter: counter),
      extractor: BaselineFactExtractor(model: model, maximumResponseTokens: reservedForOutput),
      summarizer: BaselineSummarizer(
        model: model, factBudget: factBudget, counter: counter,
        maximumResponseTokens: reservedForOutput))
  }
}
