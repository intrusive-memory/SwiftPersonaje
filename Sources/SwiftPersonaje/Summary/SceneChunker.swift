import Foundation

/// Counts the tokens a model would see for a text.
///
/// The on-device model's count comes from FoundationModels
/// (`SystemLanguageModel.tokenCount(for:)`, macOS 26.4); this package doesn't
/// link FoundationModels, so the caller supplies the counter. Tests use a
/// deterministic one.
public protocol TokenCounting: Sendable {
  func tokenCount(for text: String) async throws -> Int
}

/// How much of a model's context one chunk may use.
///
/// A model's context (`SystemLanguageModel.contextSize` for the on-device
/// model) holds the instructions, the output schema, the prompt and the
/// response together.
public struct ChunkBudget: Sendable, Equatable {
  /// The model's whole context, in tokens.
  public let contextSize: Int
  /// Tokens kept free for the response.
  public let reservedForOutput: Int
  /// Tokens the instructions, the schema and the prompt's own wording take.
  public let overhead: Int

  public init(contextSize: Int, reservedForOutput: Int, overhead: Int) {
    self.contextSize = contextSize
    self.reservedForOutput = reservedForOutput
    self.overhead = overhead
  }

  /// Tokens left for the chunk's screenplay text.
  public var inputLimit: Int { contextSize - reservedForOutput - overhead }
}

/// One piece of a character's material: one scene, or one part of a scene
/// too large for one call.
public struct SceneChunk: Sendable, Equatable, Codable {
  /// The scene every line of ``text`` comes from. Every part of a split
  /// scene carries it.
  public let citation: SceneCitation
  /// 1-based part number, and the scene's number of parts.
  public let part: Int
  public let partCount: Int
  /// The text the model sees: the slugline (marked `(CONTINUED)` on later
  /// parts), then the blocks, as written, separated by blank lines.
  public let text: String
  /// ``text``'s size, by the budget's counter.
  public let tokenCount: Int
  /// The first and last file lines (1-based) of the blocks in this part.
  public let firstLine: Int
  public let lastLine: Int
}

public enum SceneChunkerError: Error, Equatable, CustomStringConvertible {
  /// The budget leaves no room for any screenplay text.
  case noRoomForInput(ChunkBudget)
  /// One line, with its slugline and cue, is larger than the budget.
  case lineExceedsBudget(SceneCitation, line: Int, tokens: Int, limit: Int)

  public var description: String {
    switch self {
    case .noRoomForInput(let budget):
      return
        "A context of \(budget.contextSize) tokens leaves no room for screenplay text after \(budget.reservedForOutput) for output and \(budget.overhead) overhead."
    case .lineExceedsBudget(let citation, let line, let tokens, let limit):
      return
        "Line \(line) of \(citation) takes \(tokens) tokens; a chunk holds \(limit). It can't be split without cutting the line."
    }
  }
}

/// Step 1 of the pipeline: cuts scenes into chunks that fit a model's
/// context.
///
/// - Each scene becomes one chunk when it fits ``ChunkBudget/inputLimit``.
/// - A larger scene is split between blocks; a block that doesn't fit alone
///   is split between its lines, and each later piece of a dialogue block
///   repeats the cue, so the speaker is never lost. A line is never cut.
/// - Every part carries the scene's citation, and the slugline at its top.
/// - Scenes are never packed together: a fact's citation is its chunk's.
///
/// Pass ``EvidenceCorpus/scenes(featuring:)`` to chunk only the scenes a
/// member appears in.
public struct SceneChunker: Sendable {
  public let budget: ChunkBudget
  public let counter: any TokenCounting

  public init(budget: ChunkBudget, counter: any TokenCounting) {
    self.budget = budget
    self.counter = counter
  }

  public func chunks(of scenes: [SceneSource]) async throws -> [SceneChunk] {
    guard budget.inputLimit > 0 else { throw SceneChunkerError.noRoomForInput(budget) }
    var result: [SceneChunk] = []
    for scene in scenes where !scene.blocks.isEmpty {
      result += try await chunks(of: scene)
    }
    return result
  }

  // MARK: - One scene

  /// A unit that is never split: a whole block, or one or more lines of a
  /// block, the cue repeated in front.
  struct Piece: Equatable {
    var lines: [String]
    var firstLine: Int
    var lastLine: Int
  }

  func chunks(of scene: SceneSource) async throws -> [SceneChunk] {
    let limit = budget.inputLimit
    var parts: [[Piece]] = []
    var current: [Piece] = []

    for block in scene.blocks {
      let whole = Piece(
        lines: block.lines, firstLine: block.line, lastLine: block.line + block.lines.count - 1)
      let pieces =
        try await count(render(scene, [whole], continued: true)) <= limit
        ? [whole] : try await split(block, of: scene)

      for piece in pieces {
        if try await count(render(scene, current + [piece], continued: !parts.isEmpty)) <= limit {
          current.append(piece)
        } else {
          if !current.isEmpty { parts.append(current) }
          current = [piece]
        }
      }
    }
    if !current.isEmpty { parts.append(current) }

    var chunks: [SceneChunk] = []
    for (index, pieces) in parts.enumerated() {
      let text = render(scene, pieces, continued: index > 0)
      chunks.append(
        SceneChunk(
          citation: scene.citation, part: index + 1, partCount: parts.count, text: text,
          tokenCount: try await count(text), firstLine: pieces[0].firstLine,
          lastLine: pieces.last?.lastLine ?? pieces[0].lastLine))
    }
    return chunks
  }

  /// A block too large for one chunk, as pieces that each fit alone: its
  /// lines, greedily grouped, a dialogue block's cue in front of every piece.
  func split(_ block: SourceBlock, of scene: SceneSource) async throws -> [Piece] {
    let limit = budget.inputLimit
    let cue = block.cueLine.map { [$0] } ?? []
    let firstBodyLine = block.line + cue.count
    var pieces: [Piece] = []
    var current: Piece?

    for (offset, line) in block.body.enumerated() {
      let lineNumber = firstBodyLine + offset
      if var grown = current {
        grown.lines.append(line)
        grown.lastLine = lineNumber
        if try await count(render(scene, [grown], continued: true)) <= limit {
          current = grown
          continue
        }
        pieces.append(current!)
      }
      let alone = Piece(lines: cue + [line], firstLine: lineNumber, lastLine: lineNumber)
      let tokens = try await count(render(scene, [alone], continued: true))
      guard tokens <= limit else {
        throw SceneChunkerError.lineExceedsBudget(
          scene.citation, line: lineNumber, tokens: tokens, limit: limit)
      }
      current = alone
    }
    if let current { pieces.append(current) }
    // The first piece starts at the cue's own line.
    if !pieces.isEmpty { pieces[0].firstLine = block.line }
    return pieces
  }

  /// The chunk text for `pieces` of `scene`. A continued part's slugline is
  /// marked `(CONTINUED)`; the marker is counted whether or not it's used, so
  /// a piece that fits one part fits any.
  func render(_ scene: SceneSource, _ pieces: [Piece], continued: Bool) -> String {
    var sections: [String] = []
    if let heading = scene.heading {
      sections.append(continued ? "\(heading) (CONTINUED)" : heading)
    }
    sections += pieces.map { $0.lines.joined(separator: "\n") }
    return sections.joined(separator: "\n\n")
  }

  private func count(_ text: String) async throws -> Int {
    try await counter.tokenCount(for: text)
  }
}
