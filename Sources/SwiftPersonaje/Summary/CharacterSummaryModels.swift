import Foundation

/// One fact about a character, with the words in the script that support it.
///
/// The extractor states the fact and quotes the script; the citation comes
/// from the chunk the fact was extracted from (``SceneChunk/citation``), not
/// from the model, so a model can't cite a scene it never saw.
public struct CharacterFact: Sendable, Hashable, Codable, Identifiable {
  /// Unique within one run, e.g. `"f12"`. Summary sentences cite it.
  public let id: String
  /// The fact, in the extractor's words: `"Wren keeps the lighthouse lamp."`
  public let statement: String
  /// The script's words, verbatim, that support the statement.
  public let quote: String
  public let citation: SceneCitation

  public init(id: String, statement: String, quote: String, citation: SceneCitation) {
    self.id = id
    self.statement = statement
    self.quote = quote
    self.citation = citation
  }
}

/// One sentence of a summary, with the facts it claims to be built from.
public struct SummarySentence: Sendable, Hashable, Codable {
  public let text: String
  /// ``CharacterFact/id``s. Empty for a summary written without citations
  /// (a hand-written gold summary): every fact may then support it.
  public let factIDs: [String]

  public init(text: String, factIDs: [String] = []) {
    self.text = text
    self.factIDs = factIDs
  }
}

/// A character summary built from verified facts.
public struct CharacterSummary: Sendable, Hashable, Codable {
  /// The member's `character`, as CAST.md names them.
  public let member: String
  public let sentences: [SummarySentence]
  /// How many sentences the summarizer wrote, when it wrote more than it was
  /// asked for and ``sentences`` keeps only the first of them; `nil` when
  /// nothing was cut.
  public let returnedSentenceCount: Int?

  public init(member: String, sentences: [SummarySentence], returnedSentenceCount: Int? = nil) {
    self.member = member
    self.sentences = sentences
    self.returnedSentenceCount = returnedSentenceCount
  }

  /// The summary as prose.
  public var text: String { sentences.map(\.text).joined(separator: " ") }
}

/// Step 2 of the pipeline: facts about `member` in one chunk.
///
/// An implementation returns facts whose ``CharacterFact/citation`` is the
/// chunk's. Quotes are checked afterwards by ``QuoteVerifier``; nothing here
/// is trusted.
public protocol CharacterFactExtracting: Sendable {
  func facts(about member: String, in chunk: SceneChunk) async throws -> [CharacterFact]
}

/// Step 4 of the pipeline: a summary of `member` from verified facts only.
///
/// Every sentence should cite the facts it's built from;
/// ``SummaryTraceability`` checks that it does.
public protocol CharacterSummarizing: Sendable {
  func summary(of member: String, from facts: [CharacterFact]) async throws -> CharacterSummary
}
