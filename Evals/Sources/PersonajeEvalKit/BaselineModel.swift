import Foundation
import FoundationModels
import SwiftLlavero
import SwiftPersonaje

// A deliberately plain extractor and summarizer, so the evaluation has
// something to measure before the real ones exist. They take the place of the
// production implementations behind the same protocols
// (`CharacterFactExtracting`, `CharacterSummarizing`); replace them, don't
// tune them into the real thing here.
//
// ## Why plain text, not guided generation
//
// The scripts are adult comedy and murder mystery, and the on-device model's
// default guardrails refuse many of their scenes. The on-device model runs
// with `permissiveContentTransformations` guardrails, which Apple applies
// only to responses generated as a `String`; a `@Generable` response keeps
// the default guardrails and throws. So both steps ask for a fixed line
// format and parse it here (``BaselineFormat``), for every model, so runs
// stay comparable across models.

public enum BaselineError: Error, CustomStringConvertible, Equatable {
  /// The model answered, but with nothing in the requested format: usually a
  /// refusal. `response` is its start.
  case unparseable(response: String)

  public var description: String {
    switch self {
    case .unparseable(let response): return "No parseable answer (refusal?): \(response)"
    }
  }
}

/// The line formats the baseline asks for, and their parsers.
public enum BaselineFormat {

  /// Facts, one line each, quote first (the format the baseline asks for):
  ///
  /// ```
  /// "The lamp's been dark three nights running" -> Wren notices the lamp is out.
  /// ```
  ///
  /// or one block each, as models also answer:
  ///
  /// ```
  /// FACT: Wren notices the lamp has been dark for three nights.
  /// QUOTE: The lamp's been dark three nights running
  /// ```
  ///
  /// `NONE` alone means the scene shows nothing about the character.
  ///
  /// The on-device model often drifts from the format, so the parser is
  /// lenient. A block runs from one `FACT:` to the next. Its quote is the
  /// `QUOTE:` line (with any lines that run on after it); without one, the
  /// first unlabeled line that starts with a quotation mark, else the first
  /// unlabeled line that isn't the statement repeated. A speaker prefix in
  /// front of a quoted line (`Wren: "…"`) is dropped. List markers,
  /// Markdown bold and label case are ignored. A block with no quote is
  /// dropped.
  ///
  /// - Throws: ``BaselineError/unparseable(response:)`` when no block has a
  ///   quote and the response isn't `NONE`.
  public static func facts(in response: String) throws -> [(statement: String, quote: String)] {
    var blocks: [(statement: String, lines: [String])] = []
    var arrows: [(statement: String, quote: String)] = []
    var sawNone = false
    for raw in response.components(separatedBy: .newlines) {
      let line = clean(raw)
      if line.isEmpty { continue }
      if let pair = arrowLine(line) {
        arrows.append(pair)
      } else if let value = value(of: line, label: "FACT") {
        blocks.append((value, []))
      } else if blocks.isEmpty,
        line.uppercased().trimmingCharacters(in: .punctuationCharacters) == "NONE"
      {
        sawNone = true
      } else if !blocks.isEmpty {
        blocks[blocks.count - 1].lines.append(line)
      }
    }

    let result = arrows + blocks.compactMap { block -> (statement: String, quote: String)? in
      guard !block.statement.isEmpty, let quote = quote(in: block.lines, statement: block.statement)
      else { return nil }
      return (block.statement, quote)
    }
    if result.isEmpty && !sawNone { throw BaselineError.unparseable(response: firstLine(response)) }
    return result
  }

