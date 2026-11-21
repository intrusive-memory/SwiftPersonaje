import Foundation
import NaturalLanguage

/// How one summary sentence traces back to facts.
public struct SentenceTrace: Sendable, Equatable, Codable {
  public let sentence: String
  /// The facts that support the sentence.
  public let supportingFactIDs: [String]
  /// IDs the sentence cites that aren't among the facts given.
  public let unknownFactIDs: [String]

  public var isSupported: Bool { !supportingFactIDs.isEmpty }
}

/// The traceability of a whole summary.
public struct TraceabilityReport: Sendable, Equatable, Codable {
  public let sentences: [SentenceTrace]

  public var unsupported: [SentenceTrace] { sentences.filter { !$0.isSupported } }
  public var isFullyTraceable: Bool { unsupported.isEmpty }
  /// Supported sentences over all sentences; 1 for an empty summary.
  public var rate: Double {
    sentences.isEmpty
      ? 1 : Double(sentences.count - unsupported.count) / Double(sentences.count)
  }
}

/// Flags summary sentences that no fact supports. Deterministic; no model.
///
/// ## How support is decided
///
/// It's a lexical check, kept simple on purpose:
///
/// 1. **Candidates.** A sentence that cites facts (``SummarySentence/factIDs``)
///    may be supported only by those facts. A cited ID that isn't among the
///    facts given is reported in ``SentenceTrace/unknownFactIDs`` and supports
///    nothing. A sentence with no citations (a hand-written summary) may be
///    supported by any fact.
/// 2. **Content words.** Words are lowercased letters and digits, at least
///    three long, with common English function words and the member's own
///    name removed, and a plural or verb ending (`-s`, `-es`, `-ed`, `-ing`)
///    stripped. A fact's words come from its statement and its quote.
/// 3. **Support.** A fact supports a sentence when they share at least
///    `min(minimumSharedWords, the sentence's word count)` content words. A
///    sentence with no content words at all is supported by any candidate.
///
/// This catches a sentence about something no fact mentions. It doesn't prove
/// that a fact *entails* the sentence: "Wren is not the keeper" shares its
/// words with "Wren is the keeper". The `must-not-say` lists in the
/// evaluation suite cover the contradictions this misses.
public enum SummaryTraceability {

  public static func check(
    _ summary: CharacterSummary, facts: [CharacterFact], minimumSharedWords: Int = 2
  ) -> TraceabilityReport {
    let byID = Dictionary(facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let nameWords = Set(words(in: summary.member))
    let factWords = Dictionary(
      facts.map { ($0.id, Set(words(in: $0.statement + " " + $0.quote)).subtracting(nameWords)) },
      uniquingKeysWith: { first, _ in first })

    let traces = summary.sentences.map { sentence -> SentenceTrace in
      let unknown = sentence.factIDs.filter { byID[$0] == nil }
      let candidates =
        sentence.factIDs.isEmpty ? facts.map(\.id) : sentence.factIDs.filter { byID[$0] != nil }
      let sentenceWords = Set(words(in: sentence.text)).subtracting(nameWords)
      let needed = min(minimumSharedWords, sentenceWords.count)
      let supporting = candidates.filter { id in
        (factWords[id] ?? []).intersection(sentenceWords).count >= needed
      }
      return SentenceTrace(
        sentence: sentence.text, supportingFactIDs: supporting, unknownFactIDs: unknown)
    }
    return TraceabilityReport(sentences: traces)
  }

  /// Checks prose with no citations: each sentence of `text` may be
  /// supported by any fact.
  public static func check(
    text: String, member: String, facts: [CharacterFact], minimumSharedWords: Int = 2
  ) -> TraceabilityReport {
    let summary = CharacterSummary(
      member: member, sentences: sentences(in: text).map { SummarySentence(text: $0) })
    return check(summary, facts: facts, minimumSharedWords: minimumSharedWords)
  }

  /// `text`'s sentences, by NaturalLanguage's sentence tokenizer, trimmed.
  public static func sentences(in text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    return tokenizer.tokens(for: text.startIndex..<text.endIndex)
      .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// The content words of `text`. See the type's documentation.
  static func words(in text: String) -> [String] {
    QuoteText.normalize(text).lowercased()
      .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
      .map(String.init)
      .filter { $0.count >= 3 && !stopWords.contains($0) }
      .map(stem)
  }

  static func stem(_ word: String) -> String {
    for suffix in ["ing", "ed", "es", "s"] where word.hasSuffix(suffix) {
      let stem = String(word.dropLast(suffix.count))
      if stem.count >= 3 { return stem }
    }
    return word
  }

  static let stopWords: Set<String> = [
    "the", "and", "but", "for", "nor", "yet", "with", "from", "into", "onto", "upon", "about",
    "over", "under", "after", "before", "this", "that", "these", "those", "his", "her", "hers",
    "him", "she", "they", "them", "their", "theirs", "its", "our", "ours", "your", "yours",
    "who", "whom", "whose", "which", "what", "when", "where", "why", "how", "are", "was",
    "were", "been", "being", "has", "have", "had", "does", "did", "doing", "will", "would",
    "shall", "should", "can", "could", "may", "might", "must", "not", "all", "any", "each",
    "both", "more", "most", "other", "some", "such", "only", "own", "same", "than", "too",
    "very", "just", "also", "out", "off", "again", "then", "once", "there", "here", "one",
    "himself", "herself", "themselves", "itself", "while", "because",
    "through", "during", "between", "against", "without", "within", "never", "always",
  ]
}
