import Foundation

/// What ``QuoteVerifier`` decided about one quote.
public enum QuoteVerdict: Sendable, Equatable, Codable {
  /// The quote is in the cited scene, inside the block starting at `line`
  /// (1-based).
  case verified(line: Int)
  /// Nothing is left of the quote after normalization.
  case emptyQuote
  /// No episode has the cited name.
  case unknownEpisode
  /// The episode has no scene with the cited number.
  case unknownScene
  /// The scene exists but doesn't hold the quote. `foundIn` lists the
  /// scenes that do, if any: a quote cited to the wrong scene.
  case notInScene(foundIn: [SceneCitation])

  public var isVerified: Bool {
    if case .verified = self { return true }
    return false
  }
}

/// Checks a quote against the screenplay text, with no model involved.
///
/// ## The rule
///
/// A quote is verified when, after normalization, it appears inside **one
/// block** of the cited scene, starting and ending on word boundaries.
///
/// - **Normalization** (``QuoteText/normalize(_:)``): curly quotes become
///   straight; `--`, `—`, `–` and a spaced ` - ` become one dash; `…` becomes
///   `...`; Fountain emphasis (`*`, `_`) is dropped; every run of whitespace,
///   line breaks included, becomes one space. Case is kept: a quote is
///   verbatim or it is nothing.
/// - **Parentheticals.** A dialogue block is matched twice: with its
///   parenthetical lines (`(beat)`) and without them. A quote may include one
///   or skip one.
/// - **Cues.** The cue line is never part of the text. A quote that runs from
///   one speaker's line into the next speaker's crosses a cue, so it spans two
///   blocks and is rejected: it would put one character's words in another's
///   mouth.
/// - **Paraphrase** is rejected: only a substring matches.
/// - Surrounding quotation marks on the quote itself are dropped.
public struct QuoteVerifier: Sendable {

  /// The scenes, by episode and SN-1 number.
  private let scenes: [SceneCitation: SceneSource]
  private let episodes: Set<String>
  /// Every scene in corpus order, for locating a quote cited to the wrong one.
  private let ordered: [SceneSource]

  public init(scenes: [SceneSource]) {
    var byCitation: [SceneCitation: SceneSource] = [:]
    for scene in scenes where byCitation[scene.citation] == nil {
      byCitation[scene.citation] = scene
    }
    self.scenes = byCitation
    self.episodes = Set(scenes.map(\.citation.episode))
    self.ordered = scenes
  }

  /// Verifies every scene of `corpus`.
  public init(corpus: EvidenceCorpus) {
    self.init(scenes: corpus.scenes())
  }

  public func verify(_ quote: String, at citation: SceneCitation) -> QuoteVerdict {
    let needle = QuoteText.normalize(QuoteText.unwrap(quote))
    guard !needle.isEmpty else { return .emptyQuote }
    guard episodes.contains(citation.episode) else { return .unknownEpisode }
    guard let scene = scenes[citation] else { return .unknownScene }

    if let line = Self.match(needle, in: scene) { return .verified(line: line) }
    let elsewhere = ordered.filter { $0.citation != citation && Self.match(needle, in: $0) != nil }
    return .notInScene(foundIn: elsewhere.map(\.citation))
  }

  /// Splits `facts` into those whose quotes verify and those that don't,
  /// each dropped fact with its verdict.
  public func partition(_ facts: [CharacterFact]) -> (
    verified: [CharacterFact], dropped: [(fact: CharacterFact, verdict: QuoteVerdict)]
  ) {
    var verified: [CharacterFact] = []
    var dropped: [(fact: CharacterFact, verdict: QuoteVerdict)] = []
    for fact in facts {
      let verdict = verify(fact.quote, at: fact.citation)
      if verdict.isVerified {
        verified.append(fact)
      } else {
        dropped.append((fact, verdict))
      }
    }
    return (verified, dropped)
  }

  /// The 1-based line of the first block in `scene` holding `needle`.
  static func match(_ needle: String, in scene: SceneSource) -> Int? {
    for block in scene.blocks {
      let views = [block.body, block.spoken]
      for view in views {
        let haystack = QuoteText.normalize(view.joined(separator: "\n"))
        if QuoteText.contains(haystack, needle) { return block.line }
      }
    }
    return nil
  }
}

/// Text normalization shared by quote verification.
public enum QuoteText {

  /// Folds the typographic forms a model and a writer disagree on. See
  /// ``QuoteVerifier`` for the rule.
  public static func normalize(_ text: String) -> String {
    var result = text
    for (from, to) in [
      ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201A}", "'"), ("\u{201B}", "'"),
      ("\u{2032}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""),
      ("\u{2033}", "\""), ("\u{2026}", "..."), ("*", ""), ("_", ""),
    ] {
      result = result.replacingOccurrences(of: from, with: to)
    }
    // Every dash form, with the spaces around it, becomes one em dash.
    result = result.replacingOccurrences(
      of: "\\s*(?:--+|\u{2014}|\u{2013})\\s*|\\s+-\\s+", with: "\u{2014}",
      options: .regularExpression)
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespaces)
  }

  /// `quote` without one pair of surrounding quotation marks.
  static func unwrap(_ quote: String) -> String {
    let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
    let marks: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'")]
    for (open, close) in marks
    where trimmed.count >= 2 && trimmed.first == open && trimmed.last == close {
      return String(trimmed.dropFirst().dropLast())
    }
    return trimmed
  }

  /// `true` when `needle` occurs in `haystack` starting and ending on word
  /// boundaries: the characters just outside the match are not letters or
  /// digits.
  static func contains(_ haystack: String, _ needle: String) -> Bool {
    guard let first = needle.first, let last = needle.last else { return false }
    var searchStart = haystack.startIndex
    while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
      let before =
        range.lowerBound > haystack.startIndex
        ? haystack[haystack.index(before: range.lowerBound)] : nil
      let after = range.upperBound < haystack.endIndex ? haystack[range.upperBound] : nil
      // A boundary matters only where the quote itself starts or ends on a
      // letter or digit: "-- and" may follow a word directly.
      let startsOnBoundary = !isWordCharacter(first) || before.map(isWordCharacter) != true
      let endsOnBoundary = !isWordCharacter(last) || after.map(isWordCharacter) != true
      if startsOnBoundary && endsOnBoundary { return true }
      searchStart = haystack.index(after: range.lowerBound)
    }
    return false
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }
}