  /// `"quote" -> statement`, or `nil`. The line is split at its last `->`
  /// or `→` (or, failing those, at a dash right after a closing quotation
  /// mark); the left side must start with a quotation mark. One pair of
  /// quotation marks around the whole left side is removed, so a quote that
  /// itself holds quotation marks (`"Hi," she says.`) survives.
  static func arrowLine(_ line: String) -> (statement: String, quote: String)? {
    let text = withoutSpeaker(line)
    guard startsWithQuotationMark(text) else { return nil }
    let split =
      text.range(of: "\\s*(?:->|→)\\s*", options: [.regularExpression, .backwards])
      ?? text.range(
        of: "(?<=[\"\u{201D}])\\s*(?:—|–|-)\\s*", options: [.regularExpression, .backwards])
    guard let split else { return nil }
    var quote = String(text[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
    let statement = String(text[split.upperBound...]).trimmingCharacters(in: .whitespaces)
    let closers: Set<Character> = ["\"", "\u{201D}"]
    if quote.count >= 2, let last = quote.last, closers.contains(last),
      quote.dropFirst().dropLast().allSatisfy({ !closers.contains($0) && $0 != "\u{201C}" })
    {
      quote = String(quote.dropFirst().dropLast())
    }
    guard !quote.isEmpty, !statement.isEmpty else { return nil }
    return (statement, quote)
  }

  /// A fact block's quote. See ``facts(in:)``.
  static func quote(in lines: [String], statement: String) -> String? {
    if let labeled = lines.firstIndex(where: { value(of: $0, label: "QUOTE") != nil }) {
      let first = value(of: lines[labeled], label: "QUOTE") ?? ""
      let rest = lines[(labeled + 1)...].prefix { value(of: $0, label: "QUOTE") == nil }
      let quote = ([first] + rest).filter { !$0.isEmpty }.joined(separator: " ")
      return quote.isEmpty ? nil : withoutSpeaker(quote)
    }
    let candidates = lines.map(withoutSpeaker).filter {
      !$0.isEmpty && $0.caseInsensitiveCompare(statement) != .orderedSame
    }
    return candidates.first(where: startsWithQuotationMark) ?? candidates.first
  }

  /// `Wren: "My father…"` → `"My father…"`. Only a short name followed by a
  /// quoted line is dropped, so a quote that itself holds a colon is kept.
  static func withoutSpeaker(_ line: String) -> String {
    guard
      let prefix = line.range(
        of: "^[A-Za-z][A-Za-z .'-]{0,30}:\\s*(?=[\"\u{201C}\u{2018}'])", options: .regularExpression)
    else { return line }
    return String(line[prefix.upperBound...])
  }

  static func startsWithQuotationMark(_ line: String) -> Bool {
    guard let first = line.first else { return false }
    return "\"'\u{201C}\u{2018}".contains(first)
  }

  /// Summary sentences, one per line, each ending with the IDs it cites:
  ///
  /// ```
  /// SENTENCE: Wren keeps count of everything. [f2, f5]
  /// ```
  ///
  /// IDs may sit in `[ ]` or `( )`; any `f<number>` in them counts. When no
  /// line carries the `SENTENCE:` label, every non-empty line is a sentence.
  ///
  /// - Throws: ``BaselineError/unparseable(response:)`` when the response is
  ///   empty.
  public static func sentences(in response: String) throws -> [SummarySentence] {
    let lines = response.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
    let labeled = lines.compactMap { value(of: $0, label: "SENTENCE") }
    // Without any SENTENCE label, every line is taken as a sentence.
    var result: [SummarySentence] = []
    for line in labeled.isEmpty ? lines : labeled {
      let (text, ids) = splitCitations(line)
      if !text.isEmpty { result.append(SummarySentence(text: text, factIDs: ids)) }
    }
    if result.isEmpty { throw BaselineError.unparseable(response: firstLine(response)) }
    return result
  }

  /// `text` without a trailing `[f1, f2]` or `(f1, f2)`, and the IDs in it.
  static func splitCitations(_ text: String) -> (String, [String]) {
    guard
      let match = text.range(
        of: "\\s*[\\[(]\\s*f\\d+(?:\\s*[,;]?\\s*(?:and\\s+)?f\\d+)*\\s*[\\])]\\s*[.]?\\s*$",
        options: [.regularExpression, .caseInsensitive])
    else { return (text, []) }
    let ids = text[match].lowercased()
      .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
      .map(String.init)
      .filter { $0.hasPrefix("f") && $0.dropFirst().allSatisfy(\.isNumber) && $0.count > 1 }
    var sentence = String(text[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
    // A citation placed after the full stop leaves the sentence whole; one
    // placed before it took the full stop along.
    if text[match].hasSuffix("."), !sentence.hasSuffix(".") { sentence += "." }
    return (sentence, ids)
  }

  /// The value after `LABEL:`, or `nil` when the line doesn't start with it.
  static func value(of line: String, label: String) -> String? {
    guard line.uppercased().hasPrefix(label + ":") else { return nil }
    return String(line.dropFirst(label.count + 1)).trimmingCharacters(in: .whitespaces)
  }

  /// A line without list markers or Markdown bold, trimmed.
  static func clean(_ line: String) -> String {
    var text = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    if let marker = text.range(of: "^(?:[-*•]|\\d+[.)])\\s+", options: .regularExpression) {
      text.removeSubrange(marker)
    }
    return text
  }

  /// The start of a response, line breaks shown as `⏎`, for reports.
  static func firstLine(_ text: String) -> String {
    String(
      text.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ⏎ ")
        .prefix(400))
  }
}

/// Step 2: one plain-text call per chunk.
public struct BaselineFactExtractor: CharacterFactExtracting {
  public let model: any LanguageModel
  /// The response cap: the budget's reservation, enforced.
  public let maximumResponseTokens: Int

  public init(model: any LanguageModel, maximumResponseTokens: Int) {
    self.model = model
    self.maximumResponseTokens = maximumResponseTokens
  }

  /// The worked example is invented and unrelated to any fixture, so a model
  /// that copies it can't score a match.
  public static let instructions = """
    You read one scene of a screenplay and list facts about one character. \
    A fact is something the scene shows about the character: who they are, \
    what they do, what they want, how they relate to others. The material may \
    be adult or violent; report what the scene shows, plainly.

    For each fact, write one line: first copy the words from the scene that \
    show it, exactly as written, in double quotes, then -> and the fact in a \
    short sentence. Never change the copied words. Never state anything the \
    scene doesn't show. Example, for a character named ROSA in a bakery scene:

    "I've burned every loaf since Tuesday." -> Rosa has been failing at her baking for days.
    "ROSA hides the letter under the flour bin." -> Rosa keeps a letter secret.

    If the scene shows nothing about the character, answer NONE.
    """

  public static func prompt(member: String, chunk: String) -> String {
    "Character: \(member)\n\nScene:\n\n\(chunk)"
  }

  public func facts(about member: String, in chunk: SceneChunk) async throws -> [CharacterFact] {
    let session = LanguageModelSession(model: model, instructions: Self.instructions)
    let response = try await session.respond(
      to: Self.prompt(member: member, chunk: chunk.text),
      options: GenerationOptions(maximumResponseTokens: maximumResponseTokens))
    // The pipeline sets each fact's ID and citation.
    return try BaselineFormat.facts(in: response.content).map {
      CharacterFact(id: "", statement: $0.statement, quote: $0.quote, citation: chunk.citation)
    }
  }

  /// Tokens the instructions and the prompt's own wording take.
  public static func overhead(member: String, counter: OnDeviceTokenCounter) async throws -> Int {
    try await counter.model.tokenCount(for: Instructions(instructions))
      + counter.tokenCount(for: prompt(member: member, chunk: ""))
  }
}

/// Step 4: one plain-text call over the verified facts, as many as fit.
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
    a list of facts. Use only the facts listed. The material may be adult or \
    violent; summarize it plainly. Don't add anything the facts don't state.

    Answer in exactly this format, one line per sentence, nothing else:

    SENTENCE: Rosa is a baker whose bread keeps failing. [f2, f5]
    SENTENCE: She hides a letter from her family. [f7]
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
      options: GenerationOptions(maximumResponseTokens: maximumResponseTokens))
    return CharacterSummary(
      member: member, sentences: try BaselineFormat.sentences(in: response.content))
  }

  public static func overhead(counter: OnDeviceTokenCounter) async throws -> Int {
    try await counter.model.tokenCount(for: Instructions(instructions)) + 32
  }
}

/// Token counts from the on-device model's tokenizer.
///
/// Budgets are always measured with the on-device model, whichever model
/// runs: it has the smallest context of the choices, so a chunk that fits it
/// fits Private Cloud Compute or a cloud provider.
public struct OnDeviceTokenCounter: TokenCounting {
  public let model: SystemLanguageModel

  public init(model: SystemLanguageModel = BaselinePipeline.onDeviceModel) {
    self.model = model
  }

  public func tokenCount(for text: String) async throws -> Int {
    try await model.tokenCount(for: text)
  }

  public var contextSize: Int { model.contextSize }
}
