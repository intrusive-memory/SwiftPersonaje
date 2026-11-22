import Foundation
import SwiftPersonaje
import Yams

/// A fact written by hand, with the quote and scene that show it.
public struct GoldFact: Sendable, Equatable, Codable {
  public let id: String
  public let statement: String
  public let quote: String
  /// The episode file's name, e.g. `episode_1_02_hunting_dilfs.fountain`.
  public let episode: String
  /// The SN-1 scene number, as Personaje shows it.
  public let scene: String?

  public init(id: String, statement: String, quote: String, episode: String, scene: String?) {
    self.id = id
    self.statement = statement
    self.quote = quote
    self.episode = episode
    self.scene = scene
  }

  public var citation: SceneCitation { SceneCitation(episode: episode, scene: scene) }
}

/// A plausible but wrong claim, and the phrases that would show a model made
/// it.
public struct ForbiddenClaim: Sendable, Equatable, Codable {
  public let id: String
  /// The wrong claim, for people: `"Hunter is in his fifties."`
  public let claim: String
  /// Phrases whose appearance (case-insensitive) in a fact or the summary
  /// counts as making the claim: `["fifties", "50s", "fifty"]`.
  public let phrases: [String]
}

/// One character's fixture, loaded from
/// `<fixtures>/<CHARACTER>/{gold-facts.yaml, gold-summary.md, must-not-say.yaml}`.
public struct CharacterFixture: Sendable, Equatable, Codable {
  public let member: String
  public let facts: [GoldFact]
  /// Facts not in `facts` that a run found and Tom accepted. They count
  /// toward precision, not recall.
  public let acceptable: [GoldFact]
  public let summary: String
  public let forbidden: [ForbiddenClaim]

  public init(
    member: String, facts: [GoldFact], acceptable: [GoldFact], summary: String,
    forbidden: [ForbiddenClaim]
  ) {
    self.member = member
    self.facts = facts
    self.acceptable = acceptable
    self.summary = summary
    self.forbidden = forbidden
  }

  /// `false` while any file still holds a `TODO` marker or `facts` is
  /// empty. Gold-based metrics are then reported as not scored.
  public var isComplete: Bool {
    !facts.isEmpty && !Self.hasTODO(self)
  }

  static func hasTODO(_ fixture: CharacterFixture) -> Bool {
    let texts =
      fixture.facts.flatMap { [$0.statement, $0.quote, $0.episode, $0.scene ?? ""] }
      + fixture.acceptable.flatMap { [$0.statement, $0.quote, $0.episode] }
      + fixture.forbidden.flatMap { [$0.claim] + $0.phrases } + [fixture.summary]
    return texts.contains { $0.contains("TODO") }
  }
}

public enum GoldFixtureError: Error, CustomStringConvertible {
  case missingFile(URL)
  case invalidYAML(URL, String)
  case noCharacters(URL)

  public var description: String {
    switch self {
    case .missingFile(let url): return "Missing fixture file: \(url.path)"
    case .invalidYAML(let url, let reason): return "Can't read \(url.path): \(reason)"
    case .noCharacters(let url): return "No character folders under \(url.path)"
    }
  }
}

public enum GoldFixtures {

  public static let factsFile = "gold-facts.yaml"
  public static let summaryFile = "gold-summary.md"
  public static let mustNotSayFile = "must-not-say.yaml"

  struct FactsFile: Codable {
    var facts: [GoldFact]?
    var acceptable: [GoldFact]?
  }

  struct MustNotSayFile: Codable {
    var claims: [ForbiddenClaim]?
  }

  /// Every character folder under `root`, in name order. A folder is a
  /// character when it holds `gold-facts.yaml`.
  public static func load(from root: URL) throws -> [CharacterFixture] {
    let folders = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
    )
    .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(factsFile).path) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !folders.isEmpty else { throw GoldFixtureError.noCharacters(root) }
    return try folders.map(loadCharacter)
  }

  public static func loadCharacter(at folder: URL) throws -> CharacterFixture {
    let facts: FactsFile = try decode(folder.appendingPathComponent(factsFile))
    let mustNotSay: MustNotSayFile = try decode(folder.appendingPathComponent(mustNotSayFile))
    let summaryURL = folder.appendingPathComponent(summaryFile)
    guard let summary = try? String(contentsOf: summaryURL, encoding: .utf8) else {
      throw GoldFixtureError.missingFile(summaryURL)
    }
    return CharacterFixture(
      member: folder.lastPathComponent, facts: facts.facts ?? [],
      acceptable: facts.acceptable ?? [], summary: stripComments(summary),
      forbidden: mustNotSay.claims ?? [])
  }

  static func decode<T: Decodable>(_ url: URL) throws -> T {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      throw GoldFixtureError.missingFile(url)
    }
    do {
      return try YAMLDecoder().decode(T.self, from: text)
    } catch {
      throw GoldFixtureError.invalidYAML(url, String(describing: error))
    }
  }

  /// The summary file without HTML comments (`<!-- ... -->`), which hold the
  /// file's instructions, trimmed.
  static func stripComments(_ text: String) -> String {
    text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
