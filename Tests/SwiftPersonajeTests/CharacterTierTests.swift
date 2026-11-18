import Foundation
import SwiftReparto
import Testing

@testable import SwiftPersonaje

/// VE-6 (UD19): major/minor tier from block and scene shares.
@Suite("Character tier (VE-6)")
struct CharacterTierTests {

  static let fixture = CharacterEvidenceTests.fixture

  @Test("Exactly 8% of blocks is major, with under 15% of scenes")
  func exactlyEightPercentIsMajor() {
    // 8 of 100 blocks; 1 of 10 scenes (10%).
    let tier = CharacterTier.tier(
      memberBlocks: 8, totalBlocks: 100, memberScenes: 1, totalScenes: 10)
    #expect(tier == .major)
    // 2 of 25 blocks is exactly 8% too.
    #expect(
      CharacterTier.tier(memberBlocks: 2, totalBlocks: 25, memberScenes: 1, totalScenes: 20)
        == .major)
  }

  @Test("One block under 8% and under 15% of scenes is minor")
  func justUnderThresholdsIsMinor() {
    #expect(
      CharacterTier.tier(memberBlocks: 7, totalBlocks: 100, memberScenes: 1, totalScenes: 10)
        == .minor)
    // 2 of 26 blocks is 7.69%; 2 of 14 scenes is 14.28%.
    #expect(
      CharacterTier.tier(memberBlocks: 2, totalBlocks: 26, memberScenes: 2, totalScenes: 14)
        == .minor)
    #expect(
      CharacterTier.tier(memberBlocks: 0, totalBlocks: 0, memberScenes: 0, totalScenes: 0)
        == .minor)
  }

  @Test("Exactly 15% of scenes is major, with under 8% of blocks")
  func exactlyFifteenPercentOfScenesIsMajor() {
    #expect(
      CharacterTier.tier(memberBlocks: 1, totalBlocks: 100, memberScenes: 3, totalScenes: 20)
        == .major)
    #expect(
      CharacterTier.tier(memberBlocks: 1, totalBlocks: 100, memberScenes: 2, totalScenes: 14)
        == .minor)
  }

  @Test("A CAST.md role wins over the computed tier, even for TOBY in the fixture")
  func castRoleWins() async throws {
    let cast = try CastMarkdownParser().parse(
      fileURL: Self.fixture.appendingPathComponent("CAST.md"))
    let toby = try #require(cast.cast.first { $0.character == "TOBY" })
    #expect(toby.role == .supporting)

    let corpus = try await EvidenceCorpus.load(screenplays: CharacterEvidenceTests.episodes)
    let evidence = try await corpus.evidence(for: "TOBY")
    let counts = evidence.tierCounts(in: corpus)
    #expect(counts == CharacterTierCounts(memberBlocks: 1, totalBlocks: 31, memberScenes: 1, totalScenes: 11))
    #expect(evidence.tier(in: corpus) == .minor)
    #expect(evidence.tier(in: corpus, castRole: toby.role) == .major)

    // A minor role beats a computed major tier.
    #expect(
      CharacterTier.tier(
        memberBlocks: 50, totalBlocks: 100, memberScenes: 9, totalScenes: 10, castRole: .background)
        == .minor)

    // Members without a role are computed.
    let constable = try await corpus.evidence(for: "CONSTABLE")
    #expect(constable.tier(in: corpus) == .major)
    let ned = try await corpus.evidence(for: "NED")
    #expect(ned.tier(in: corpus) == .minor)
  }

  @Test("A forced .MUSIC CONTINUES line adds no scene: the project has 11")
  func forcedLineAddsNoScene() async throws {
    let quayURL = CharacterEvidenceTests.episodes[0]
    let text = try String(contentsOf: quayURL, encoding: .utf8)
    let forced = text.components(separatedBy: "\n").filter { $0.hasPrefix(".MUSIC CONTINUES") }
    #expect(forced.count == 1)

    let corpus = try await EvidenceCorpus.load(screenplays: CharacterEvidenceTests.episodes)
    #expect(corpus.sceneCount == 11)
    #expect(corpus.dialogueBlockCount == 31)

    // Removing the forced line leaves the scene count as it was.
    let without = text.components(separatedBy: "\n").filter { !$0.hasPrefix(".MUSIC CONTINUES") }
      .joined(separator: "\n")
    #expect(
      SceneNumbering.numberedHeadings(in: without).count
        == SceneNumbering.numberedHeadings(in: text).count)
  }
}
