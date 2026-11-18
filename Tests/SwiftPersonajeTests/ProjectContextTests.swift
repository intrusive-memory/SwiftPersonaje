import Foundation
import Testing

@testable import SwiftPersonaje

/// VE-7: project context and accent, against the synthetic evidence fixture.
@Suite("Project context and accent (VE-7)")
struct ProjectContextTests {

  static let fixture = CharacterEvidenceTests.fixture

  @Test("Title, genre and description come from PROJECT.md")
  func readsTitleGenreDescription() throws {
    let context = try ProjectContext(directory: Self.fixture)
    #expect(context.title == "The Lantern Coast")
    #expect(context.genre == "Mystery")
    #expect(
      context.description
        == "A small harbour town, a lighthouse keeper and a missing ledger. Invented for SwiftPersonaje's evidence tests; CC0."
    )
    #expect(context.accent == "Lowland Coastal")
  }

  @Test("Members without their own accent inherit the project's, including the boys and NARRATOR")
  func accentInherited() async throws {
    let context = try ProjectContext(directory: Self.fixture)
    let corpus = try await EvidenceCorpus.load(screenplays: CharacterEvidenceTests.episodes)
    for member in ["PIP", "NED", "TOBY", "NARRATOR"] {
      let evidence = try await corpus.evidence(for: member, context: context)
      #expect(evidence.accent?.accent == "Lowland Coastal", "\(member)")
      #expect(evidence.accent?.source == .project, "\(member)")
    }
  }

  @Test("ODILE's own introduction overrides the project accent")
  func ownAccentOverridesProject() async throws {
    let context = try ProjectContext(directory: Self.fixture)
    let corpus = try await EvidenceCorpus.load(screenplays: CharacterEvidenceTests.episodes)
    let evidence = try await corpus.evidence(for: "ODILE", context: context)
    let accent = try #require(evidence.accent)
    #expect(accent.accent == "Northern Highland")
    guard case .evidence(let item) = accent.source else {
      Issue.record("expected evidence source, got \(accent.source)")
      return
    }
    #expect(item.kind == .introduction)
    #expect(item.episode == CharacterEvidenceTests.lamp)
    #expect(item.line == 12)
    #expect(item.sceneNumber == "0A")
  }

  @Test("No setting section and no accent in evidence gives nil")
  func missingSettingIsNil() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("project-context-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let text = """
      ---
      type: project
      title: Bare
      author: Nobody
      created: 2026-01-01T00:00:00Z
      ---

      # Bare
      """
    try text.write(
      to: directory.appendingPathComponent("PROJECT.md"), atomically: true, encoding: .utf8)
    let context = try ProjectContext(directory: directory)
    #expect(context.accent == nil)
    #expect(context.genre == nil)

    let corpus = try await EvidenceCorpus.load(screenplays: CharacterEvidenceTests.episodes)
    // No project accent: PIP's "thick coastal accent" still names one, but
    // FERRYMAN has no accent evidence at all.
    let ferryman = try await corpus.evidence(for: "FERRYMAN", context: context)
    #expect(ferryman.accent == nil)
  }

  @Test("Accent phrases drop manner adjectives and compare as word subsets")
  func accentPhraseRules() {
    #expect(
      AccentRules.phrase(in: "speaks with a clipped Northern Highland accent.")
        == "Northern Highland")
    #expect(AccentRules.phrase(in: "They each speak with a thick coastal accent.") == "coastal")
    #expect(AccentRules.phrase(in: "She has a thick accent.") == nil)
    #expect(AccentRules.isProjectAccent("coastal", project: "Lowland Coastal"))
    #expect(!AccentRules.isProjectAccent("Northern Highland", project: "Lowland Coastal"))
  }
}
