import Foundation
import SwiftBruja

/// A local MLX model run in-process through SwiftBruja, for comparing open
/// models with Apple's. Selected with `MODEL=bruja:<model id>`, e.g.
/// `bruja:mlx-community/Qwen3.5-9B-MLX-4bit`; the model must already be
/// downloaded (`bruja download -m <id>`).
///
/// Temperature 0 (greedy, like the FoundationModels runs) and thinking off:
/// the task is copying and stating, and a thinking trace would spend the
/// response budget. Any `<think>…</think>` block left in a response is
/// removed before parsing.
public struct BrujaGenerator: TextGenerating {
  public let modelID: String

  public init(modelID: String) {
    self.modelID = modelID
  }

  public func respond(instructions: String, prompt: String, maximumResponseTokens: Int)
    async throws -> String
  {
    let response = try await Bruja.query(
      prompt, model: modelID, temperature: 0, maxTokens: maximumResponseTokens,
      system: instructions, thinking: .off)
    return Self.withoutThinking(response)
  }

  public static func withoutThinking(_ text: String) -> String {
    text.replacingOccurrences(
      of: "<think>[\\s\\S]*?(?:</think>|$)", with: "", options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public enum BrujaGeneratorError: Error, CustomStringConvertible {
  case noModel

  public var description: String {
    switch self {
    case .noModel: return "MODEL=bruja: needs a model id, e.g. bruja:mlx-community/Qwen3.5-9B-MLX-4bit"
    }
  }
}
