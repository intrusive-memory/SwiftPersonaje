import Foundation
import FoundationModels
import SwiftLlavero
import SwiftPersonaje

// A deliberately plain extractor and summarizer, so the evaluation has
// something to measure before the real ones exist. They take the place of the
// production implementations behind the same protocols
// (`CharacterFactExtracting`, `CharacterSummarizing`); replace them, don't
// tune them into the real thing here.

@Generable
struct ExtractedFacts {
  @Guide(description: "Facts about the character that this scene shows. Empty if there are none.")
  var facts: [ExtractedFact]
}

@Generable
struct ExtractedFact {
  @Guide(description: "One fact about the character, as a short plain sentence.")
  var statement: String
  @Guide(
    description:
      "Words copied exactly, character for character, from the scene, that show the fact. No paraphrase."
  )
  var quote: String
}

@Generable
struct GeneratedSummary {
  @Guide(description: "Two or three sentences summarizing the character.", .count(2...3))
  var sentences: [GeneratedSentence]
}

@Generable
struct GeneratedSentence {
  @Guide(description: "One sentence of the summary. Claim nothing the cited facts don't state.")
  var text: String
  @Guide(description: "The IDs of the facts this sentence is built from, e.g. f3.")
  var factIDs: [String]
}

/// Step 2: one guided-generation call per chunk.
public struct BaselineFactExtractor: CharacterFactExtracting {
  public let model: any LanguageModel
  /// The response cap: the budget's reservation, enforced.
  public let maximumResponseTokens: Int

  public init(model: any LanguageModel, maximumResponseTokens: Int) {
    self.model = model
    self.maximumResponseTokens = maximumResponseTokens
  }

  public static let instructions = """
    You read one scene of a screenplay and list facts about one character. \
    A fact is something the scene shows about the character: who they are, \
    what they do, what they want, how they relate to others. \
    For each fact, copy a quote from the scene exactly as written. \
    Never paraphrase a quote. Never state anything the scene doesn't show.
    """

  public static func prompt(member: String, chunk: String) -> String {
    "Character: \(member)\n\nScene:\n\n\(chunk)"
  }

  public func facts(about member: String, in chunk: SceneChunk) async throws -> [CharacterFact] {
    let session = LanguageModelSession(model: model, instructions: Self.instructions)
    let response = try await session.respond(
      to: Self.prompt(member: member, chunk: chunk.text), generating: ExtractedFacts.self,
      options: GenerationOptions(maximumResponseTokens: maximumResponseTokens))
    // The pipeline sets each fact's ID and citation.
    return response.content.facts.map {
      CharacterFact(id: "", statement: $0.statement, quote: $0.quote, citation: chunk.citation)
    }
  }

  /// Tokens the instructions, the schema and the prompt's own wording take.
  public static func overhead(member: String, counter: OnDeviceTokenCounter) async throws -> Int {
    let model = SystemLanguageModel.default
    return try await model.tokenCount(for: Instructions(instructions))
      + model.tokenCount(for: ExtractedFacts.generationSchema)
      + counter.tokenCount(for: prompt(member: member, chunk: ""))
  }
}

/// Step 4: one call over the verified facts, as many as fit the budget.
public struct BaselineSummarizer: CharacterSummarizing {
  public let model: any LanguageModel
  /// Tokens the listed facts may take.
  public let factBudget: Int
  public let counter: OnDeviceTokenCounter
  public let maximumResponseTokens: Int

  public init(
    model: any LanguageModel, factBudget: Int, counter: OnDeviceTokenCounter,
    maximumResponseTokens: Int
  ) {
    self.model = model
    self.factBudget = factBudget
    self.counter = counter
    self.maximumResponseTokens = maximumResponseTokens
  }

  public static let instructions = """
    You write a two- or three-sentence summary of a screenplay character from \
    a list of facts. Use only the facts listed. Every sentence cites the IDs \
    of the facts it is built from. Don't add anything the facts don't state.
    """

  public func summary(of member: String, from facts: [CharacterFact]) async throws
    -> CharacterSummary
  {
    var lines: [String] = []
    var used = 0
    for fact in facts {
      let line = "\(fact.id): \(fact.statement) (\"\(fact.quote)\")"
      let tokens = try await counter.tokenCount(for: line)
      if used + tokens > factBudget { break }
      lines.append(line)
      used += tokens
    }
    let session = LanguageModelSession(model: model, instructions: Self.instructions)
    let response = try await session.respond(
      to: "Character: \(member)\n\nFacts:\n\(lines.joined(separator: "\n"))",
      generating: GeneratedSummary.self,
      options: GenerationOptions(maximumResponseTokens: maximumResponseTokens))
    return CharacterSummary(
      member: member,
      sentences: response.content.sentences.map {
        SummarySentence(text: $0.text, factIDs: $0.factIDs)
      })
  }

  public static func overhead(counter: OnDeviceTokenCounter) async throws -> Int {
    let model = SystemLanguageModel.default
    return try await model.tokenCount(for: Instructions(instructions))
      + model.tokenCount(for: GeneratedSummary.generationSchema) + 32
  }
}

/// Token counts from the on-device model's tokenizer.
///
/// Budgets are always measured with the on-device model, whichever model
/// runs: it has the smallest context of the choices, so a chunk that fits it
/// fits Private Cloud Compute or a cloud provider.
public struct OnDeviceTokenCounter: TokenCounting {
  public init() {}

  public func tokenCount(for text: String) async throws -> Int {
    try await SystemLanguageModel.default.tokenCount(for: text)
  }

  public var contextSize: Int { SystemLanguageModel.default.contextSize }
}
