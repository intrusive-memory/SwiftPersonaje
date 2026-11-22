import Foundation

/// Where a fact comes from: an episode file and a scene in it.
///
/// `scene` is the SN-1 scene number (``SceneNumbering``), the same number
/// ``EvidenceItem/sceneNumber`` carries. It is `nil` for the material before
/// an episode's first slugline.
public struct SceneCitation: Sendable, Hashable, Codable, CustomStringConvertible {
  /// The episode file's name, as ``EvidenceCorpus/episodeNames`` lists it.
  public let episode: String
  /// The SN-1 scene number, or `nil` before the first slugline.
  public let scene: String?

  public init(episode: String, scene: String?) {
    self.episode = episode
    self.scene = scene
  }

  public var description: String { "\(episode) scene \(scene ?? "-")" }
}

/// One block of a scene, as written in the file.
public struct SourceBlock: Sendable, Equatable, Codable {
  public enum Kind: Sendable, Equatable, Codable {
    /// A dialogue block. ``SourceBlock/lines`` starts with the cue when the
    /// block has one.
    case dialogue(speaker: String?, hasCue: Bool)
    /// An action paragraph.
    case action
    /// Anything else: a transition, a forced `.` line, a centred line.
    case other
  }

  public let kind: Kind
  /// 1-based line of the block's first line in the episode file.
  public let line: Int
  /// The block's lines as written, each trimmed. Never empty.
  public let lines: [String]

  public init(kind: Kind, line: Int, lines: [String]) {
    self.kind = kind
    self.line = line
    self.lines = lines
  }

  /// The block's lines without the cue: what was written under it.
  public var body: [String] {
    if case .dialogue(_, true) = kind { return Array(lines.dropFirst()) }
    return lines
  }

  /// The cue line, for a dialogue block that has one.
  public var cueLine: String? {
    if case .dialogue(_, true) = kind { return lines.first }
    return nil
  }

  /// The speaker, cleaned as SwiftCompartido cleans cues, for dialogue.
  public var speaker: String? {
    if case .dialogue(let speaker, _) = kind { return speaker }
    return nil
  }

  /// The body's spoken lines: parenthetical lines (`(beat)`) left out.
  /// Equal to ``body`` for anything but dialogue.
  public var spoken: [String] {
    guard case .dialogue = kind else { return body }
    return body.filter { !Self.isParenthetical($0) }
  }

  /// The block's text as written, lines joined with `\n`.
  public var text: String { lines.joined(separator: "\n") }

  static func isParenthetical(_ line: String) -> Bool {
    line.count > 1 && line.hasPrefix("(") && line.hasSuffix(")")
  }
}

/// One scene of an episode, slugline to slugline (the scene rule
/// ``EvidenceCorpus`` uses), with its blocks as written in the file.
public struct SceneSource: Sendable, Equatable, Codable {
  public let citation: SceneCitation
  /// The slugline as written, or `nil` before the first slugline.
  public let heading: String?
  /// 1-based line of the slugline, or of the first block when there is none.
  public let line: Int
  public let blocks: [SourceBlock]

  public init(citation: SceneCitation, heading: String?, line: Int, blocks: [SourceBlock]) {
    self.citation = citation
    self.heading = heading
    self.line = line
    self.blocks = blocks
  }
}

extension EvidenceCorpus {

  /// Every scene of every episode, in corpus order.
  ///
  /// Blocks are SwiftCompartido's, cut under the scene rule
  /// (``makeBlocks(elements:located:lines:headings:)``). Each block's text is
  /// taken from the file, from its first line to the next blank line, so a
  /// quote is checked against what the writer typed rather than the parser's
  /// cleaned text. Scenes with no blocks (a slugline followed by another) are
  /// kept, with no blocks.
  public func scenes() -> [SceneSource] {
    episodes.flatMap { Self.scenes(of: $0) }
  }

  /// The scenes `member` appears in, in corpus order.
  ///
  /// A member appears in a scene when one of its dialogue blocks is theirs
  /// (the speaker, cleaned as SwiftCompartido cleans cues, is theirs), or
  /// when an action paragraph names them under the VE-3 rule
  /// (``CapitalisedNames``: the cue's words, in capitals, as whole words).
  public func scenes(featuring member: String) -> [SceneSource] {
    let speaker = EvidenceCue.speaker(of: member)
    let words = CapitalisedNames.words(ofCue: speaker)
    return scenes().filter { scene in
      scene.blocks.contains { block in
        switch block.kind {
        case .dialogue(let blockSpeaker, _):
          return blockSpeaker == speaker
        case .action:
          return CapitalisedNames.names(in: block.text).contains {
            CapitalisedNames.name($0, matches: words)
          }
        case .other:
          return false
        }
      }
    }
  }

  static func scenes(of episode: Episode) -> [SceneSource] {
    var byScene: [Int: [SourceBlock]] = [:]
    for block in episode.blocks {
      byScene[block.scene, default: []].append(sourceBlock(block, in: episode))
    }

    var result: [SceneSource] = []
    if let opening = byScene[-1], !opening.isEmpty {
      result.append(
        SceneSource(
          citation: SceneCitation(episode: episode.name, scene: nil), heading: nil,
          line: opening[0].line, blocks: opening))
    }
    for (index, heading) in episode.headings.enumerated() {
      result.append(
        SceneSource(
          citation: SceneCitation(episode: episode.name, scene: heading.number),
          heading: episode.lines[heading.lineIndex].trimmingCharacters(in: .whitespaces),
          line: heading.lineIndex + 1,
          blocks: byScene[index] ?? []))
    }
    return result
  }

  static func sourceBlock(_ block: Block, in episode: Episode) -> SourceBlock {
    var lines: [String] = []
    var index = block.line
    while index < episode.lines.count {
      let line = episode.lines[index].trimmingCharacters(in: .whitespaces)
      if line.isEmpty { break }
      lines.append(line)
      index += 1
    }
    if lines.isEmpty { lines = block.texts }

    let kind: SourceBlock.Kind
    if block.isDialogue {
      kind = .dialogue(speaker: block.speaker, hasCue: block.cue != nil)
    } else if block.isAction {
      kind = .action
    } else {
      kind = .other
    }
    return SourceBlock(kind: kind, line: block.line + 1, lines: lines)
  }
}
