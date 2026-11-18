import Foundation
import SwiftProyecto

/// The `setting` section of `PROJECT.md` front matter (VE-7), read through
/// SwiftProyecto's app-settings hook.
///
/// ```yaml
/// setting: { accent: "Lowland Coastal" }
/// ```
public struct PersonajeSetting: AppFrontMatterSettings, Equatable {
  public static var sectionKey: String { "setting" }

  /// The accent the whole project speaks with unless a member's own
  /// evidence says otherwise.
  public var accent: String?

  public init(accent: String? = nil) {
    self.accent = accent
  }
}

/// Where a member's accent came from (VE-7).
public enum AccentSource: Sendable, Equatable, Hashable, Codable {
  /// Inherited from `setting.accent` in `PROJECT.md`.
  case project
  /// Named by one of the member's own evidence items (an introduction or a
  /// group statement).
  case evidence(EvidenceItem)
}

/// A member's accent and its source (VE-7).
public struct MemberAccent: Sendable, Equatable, Hashable, Codable {
  /// The accent: for evidence, the phrase before the word "accent" with
  /// manner adjectives removed (`Northern Highland`).
  public let accent: String
  /// Where it came from.
  public let source: AccentSource

  public init(accent: String, source: AccentSource) {
    self.accent = accent
    self.source = source
  }
}

/// What `PROJECT.md` says about the project as a whole (VE-7): title, genre,
/// description and the project accent.
public struct ProjectContext: Sendable, Equatable, Hashable, Codable {
  public let title: String
  public let genre: String?
  public let description: String?
  /// `setting.accent`, or `nil` when the project has no `setting` section.
  public let accent: String?

  public init(title: String, genre: String? = nil, description: String? = nil, accent: String? = nil) {
    self.title = title
    self.genre = genre
    self.description = description
    self.accent = accent
  }

  /// Reads the context from parsed front matter.
  ///
  /// - Throws: SwiftProyecto's `DecodingError` when `setting` is present
  ///   but malformed.
  public init(frontMatter: ProjectFrontMatter) throws {
    let setting = try frontMatter.settings(for: PersonajeSetting.self)
    let accent = setting?.accent?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.init(
      title: frontMatter.title,
      genre: frontMatter.genre,
      description: frontMatter.description,
      accent: (accent?.isEmpty ?? true) ? nil : accent)
  }

  /// Reads the context of an opened project.
  public init(project: PersonajeProject) throws {
    try self.init(frontMatter: project.frontMatter)
  }

  /// Opens the project in `directory` (which must hold `PROJECT.md`) and
  /// reads its context.
  public init(directory: URL) throws {
    try self.init(project: try PersonajeProject(directory: directory))
  }
}

/// Accent rules (VE-7).
enum AccentRules {

  /// Words that describe how an accent sounds, not which one it is.
  static let mannerAdjectives: Set<String> = [
    "thick", "clipped", "heavy", "slight", "faint", "broad", "soft", "strong", "light",
    "pronounced", "noticeable", "distinct", "mild", "subtle",
  ]

  private static let pattern = try? NSRegularExpression(
    pattern: #"\b(?:an?|the|his|her|their)\s+((?:[A-Za-z'’-]+\s+){0,4}?)accent\b"#,
    options: [.caseInsensitive])

  /// The accent named in `text` ("with a clipped Northern Highland accent"
  /// → "Northern Highland"), or `nil` when it names none.
  static func phrase(in text: String) -> String? {
    guard let pattern else { return nil }
    let whole = NSRange(text.startIndex..., in: text)
    for match in pattern.matches(in: text, range: whole) {
      guard let range = Range(match.range(at: 1), in: text) else { continue }
      let words = text[range].split(whereSeparator: \.isWhitespace).map(String.init)
        .filter { !mannerAdjectives.contains($0.lowercased()) }
      if !words.isEmpty { return words.joined(separator: " ") }
    }
    return nil
  }

  /// The lowercased words of `phrase`.
  static func words(_ phrase: String) -> Set<String> {
    Set(
      phrase.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
        .map(String.init))
  }

  /// `true` when `candidate` is the project's own accent: its words are a
  /// subset of the project's (`coastal` ⊂ `Lowland Coastal`).
  static func isProjectAccent(_ candidate: String, project: String) -> Bool {
    let mine = words(candidate)
    return !mine.isEmpty && mine.isSubset(of: words(project))
  }

  private static let offScreen: Set<String> = ["V.O.", "O.S.", "PRELAP"]

  /// `true` when the member speaks in `item`'s scene and every one of
  /// those lines is V.O., O.S. or PRELAP.
  static func isOnlyOffScreen(in item: EvidenceItem, dialogue: [EvidenceItem]) -> Bool {
    let scene = dialogue.filter { $0.episode == item.episode && $0.sceneNumber == item.sceneNumber }
    guard !scene.isEmpty else { return false }
    return scene.allSatisfy { line in
      line.extensions.contains { offScreen.contains($0.uppercased()) }
    }
  }

  /// The member's accent: the first evidence item, by priority, that names
  /// an accent other than the project's; otherwise the project's accent;
  /// otherwise `nil`.
  static func accent(items: [EvidenceItem], project: String?) -> MemberAccent? {
    let dialogue = items.filter { $0.kind == .dialogue }
    let ordered =
      items.filter { $0.kind == .introduction }
      + items.filter { $0.kind == .groupStatement && $0.matchedName != nil }
      + items.filter { $0.kind == .groupStatement && $0.matchedName == nil }
    for item in ordered {
      if item.kind == .groupStatement, item.matchedName == nil,
        isOnlyOffScreen(in: item, dialogue: dialogue)
      {
        continue
      }
      guard let phrase = phrase(in: item.text) else { continue }
      if let project, isProjectAccent(phrase, project: project) { continue }
      return MemberAccent(accent: phrase, source: .evidence(item))
    }
    guard let project else { return nil }
    return MemberAccent(accent: project, source: .project)
  }
}
