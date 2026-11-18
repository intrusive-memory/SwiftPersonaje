import Foundation

/// One piece of evidence about a character, with its source (VE-1, VE-8).
///
/// Every item says where it came from: the episode file, the 1-based line it
/// starts on, the SN-1 number of the scene that holds it (SN-2), and its exact
/// text. A dialogue item also keeps its raw cue, so the cue extension
/// (`V.O.`, `O.S.`, `PRELAP`, `sotto`, …) that SwiftCompartido drops from the
/// speaker name survives.
public struct EvidenceItem: Sendable, Equatable, Hashable, Codable {

  /// What kind of evidence an item is. Later sorties add kinds
  /// (introduction, name variant, group statement); the raw values are
  /// stable strings, so encoded evidence stays readable as cases are added.
  public enum Kind: String, Sendable, Equatable, Hashable, Codable {
    /// A speech block of the character: cue, parentheticals and dialogue
    /// (VE-1).
    case dialogue
  }

  /// What kind of evidence this is.
  public let kind: Kind
  /// The episode file's name (for example `01-the-quay.fountain`).
  public let episode: String
  /// The 1-based line the item starts on in the episode file: for dialogue,
  /// the cue's line.
  public let line: Int
  /// The SN-1 number of the scene that holds the item (SN-2), or `nil` when
  /// the item comes before the episode's first scene heading.
  public let sceneNumber: String?
  /// The item's exact text. For dialogue: the parentheticals and dialogue
  /// under the cue, in order, joined by newlines (the cue itself is in
  /// ``cue``).
  public let text: String
  /// The raw cue line as written, extension included (`NARRATOR (V.O.)`).
  /// `nil` for kinds that have no cue.
  public let cue: String?
  /// The cue's extensions without their parentheses, in order
  /// (`NARRATOR (V.O.) (CONT'D)` → `["V.O.", "CONT'D"]`). Empty when the
  /// cue has none.
  public let extensions: [String]
  /// The block's parentheticals as written, parentheses included, in order.
  public let parentheticals: [String]

  public init(
    kind: Kind,
    episode: String,
    line: Int,
    sceneNumber: String?,
    text: String,
    cue: String? = nil,
    extensions: [String] = [],
    parentheticals: [String] = []
  ) {
    self.kind = kind
    self.episode = episode
    self.line = line
    self.sceneNumber = sceneNumber
    self.text = text
    self.cue = cue
    self.extensions = extensions
    self.parentheticals = parentheticals
  }
}

/// One block of a context window (VE-5): a dialogue block (cue,
/// parentheticals and dialogue) or one action paragraph or other body
/// element.
public struct EvidenceBlock: Sendable, Equatable, Hashable, Codable {
  /// The 1-based line the block starts on in the episode file.
  public let line: Int
  /// The speaker's name as SwiftCompartido cleans a cue (extensions removed,
  /// uppercased), or `nil` for a block that isn't dialogue.
  public let speaker: String?
  /// The raw cue line, extension included, or `nil` for a block that isn't
  /// dialogue.
  public let cue: String?
  /// The block's exact text. For dialogue: parentheticals and dialogue joined
  /// by newlines, without the cue.
  public let text: String
  /// `true` when this block is one of the character's own lines (a window
  /// centre).
  public let isMemberLine: Bool

  public init(line: Int, speaker: String?, cue: String?, text: String, isMemberLine: Bool) {
    self.line = line
    self.speaker = speaker
    self.cue = cue
    self.text = text
    self.isMemberLine = isMemberLine
  }
}

/// A character's lines with the blocks around them, inside one scene (VE-5).
///
/// A scene here is the scene rule's: it starts only at a slugline. A forced
/// `.` line (`.MUSIC CONTINUES`) is a block inside the scene before it and
/// never ends a window.
public struct EvidenceWindow: Sendable, Equatable, Hashable, Codable {
  /// The episode file's name.
  public let episode: String
  /// The SN-1 number of the window's scene, or `nil` before the first
  /// heading.
  public let sceneNumber: String?
  /// The scene heading line as written, or `nil` before the first heading.
  public let heading: String?
  /// The window's blocks in script order.
  public let blocks: [EvidenceBlock]

  public init(episode: String, sceneNumber: String?, heading: String?, blocks: [EvidenceBlock]) {
    self.episode = episode
    self.sceneNumber = sceneNumber
    self.heading = heading
    self.blocks = blocks
  }

  /// The 1-based line of the window's first block.
  public var firstLine: Int? { blocks.first?.line }
  /// The 1-based line of the window's last block.
  public var lastLine: Int? { blocks.last?.line }
}

/// Everything the screenplays say about one cast member, each item with its
/// source (VE-1, VE-5, VE-8).
///
/// Built by ``EvidenceCorpus/evidence(for:neighbours:)``. Later sorties add
/// derived properties (tier, accent) beside these.
public struct CharacterEvidence: Sendable, Equatable, Hashable, Codable {
  /// The member's `character` as CAST.md spells it.
  public let member: String
  /// The evidence items, ordered by episode (in the order the corpus was
  /// loaded) and then by line.
  public let items: [EvidenceItem]
  /// The member's context windows, in the same order.
  public let windows: [EvidenceWindow]

  public init(member: String, items: [EvidenceItem], windows: [EvidenceWindow]) {
    self.member = member
    self.items = items
    self.windows = windows
  }

  /// The dialogue items only.
  public var dialogue: [EvidenceItem] { items.filter { $0.kind == .dialogue } }
}

/// Cue parsing. SwiftCompartido's `cleanCharacterName` is internal and drops
/// the extension, so the raw cue is read here.
enum EvidenceCue {

  /// The speaker name exactly as SwiftCompartido cleans a cue: trimmed, cut
  /// at the first `(`, `^` removed, uppercased.
  static func speaker(of cue: String) -> String {
    var cleaned = cue.trimmingCharacters(in: .whitespaces)
    if let open = cleaned.firstIndex(of: "(") {
      cleaned = String(cleaned[..<open]).trimmingCharacters(in: .whitespaces)
    }
    cleaned = cleaned.replacingOccurrences(of: "^", with: "").trimmingCharacters(in: .whitespaces)
    return cleaned.uppercased()
  }

  /// Every `( … )` group after the name, contents trimmed, empty ones left
  /// out: `NARRATOR (V.O.)` → `["V.O."]`.
  static func extensions(of cue: String) -> [String] {
    var result: [String] = []
    var current: String?
    for character in cue {
      switch character {
      case "(":
        current = ""
      case ")":
        if let value = current?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
          result.append(value)
        }
        current = nil
      default:
        current?.append(character)
      }
    }
    return result
  }
}
